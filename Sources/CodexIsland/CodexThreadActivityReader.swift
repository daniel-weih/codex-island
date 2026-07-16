import Foundation

/// Reads the latest persisted turn lifecycle without decoding message contents.
/// Initial reads scan backwards; subsequent reads inspect newly appended bytes,
/// re-reading the exact unterminated final record only when necessary.
enum CodexThreadActivityReader {
    private static let chunkSize = 64 * 1024
    private static let defaultRunningStaleInterval: TimeInterval = 30 * 60
    private static let taskStartedMarker = Data("task_started".utf8)
    private static let taskCompleteMarker = Data("task_complete".utf8)
    private static let turnAbortedMarker = Data("turn_aborted".utf8)
    private static let tokenCountMarker = Data("token_count".utf8)
    private static let errorMarker = Data("\"type\":\"error\"".utf8)
    private static let cache = ThreadActivityCache()

    static func readLatest(
        from rolloutPath: String,
        threadID: String? = nil,
        validatePath: Bool = true,
        now: Date = Date(),
        staleInterval: TimeInterval = defaultRunningStaleInterval
    ) throws -> ThreadActivitySnapshot {
        let url = try CodexThreadSettingsReader.rolloutURL(
            from: rolloutPath,
            threadID: threadID,
            validatePath: validatePath
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let fileIdentity = [
            (attributes[.systemNumber] as? NSNumber)?.stringValue,
            (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        ]
        .compactMap { $0 }
        .joined(separator: ":")

        if let cached = cache.entry(for: url.path),
           cached.fileIdentity == fileIdentity,
           cached.fileSize == fileSize,
           cached.modifiedAt == modifiedAt {
            return makeSnapshot(
                reducer: cached.reducer,
                modifiedAt: modifiedAt,
                now: now,
                staleInterval: staleInterval
            )
        }

        let previous = cache.entry(for: url.path)
        let reducer: ActivityReducer
        if let previous,
           previous.fileIdentity == fileIdentity,
           fileSize > previous.fileSize {
            reducer = try scanAppendedBytes(
                url: url,
                fileSize: fileSize,
                previousFileSize: previous.fileSize,
                trailingLineStartOffset: previous.trailingLineStartOffset,
                initialReducer: previous.reducer
            )
        } else {
            reducer = try scanBackwards(url: url, fileSize: fileSize)
        }

        let trailingLineStartOffset = try findTrailingLineStartOffset(
            url: url,
            fileSize: fileSize
        )
        let snapshot = makeSnapshot(
            reducer: reducer,
            modifiedAt: modifiedAt,
            now: now,
            staleInterval: staleInterval
        )
        cache.store(
            ThreadActivityCacheEntry(
                fileIdentity: fileIdentity,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                reducer: reducer,
                trailingLineStartOffset: trailingLineStartOffset
            ),
            for: url.path
        )
        return snapshot
    }

    private static func makeSnapshot(
        reducer: ActivityReducer,
        modifiedAt: Date,
        now: Date,
        staleInterval: TimeInterval
    ) -> ThreadActivitySnapshot {
        ThreadActivitySnapshot(
            executionState: reducer.resolvedExecutionState(
                now: now,
                fileModifiedAt: modifiedAt,
                staleInterval: staleInterval
            ),
            tokenUsage: reducer.tokenUsage,
            updatedAt: modifiedAt
        )
    }

    private static func scanAppendedBytes(
        url: URL,
        fileSize: UInt64,
        previousFileSize: UInt64,
        trailingLineStartOffset: UInt64?,
        initialReducer: ActivityReducer
    ) throws -> ActivityReducer {
        // If the previous poll ended in the middle of a JSONL record, resume
        // at that record's exact start. A fixed-size overlap can begin inside
        // a record larger than the overlap and permanently miss its event.
        let lowerBound = min(trailingLineStartOffset ?? previousFileSize, previousFileSize)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: lowerBound)

        var offset = lowerBound
        var carry = Data()
        var reducer = initialReducer

        while offset < fileSize {
            let readCount = min(chunkSize, Int(fileSize - offset))
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }
            offset += UInt64(chunk.count)

            var block = Data(capacity: carry.count + chunk.count)
            block.append(carry)
            block.append(chunk)
            let lines = block.split(separator: 0x0A, omittingEmptySubsequences: false)
            if let lastLine = lines.last {
                carry = Data(lastLine)
            } else {
                carry.removeAll(keepingCapacity: true)
            }

            for line in lines.dropLast() {
                if let event = parseRolloutEvent(line) {
                    reducer.consume(event)
                }
            }
        }

        if let event = parseRolloutEvent(carry) {
            reducer.consume(event)
        }
        return reducer
    }

