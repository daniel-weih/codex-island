import Foundation

/// Computes today's locally-persisted Token increments for root CLI/App
/// conversations. Absolute cumulative counters are reduced to positive deltas,
/// so replayed `token_count` notifications do not inflate the result.
enum CodexDailyTokenUsageReader {
    private static let cache = DailyTokenUsageCache()

    static func readToday(
        from rolloutPaths: [String],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Int64 {
        try cache.readToday(
            from: rolloutPaths,
            now: now,
            calendar: calendar
        )
    }

    /// Finds every locally-persisted root CLI/App rollout that could contain
    /// today's activity or a still-fresh cross-midnight running turn.
    static func discoverRootConversationRollouts(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [String] {
        try DailyTokenUsageCache.discoverRootConversationRollouts(
            now: now,
            calendar: calendar
        )
    }

    static func resetCacheForTesting() {
        cache.reset()
    }
}

private struct DailyTokenEvent {
    var timestamp: Date
    var totalTokens: Int64
    var lastTokens: Int64?
}

private struct DailyTokenFileEntry {
    var fileIdentity: String
    var fileSize: UInt64
    var modifiedAt: Date
    var previousTotal: Int64?
    var todayTotal: Int64
    var trailingLineStartOffset: UInt64?
    var isExcludedFork: Bool
}

private enum DailyTokenUsageError: LocalizedError {
    case noReadableRollouts

    var errorDescription: String? {
        switch self {
        case .noReadableRollouts:
            return "没有可读取的本地会话用量记录"
        }
    }
}

private final class DailyTokenUsageCache: @unchecked Sendable {
    private static let chunkSize = 64 * 1024
    private static let maximumRelevantLineSize = 64 * 1024
    private static let maximumSessionMetaSize = 512 * 1024
    private static let tokenCountMarker = Data("token_count".utf8)
    private static let freshRunningLookback: TimeInterval = 30 * 60

    private let lock = NSLock()
    private var dayStart: Date?
    private var nextDayStart: Date?
    private var entries: [String: DailyTokenFileEntry] = [:]

    private static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        dayStart = nil
        nextDayStart = nil
        entries.removeAll()
    }

    func readToday(
        from rolloutPaths: [String],
        now: Date,
        calendar: Calendar
    ) throws -> Int64 {
        let resolvedDayStart = calendar.startOfDay(for: now)
        guard let resolvedNextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: resolvedDayStart
        ) else {
            throw DailyTokenUsageError.noReadableRollouts
        }

        lock.lock()
        defer { lock.unlock() }

        if dayStart != resolvedDayStart || nextDayStart != resolvedNextDayStart {
            dayStart = resolvedDayStart
            nextDayStart = resolvedNextDayStart
            entries.removeAll()
        }

        let paths = Array(Set(rolloutPaths.filter { !$0.isEmpty })).sorted()
        guard !paths.isEmpty else { return 0 }

        var readableCount = 0
        var total: Int64 = 0
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            do {
                let entry = try refreshedEntry(
                    for: url,
                    dayStart: resolvedDayStart,
                    nextDayStart: resolvedNextDayStart
                )
                entries[url.path] = entry
                readableCount += 1
                total = Self.clampedAdd(total, entry.todayTotal)
            } catch {
                // A thread may disappear from the state index while it is being
                // archived. Preserve the rest of the independently readable sum.
                continue
            }
        }