    /// Returns the exact start offset of a non-newline-terminated final record.
    /// Only an offset is cached, so even unusually large JSONL records do not
    /// remain resident in memory between polls.
    private static func findTrailingLineStartOffset(
        url: URL,
        fileSize: UInt64
    ) throws -> UInt64? {
        guard fileSize > 0 else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: fileSize - 1)
        if try handle.read(upToCount: 1)?.first == 0x0A {
            return nil
        }

        var position = fileSize
        while position > 0 {
            let readCount = min(chunkSize, Int(position))
            position -= UInt64(readCount)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            if let newlineIndex = chunk.lastIndex(of: 0x0A) {
                return position + UInt64(newlineIndex + 1)
            }
        }
        return 0
    }

    private static func scanBackwards(
        url: URL,
        fileSize: UInt64
    ) throws -> ActivityReducer {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var position = fileSize
        var carry = Data()
        var reverseLifecycleEvents: [RolloutEvent] = []
        var latestTokenUsage: ThreadTokenUsage?
        var foundLatestStart = false

        while position > 0 {
            let readCount = min(chunkSize, Int(position))
            position -= UInt64(readCount)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }

            var block = Data(capacity: chunk.count + carry.count)
            block.append(chunk)
            block.append(carry)
            let lines = block.split(separator: 0x0A, omittingEmptySubsequences: false)
            guard lines.count > 1 else {
                carry = block
                continue
            }

            carry = Data(lines[0])
            for line in lines.dropFirst().reversed() {
                guard let event = parseRolloutEvent(line) else { continue }
                collectBackward(
                    event,
                    reverseLifecycleEvents: &reverseLifecycleEvents,
                    latestTokenUsage: &latestTokenUsage,
                    foundLatestStart: &foundLatestStart
                )
                if foundLatestStart, latestTokenUsage != nil {
                    return reduceChronologically(
                        reverseLifecycleEvents.reversed(),
                        tokenUsage: latestTokenUsage
                    )
                }
            }
        }

        if let event = parseRolloutEvent(carry) {
            collectBackward(
                event,
                reverseLifecycleEvents: &reverseLifecycleEvents,
                latestTokenUsage: &latestTokenUsage,
                foundLatestStart: &foundLatestStart
            )
        }
        return reduceChronologically(
            reverseLifecycleEvents.reversed(),
            tokenUsage: latestTokenUsage
        )
    }

    private static func collectBackward(
        _ event: RolloutEvent,
        reverseLifecycleEvents: inout [RolloutEvent],
        latestTokenUsage: inout ThreadTokenUsage?,
        foundLatestStart: inout Bool
    ) {
        if case .tokenUsage(let usage) = event {
            if latestTokenUsage == nil {
                latestTokenUsage = usage
            }
            return
        }

        // Once the newest task_started is found, older lifecycle events belong
        // to previous turns. Continue only far enough to recover cumulative
        // token usage for a newly-started turn that has not emitted a count yet.
        guard !foundLatestStart else { return }
        reverseLifecycleEvents.append(event)
        if case .started = event {
            foundLatestStart = true
        }
    }

    private static func parseRolloutEvent<D: DataProtocol>(
        _ line: D
    ) -> RolloutEvent? {
        let data = Data(line)
        guard data.range(of: taskStartedMarker) != nil
                || data.range(of: taskCompleteMarker) != nil
                || data.range(of: turnAbortedMarker) != nil
                || data.range(of: tokenCountMarker) != nil
                || data.range(of: errorMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? JSONObject,
              object.string("type") == "event_msg",
              let payload = object.dictionary("payload") else {
            return nil
        }

        let turnID = payload.string("turn_id")
        switch payload.string("type") {
        case "task_started":
            return .started(
                turnID: turnID,
                occurredAt: eventDate(object: object, payload: payload)
            )
        case "task_complete": return .completed(turnID: turnID)
        case "turn_aborted": return .aborted(turnID: turnID)
        case "error": return .failed
        case "token_count":
            guard let usage = parseTokenUsage(payload) else { return nil }
            return .tokenUsage(usage)
        default: return nil
        }
    }

    private static func parseTokenUsage(_ payload: JSONObject) -> ThreadTokenUsage? {
        guard let totalUsage = payload.dictionary("info")?
            .dictionary("total_token_usage"),
            let totalTokens = totalUsage.int64("total_tokens") else {
            return nil
        }

        return ThreadTokenUsage(
            inputTokens: totalUsage.int64("input_tokens") ?? 0,
            cachedInputTokens: totalUsage.int64("cached_input_tokens") ?? 0,
            outputTokens: totalUsage.int64("output_tokens") ?? 0,
            reasoningOutputTokens: totalUsage.int64("reasoning_output_tokens") ?? 0,
            totalTokens: totalTokens
        )
    }

    private static func eventDate(object: JSONObject, payload: JSONObject) -> Date? {
        if let timestamp = object.string("timestamp") {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: timestamp) {
                return date
            }

            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = wholeSeconds.date(from: timestamp) {
                return date
            }
        }

        if let startedAt = payload["started_at"] as? NSNumber {
            return Date(timeIntervalSince1970: startedAt.doubleValue)
        }
        return nil
    }

    private static func reduceChronologically<S: Sequence>(
        _ events: S,
        tokenUsage: ThreadTokenUsage? = nil
    ) -> ActivityReducer where S.Element == RolloutEvent {
        var reducer = ActivityReducer()
        for event in events {
            reducer.consume(event)
        }
        reducer.tokenUsage = tokenUsage ?? reducer.tokenUsage
        return reducer
    }
}