        guard readableCount > 0 else {
            throw DailyTokenUsageError.noReadableRollouts
        }
        return total
    }

    static func discoverRootConversationRollouts(
        now: Date,
        calendar: Calendar
    ) throws -> [String] {
        let dayStart = calendar.startOfDay(for: now)
        let cutoff = min(
            dayStart,
            now.addingTimeInterval(-freshRunningLookback)
        )
        let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { ($0 as NSString).expandingTildeInPath }
        let codexHome = URL(fileURLWithPath: configuredHome
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true).path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        let roots = ["sessions", "archived_sessions"].map {
            codexHome.appendingPathComponent($0, isDirectory: true)
        }

        var paths: [String] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                let values = try? url.resourceValues(forKeys: Set(resourceKeys))
                guard values?.isRegularFile == true,
                      let modifiedAt = values?.contentModificationDate,
                      modifiedAt >= cutoff,
                      (try? isRootCLIOrAppRollout(url: url)) == true else {
                    continue
                }
                paths.append(url.standardizedFileURL.path)
            }
        }
        return Array(Set(paths)).sorted()
    }

    private func refreshedEntry(
        for url: URL,
        dayStart: Date,
        nextDayStart: Date
    ) throws -> DailyTokenFileEntry {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let fileIdentity = [
            (attributes[.systemNumber] as? NSNumber)?.stringValue,
            (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        ]
        .compactMap { $0 }
        .joined(separator: ":")

        if let cached = entries[url.path],
           cached.fileIdentity == fileIdentity,
           cached.fileSize == fileSize,
           cached.modifiedAt == modifiedAt {
            return cached
        }

        if var cached = entries[url.path],
           cached.fileIdentity == fileIdentity,
           fileSize > cached.fileSize {
            let originalSize = cached.fileSize
            let scanStart = min(
                cached.trailingLineStartOffset ?? originalSize,
                originalSize
            )
            cached.fileSize = fileSize
            cached.modifiedAt = modifiedAt
            if !cached.isExcludedFork {
                var previousTotal = cached.previousTotal
                var todayTotal = cached.todayTotal
                try Self.scanForward(
                    url: url,
                    from: scanStart,
                    to: fileSize
                ) { event in
                    Self.consume(
                        event,
                        previousTotal: &previousTotal,
                        todayTotal: &todayTotal,
                        dayStart: dayStart,
                        nextDayStart: nextDayStart
                    )
                }
                cached.previousTotal = previousTotal
                cached.todayTotal = todayTotal
                cached.trailingLineStartOffset = try Self.findTrailingLineStartOffset(
                    url: url,
                    fileSize: fileSize
                )
            }
            return cached
        }

        let excluded = try Self.isForkedOrSubagentRollout(url: url)
        var entry = DailyTokenFileEntry(
            fileIdentity: fileIdentity,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            previousTotal: nil,
            todayTotal: 0,
            trailingLineStartOffset: try Self.findTrailingLineStartOffset(
                url: url,
                fileSize: fileSize
            ),
            isExcludedFork: excluded
        )
        guard !excluded, modifiedAt >= dayStart else { return entry }

        let events = try Self.scanBackwardToDailyBaseline(
            url: url,
            fileSize: fileSize,
            dayStart: dayStart
        )
        for event in events.reversed() {
            Self.consume(
                event,
                previousTotal: &entry.previousTotal,
                todayTotal: &entry.todayTotal,
                dayStart: dayStart,
                nextDayStart: nextDayStart
            )
        }
        return entry
    }

    private static func consume(
        _ event: DailyTokenEvent,
        previousTotal: inout Int64?,
        todayTotal: inout Int64,
        dayStart: Date,
        nextDayStart: Date
    ) {
        let delta: Int64
        if let previousTotal {
            if event.totalTokens >= previousTotal {
                delta = event.totalTokens - previousTotal
            } else {
                delta = max(0, event.lastTokens ?? event.totalTokens)
            }
        } else {
            delta = max(0, event.lastTokens ?? event.totalTokens)
        }
        previousTotal = event.totalTokens

        guard event.timestamp >= dayStart, event.timestamp < nextDayStart else { return }
        todayTotal = clampedAdd(todayTotal, delta)
    }

    /// Returns newest-to-oldest events, including the first absolute counter
    /// before local midnight as the baseline for a cross-midnight conversation.
    private static func scanBackwardToDailyBaseline(
        url: URL,
        fileSize: UInt64,
        dayStart: Date
    ) throws -> [DailyTokenEvent] {
        var events: [DailyTokenEvent] = []
        try scanLinesBackward(url: url, fileSize: fileSize) { line in
            guard let event = parseTokenEvent(line) else { return true }
            events.append(event)
            return event.timestamp >= dayStart
        }
        return events
    }

    private static func scanLinesBackward(
        url: URL,
        fileSize: UInt64,
        consumeLine: (Data) -> Bool
    ) throws {
        guard fileSize > 0 else { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: fileSize - 1)
        let endsWithNewline = try handle.read(upToCount: 1)?.first == 0x0A
        var position = fileSize
        var suffix = Data()
        // JSONL records are committed by their trailing newline. Ignore an
        // otherwise-valid final JSON object until that delimiter is appended.
        var skippingOversizedLine = !endsWithNewline

        while position > 0 {
            let readCount = min(chunkSize, Int(position))
            position -= UInt64(readCount)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }

            let parts = chunk.split(
                separator: 0x0A,
                omittingEmptySubsequences: false
            )
            guard parts.count > 1 else {
                if !skippingOversizedLine {
                    if chunk.count + suffix.count <= maximumRelevantLineSize {
                        var combined = Data(capacity: chunk.count + suffix.count)
                        combined.append(chunk)
                        combined.append(suffix)
                        suffix = combined
                    } else {
                        suffix.removeAll(keepingCapacity: false)
                        skippingOversizedLine = true
                    }
                }
                continue
            }

            if skippingOversizedLine {
                skippingOversizedLine = false
            } else if let last = parts.last,
                      last.count + suffix.count <= maximumRelevantLineSize {
                var line = Data(capacity: last.count + suffix.count)
                line.append(contentsOf: last)
                line.append(suffix)
                if !line.isEmpty, !consumeLine(line) { return }
            }
            suffix.removeAll(keepingCapacity: false)

            if parts.count > 2 {
                for index in stride(from: parts.count - 2, through: 1, by: -1) {
                    let part = parts[index]
                    guard part.count <= maximumRelevantLineSize else { continue }
                    let line = Data(part)
                    if !line.isEmpty, !consumeLine(line) { return }
                }
            }

            let first = parts[0]
            if first.count <= maximumRelevantLineSize {
                suffix = Data(first)
            } else {
                skippingOversizedLine = true
            }
        }

        if !skippingOversizedLine, !suffix.isEmpty {
            _ = consumeLine(suffix)
        }
    }

    private static func scanForward(
        url: URL,
        from lowerBound: UInt64,
        to upperBound: UInt64,
        consumeEvent: (DailyTokenEvent) -> Void
    ) throws {
        guard upperBound > lowerBound else { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: lowerBound)

        var offset = lowerBound
        var line = Data()
        var skippingOversizedLine = false
        while offset < upperBound {
            let readCount = min(chunkSize, Int(upperBound - offset))
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }
            offset += UInt64(chunk.count)

            for byte in chunk {
                if byte == 0x0A {
                    if !skippingOversizedLine,
                       let event = parseTokenEvent(line) {
                        consumeEvent(event)
                    }
                    line.removeAll(keepingCapacity: true)
                    skippingOversizedLine = false
                } else if !skippingOversizedLine {
                    if line.count < maximumRelevantLineSize {
                        line.append(byte)
                    } else {
                        line.removeAll(keepingCapacity: false)
                        skippingOversizedLine = true
                    }
                }
            }
        }

        // `line` intentionally remains unconsumed without a newline. The
        // cached trailing offset makes the next poll re-read it from its start.
    }

    private static func parseTokenEvent(_ line: Data) -> DailyTokenEvent? {
        guard line.range(of: tokenCountMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              object.string("type") == "event_msg",
              let timestampString = object.string("timestamp"),
              let timestamp = parseTimestamp(timestampString),
              let payload = object.dictionary("payload"),
              payload.string("type") == "token_count",
              let info = payload.dictionary("info"),
              let totalUsage = info.dictionary("total_token_usage"),
              let totalTokens = int64(totalUsage["total_tokens"]),
              totalTokens >= 0 else {
            return nil
        }

        let lastTokens = info.dictionary("last_token_usage")
            .flatMap { int64($0["total_tokens"]) }
            .flatMap { $0 >= 0 ? $0 : nil }
        return DailyTokenEvent(
            timestamp: timestamp,
            totalTokens: totalTokens,
            lastTokens: lastTokens
        )
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        fractionalTimestampFormatter.date(from: value)
            ?? timestampFormatter.date(from: value)
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func isForkedOrSubagentRollout(url: URL) throws -> Bool {
        let line = try readSessionMetaLine(url: url)
        guard !line.isEmpty else { return false }
        if line.count > maximumSessionMetaSize {
            return containsForkOrSubagentMarker(line)
        }
        guard let payload = sessionMetaPayload(line) else { return false }
        return isForkedOrSubagent(payload)
    }

    private static func isRootCLIOrAppRollout(url: URL) throws -> Bool {
        let line = try readSessionMetaLine(url: url)
        guard !line.isEmpty else { return false }

        if let payload = sessionMetaPayload(line) {
            guard !isForkedOrSubagent(payload),
                  let source = payload.string("source")?.lowercased() else {
                return false
            }
            return source == "cli" || source == "vscode"
        }

        // `source` is near the beginning of session_meta. This fallback keeps
        // unusually large metadata rows discoverable without retaining them.
        guard !containsForkOrSubagentMarker(line) else { return false }
        return line.range(of: Data("\"source\":\"cli\"".utf8)) != nil
            || line.range(of: Data("\"source\":\"vscode\"".utf8)) != nil
    }

    private static func readSessionMetaLine(url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var line = Data()
        while line.count <= maximumSessionMetaSize {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            if let newline = chunk.firstIndex(of: 0x0A) {
                line.append(chunk[..<newline])
                break
            }
            line.append(chunk)
        }
        return line
    }

    private static func sessionMetaPayload(_ line: Data) -> JSONObject? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              object.string("type") == "session_meta",
              let payload = object.dictionary("payload") else {
            return nil
        }
        return payload
    }

    private static func isForkedOrSubagent(_ payload: JSONObject) -> Bool {
        if let forkedFromID = payload.string("forked_from_id"),
           !forkedFromID.trimmingCharacters(
               in: CharacterSet.whitespacesAndNewlines
           ).isEmpty {
            return true
        }
        if payload.string("thread_source")?.lowercased() == "subagent" {
            return true
        }
        return payload.dictionary("source")?.dictionary("subagent") != nil
    }

    private static func containsForkOrSubagentMarker(_ line: Data) -> Bool {
        line.range(of: Data("\"forked_from_id\"".utf8)) != nil
            || line.range(of: Data("\"thread_source\":\"subagent\"".utf8)) != nil
            || line.range(of: Data("\"source\":{\"subagent\"".utf8)) != nil
    }

    private static func findTrailingLineStartOffset(
        url: URL,
        fileSize: UInt64
    ) throws -> UInt64? {
        guard fileSize > 0 else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: fileSize - 1)
        if try handle.read(upToCount: 1)?.first == 0x0A { return nil }

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

    private static func clampedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(max(0, rhs))
        return overflow ? Int64.max : result
    }
}