private enum RolloutEvent {
    case started(turnID: String?, occurredAt: Date?)
    case completed(turnID: String?)
    case aborted(turnID: String?)
    case failed
    case tokenUsage(ThreadTokenUsage)
}

private struct ActivityReducer {
    var executionState: ThreadExecutionState = .unknown
    var activeTurnID: String?
    var activeStartedAt: Date?
    var tokenUsage: ThreadTokenUsage?

    mutating func consume(_ event: RolloutEvent) {
        switch event {
        case .started(let turnID, let occurredAt):
            activeTurnID = turnID
            activeStartedAt = occurredAt
            executionState = .running

        case .failed:
            executionState = .failed

        case .completed(let turnID):
            guard terminalMatches(turnID) else { return }
            if executionState != .failed && executionState != .interrupted {
                executionState = .idle
            }
            activeTurnID = nil
            activeStartedAt = nil

        case .aborted(let turnID):
            guard terminalMatches(turnID) else { return }
            executionState = .interrupted
            activeTurnID = nil
            activeStartedAt = nil

        case .tokenUsage(let usage):
            tokenUsage = usage
        }
    }

    func resolvedExecutionState(
        now: Date,
        fileModifiedAt: Date,
        staleInterval: TimeInterval
    ) -> ThreadExecutionState {
        guard executionState == .running else { return executionState }

        // Both the lifecycle timestamp and subsequent rollout writes are
        // evidence of freshness. An unmatched start older than the conservative
        // window is ambiguous (for example, a killed client), not an interruption.
        let freshnessDate = max(activeStartedAt ?? .distantPast, fileModifiedAt)
        guard freshnessDate != .distantPast,
              now.timeIntervalSince(freshnessDate) > max(0, staleInterval) else {
            return .running
        }
        return .unknown
    }

    private func terminalMatches(_ turnID: String?) -> Bool {
        guard let activeTurnID, let turnID else { return true }
        return activeTurnID == turnID
    }
}

private struct ThreadActivityCacheEntry {
    var fileIdentity: String
    var fileSize: UInt64
    var modifiedAt: Date
    var reducer: ActivityReducer
    var trailingLineStartOffset: UInt64?
}

private final class ThreadActivityCache: @unchecked Sendable {
    private let maximumEntryCount = 32
    private let lock = NSLock()
    private var entries: [String: ThreadActivityCacheEntry] = [:]
    private var accessOrder: [String] = []

    func entry(for path: String) -> ThreadActivityCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path] else { return nil }
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)
        return entry
    }

    func store(_ entry: ThreadActivityCacheEntry, for path: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[path] = entry
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)
        while accessOrder.count > maximumEntryCount {
            let evictedPath = accessOrder.removeFirst()
            entries.removeValue(forKey: evictedPath)
        }
    }
}
