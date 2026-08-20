import Foundation

struct LocalTokenUsageSnapshot: Equatable, Sendable {
    var todayTokens: Int64
    var hourlyBuckets: [HourlyUsageBucket]
}

/// Computes recent locally-persisted Token increments for CLI/App model calls.
/// Absolute cumulative counters are reduced to positive deltas, so replayed
/// `token_count` notifications do not inflate the result. Forks use their own
/// session timestamp, while subagents use their explicit activity boundary, so
/// copied parent history is excluded while new work remains visible.
enum CodexDailyTokenUsageReader {
    static let recentHourCount = 48
    private static let cache = DailyTokenUsageCache()

    static func readToday(
        from rolloutPaths: [String],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Int64 {
        try readRecentHours(
            from: rolloutPaths,
            now: now,
            calendar: calendar
        ).todayTokens
    }

    static func readRecentHours(
        from rolloutPaths: [String],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> LocalTokenUsageSnapshot {
        try cache.readRecentHours(
            from: rolloutPaths,
            now: now,
            calendar: calendar,
            hourCount: recentHourCount
        )
    }

    /// Finds every local CLI/App rollout that could contain model calls in the
    /// rolling hourly chart or a still-fresh running turn.
    static func discoverLocalUsageRollouts(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [String] {
        try DailyTokenUsageCache.discoverLocalUsageRollouts(
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
    var hourlyTotals: [Date: Int64]
    var trailingLineStartOffset: UInt64?
    var countingStart: Date
    var isExcluded: Bool
    var isWaitingForSubagentBoundary: Bool
    var subagentBoundarySearchOffset: UInt64?
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
    private static let boundarySearchChunkSize = 1024 * 1024
    private static let maximumRelevantLineSize = 64 * 1024
    private static let maximumSessionMetaSize = 512 * 1024
    private static let tokenCountMarker = Data("token_count".utf8)
    private static let subagentBoundaryMarker = Data(
        "inter_agent_communication_metadata".utf8
    )
    private static let freshRunningLookback: TimeInterval = 30 * 60

    private let lock = NSLock()
    private var dayStart: Date?
    private var nextDayStart: Date?
    private var hourlyRangeStart: Date?
    private var hourlyRangeEnd: Date?
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
        hourlyRangeStart = nil
        hourlyRangeEnd = nil
        entries.removeAll()
    }

    func readRecentHours(
        from rolloutPaths: [String],
        now: Date,
        calendar: Calendar,
        hourCount: Int
    ) throws -> LocalTokenUsageSnapshot {
        guard hourCount > 0,
              let currentHourStart = calendar.dateInterval(
                of: .hour,
                for: now
              )?.start,
              let resolvedHourlyRangeStart = calendar.date(
                byAdding: .hour,
                value: -(hourCount - 1),
                to: currentHourStart
              ),
              let resolvedHourlyRangeEnd = calendar.date(
                byAdding: .hour,
                value: 1,
                to: currentHourStart
              ) else {
            throw DailyTokenUsageError.noReadableRollouts
        }
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

        if dayStart != resolvedDayStart
            || nextDayStart != resolvedNextDayStart
            || hourlyRangeStart != resolvedHourlyRangeStart
            || hourlyRangeEnd != resolvedHourlyRangeEnd {
            dayStart = resolvedDayStart
            nextDayStart = resolvedNextDayStart
            hourlyRangeStart = resolvedHourlyRangeStart
            hourlyRangeEnd = resolvedHourlyRangeEnd
            entries.removeAll()
        }

        let paths = Array(Set(rolloutPaths.filter { !$0.isEmpty })).sorted()
        guard !paths.isEmpty else {
            return LocalTokenUsageSnapshot(
                todayTokens: 0,
                hourlyBuckets: Self.emptyHourlyBuckets(
                    startingAt: resolvedHourlyRangeStart,
                    count: hourCount,
                    calendar: calendar
                )
            )
        }

        var readableCount = 0
        var total: Int64 = 0
        var hourlyTotals: [Date: Int64] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            do {
                let entry = try refreshedEntry(
                    for: url,
                    dayStart: resolvedDayStart,
                    nextDayStart: resolvedNextDayStart,
                    hourlyRangeStart: resolvedHourlyRangeStart,
                    hourlyRangeEnd: resolvedHourlyRangeEnd,
                    calendar: calendar
                )
                entries[url.path] = entry
                readableCount += 1
                total = Self.clampedAdd(total, entry.todayTotal)
                for (hourStart, tokens) in entry.hourlyTotals {
                    hourlyTotals[hourStart] = Self.clampedAdd(
                        hourlyTotals[hourStart, default: 0],
                        tokens
                    )
                }
            } catch {
                // A thread may disappear from the state index while it is being
                // archived. Preserve the rest of the independently readable sum.
                continue
            }
        }

        guard readableCount > 0 else {
            throw DailyTokenUsageError.noReadableRollouts
        }
        let buckets = Self.emptyHourlyBuckets(
            startingAt: resolvedHourlyRangeStart,
            count: hourCount,
            calendar: calendar
        ).map { bucket in
            HourlyUsageBucket(
                hourStart: bucket.hourStart,
                tokens: hourlyTotals[bucket.hourStart] ?? 0
            )
        }
        return LocalTokenUsageSnapshot(
            todayTokens: total,
            hourlyBuckets: buckets
        )
    }

    static func discoverLocalUsageRollouts(
        now: Date,
        calendar: Calendar
    ) throws -> [String] {
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let historyStart = calendar.date(
            byAdding: .hour,
            value: -(CodexDailyTokenUsageReader.recentHourCount - 1),
            to: currentHourStart
        ) ?? currentHourStart
        let cutoff = min(
            historyStart,
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
                      (try? isLocalUsageRollout(url: url)) == true else {
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
        nextDayStart: Date,
        hourlyRangeStart: Date,
        hourlyRangeEnd: Date,
        calendar: Calendar
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
           fileSize > cached.fileSize,
           cached.isWaitingForSubagentBoundary {
            let search = try Self.firstSubagentActivityBoundary(
                url: url,
                fileSize: fileSize,
                startingAt: cached.subagentBoundarySearchOffset ?? 0
            )
            cached.fileSize = fileSize
            cached.modifiedAt = modifiedAt
            cached.trailingLineStartOffset = try Self.findTrailingLineStartOffset(
                url: url,
                fileSize: fileSize
            )
            cached.subagentBoundarySearchOffset = search.activityStartedAt == nil
                ? search.nextSearchOffset
                : nil

            guard let activityStartedAt = search.activityStartedAt else {
                return cached
            }

            cached.countingStart = max(hourlyRangeStart, activityStartedAt)
            cached.isExcluded = false
            cached.isWaitingForSubagentBoundary = false
            cached.previousTotal = nil
            cached.todayTotal = 0
            cached.hourlyTotals = [:]
            let resumedCountingStart = cached.countingStart
            guard modifiedAt >= resumedCountingStart else { return cached }

            let events = try Self.scanBackwardToDailyBaseline(
                url: url,
                fileSize: fileSize,
                dayStart: resumedCountingStart
            )
            for event in events.reversed() {
                Self.consume(
                    event,
                    previousTotal: &cached.previousTotal,
                    todayTotal: &cached.todayTotal,
                    hourlyTotals: &cached.hourlyTotals,
                    countingStart: resumedCountingStart,
                    dayStart: dayStart,
                    nextDayStart: nextDayStart,
                    hourlyRangeStart: hourlyRangeStart,
                    hourlyRangeEnd: hourlyRangeEnd,
                    calendar: calendar
                )
            }
            return cached
        }

        if var cached = entries[url.path],
           cached.fileIdentity == fileIdentity,
           fileSize > cached.fileSize,
           !cached.isWaitingForSubagentBoundary {
            let originalSize = cached.fileSize
            let scanStart = min(
                cached.trailingLineStartOffset ?? originalSize,
                originalSize
            )
            cached.fileSize = fileSize
            cached.modifiedAt = modifiedAt
            if !cached.isExcluded {
                var previousTotal = cached.previousTotal
                var todayTotal = cached.todayTotal
                var hourlyTotals = cached.hourlyTotals
                try Self.scanForward(
                    url: url,
                    from: scanStart,
                    to: fileSize
                ) { event in
                    Self.consume(
                        event,
                        previousTotal: &previousTotal,
                        todayTotal: &todayTotal,
                        hourlyTotals: &hourlyTotals,
                        countingStart: cached.countingStart,
                        dayStart: dayStart,
                        nextDayStart: nextDayStart,
                        hourlyRangeStart: hourlyRangeStart,
                        hourlyRangeEnd: hourlyRangeEnd,
                        calendar: calendar
                    )
                }
                cached.previousTotal = previousTotal
                cached.todayTotal = todayTotal
                cached.hourlyTotals = hourlyTotals
                cached.trailingLineStartOffset = try Self.findTrailingLineStartOffset(
                    url: url,
                    fileSize: fileSize
                )
            }
            return cached
        }

        let session = try Self.localUsageSession(url: url, fileSize: fileSize)
        let countingStart = max(
            hourlyRangeStart,
            session.activityStartedAt ?? session.startedAt ?? hourlyRangeStart
        )
        var entry = DailyTokenFileEntry(
            fileIdentity: fileIdentity,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            previousTotal: nil,
            todayTotal: 0,
            hourlyTotals: [:],
            trailingLineStartOffset: try Self.findTrailingLineStartOffset(
                url: url,
                fileSize: fileSize
            ),
            countingStart: countingStart,
            isExcluded: !session.isIncluded || session.isWaitingForActivityBoundary,
            isWaitingForSubagentBoundary: session.isWaitingForActivityBoundary,
            subagentBoundarySearchOffset: session.subagentBoundarySearchOffset
        )
        guard !entry.isExcluded, modifiedAt >= countingStart else { return entry }

        let events = try Self.scanBackwardToDailyBaseline(
            url: url,
            fileSize: fileSize,
            dayStart: countingStart
        )
        for event in events.reversed() {
            Self.consume(
                event,
                previousTotal: &entry.previousTotal,
                todayTotal: &entry.todayTotal,
                hourlyTotals: &entry.hourlyTotals,
                countingStart: countingStart,
                dayStart: dayStart,
                nextDayStart: nextDayStart,
                hourlyRangeStart: hourlyRangeStart,
                hourlyRangeEnd: hourlyRangeEnd,
                calendar: calendar
            )
        }
        return entry
    }

    private static func consume(
        _ event: DailyTokenEvent,
        previousTotal: inout Int64?,
        todayTotal: inout Int64,
        hourlyTotals: inout [Date: Int64],
        countingStart: Date,
        dayStart: Date,
        nextDayStart: Date,
        hourlyRangeStart: Date,
        hourlyRangeEnd: Date,
        calendar: Calendar
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

        guard event.timestamp >= countingStart else { return }
        if event.timestamp >= dayStart, event.timestamp < nextDayStart {
            todayTotal = clampedAdd(todayTotal, delta)
        }
        if event.timestamp >= hourlyRangeStart,
           event.timestamp < hourlyRangeEnd,
           let hourStart = calendar.dateInterval(
            of: .hour,
            for: event.timestamp
           )?.start {
            hourlyTotals[hourStart] = clampedAdd(
                hourlyTotals[hourStart, default: 0],
                delta
            )
        }
    }

    private static func emptyHourlyBuckets(
        startingAt start: Date,
        count: Int,
        calendar: Calendar
    ) -> [HourlyUsageBucket] {
        (0..<count).compactMap { offset in
            calendar.date(byAdding: .hour, value: offset, to: start).map {
                HourlyUsageBucket(hourStart: $0, tokens: 0)
            }
        }
    }

    /// Returns newest-to-oldest events, including the first absolute counter
    /// before the requested range as the cumulative baseline.
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

    private struct LocalUsageSession {
        var startedAt: Date?
        var activityStartedAt: Date?
        var isIncluded: Bool
        var isWaitingForActivityBoundary: Bool
        var subagentBoundarySearchOffset: UInt64?
    }

    private struct SubagentBoundarySearchResult {
        var activityStartedAt: Date?
        var nextSearchOffset: UInt64
    }

    private enum SubagentBoundaryCandidateLine {
        case committed(Data)
        case pending
        case skip
    }

    private static func localUsageSession(
        url: URL,
        fileSize: UInt64
    ) throws -> LocalUsageSession {
        let line = try readSessionMetaLine(url: url)
        guard !line.isEmpty else {
            return LocalUsageSession(
                startedAt: nil,
                activityStartedAt: nil,
                isIncluded: false,
                isWaitingForActivityBoundary: false,
                subagentBoundarySearchOffset: nil
            )
        }
        guard let object = sessionMetaObject(line),
              let payload = object.dictionary("payload") else {
            return LocalUsageSession(
                startedAt: nil,
                activityStartedAt: nil,
                isIncluded: containsLocalUsageSourceMarker(line),
                isWaitingForActivityBoundary: false,
                subagentBoundarySearchOffset: nil
            )
        }
        let isSubagent = isSubagentUsageSession(payload)
        let boundarySearch = isSubagent
            ? try firstSubagentActivityBoundary(
                url: url,
                fileSize: fileSize,
                startingAt: 0
            )
            : nil
        let activityStartedAt = boundarySearch?.activityStartedAt
        return LocalUsageSession(
            startedAt: object.string("timestamp").flatMap(parseTimestamp),
            activityStartedAt: activityStartedAt,
            isIncluded: isLocalUsageSession(payload),
            isWaitingForActivityBoundary: isSubagent && activityStartedAt == nil,
            subagentBoundarySearchOffset: activityStartedAt == nil
                ? boundarySearch?.nextSearchOffset
                : nil
        )
    }

    private static func isLocalUsageRollout(url: URL) throws -> Bool {
        let line = try readSessionMetaLine(url: url)
        guard let object = sessionMetaObject(line),
              let payload = object.dictionary("payload") else {
            return containsLocalUsageSourceMarker(line)
        }
        return isLocalUsageSession(payload)
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

    private static func sessionMetaObject(_ line: Data) -> JSONObject? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              object.string("type") == "session_meta" else {
            return nil
        }
        return object
    }

    private static func isLocalUsageSession(_ payload: JSONObject) -> Bool {
        if let source = payload.string("source")?.lowercased(),
           source == "cli" || source == "vscode" {
            return true
        }
        return isSubagentUsageSession(payload)
    }

    private static func isSubagentUsageSession(_ payload: JSONObject) -> Bool {
        payload.string("thread_source")?.lowercased() == "subagent"
            || payload.dictionary("source")?.dictionary("subagent") != nil
    }

    private static func containsLocalUsageSourceMarker(_ line: Data) -> Bool {
        line.range(of: Data("\"source\":\"cli\"".utf8)) != nil
            || line.range(of: Data("\"source\":\"vscode\"".utf8)) != nil
            || line.range(of: Data("\"thread_source\":\"subagent\"".utf8)) != nil
            || line.range(of: Data("\"source\":{\"subagent\"".utf8)) != nil
    }

    /// A spawned subagent rollout begins with a timestamp-rewritten replay of
    /// its parent's history. The first inter-agent metadata row separates that
    /// replay from work performed by the child itself. Until the row is fully
    /// committed, the rollout must contribute zero rather than briefly showing
    /// the copied cumulative counters as new usage.
    private static func firstSubagentActivityBoundary(
        url: URL,
        fileSize: UInt64,
        startingAt requestedStart: UInt64
    ) throws -> SubagentBoundarySearchResult {
        guard fileSize > 0 else {
            return SubagentBoundarySearchResult(
                activityStartedAt: nil,
                nextSearchOffset: 0
            )
        }

        let overlapCount = max(0, subagentBoundaryMarker.count - 1)
        let startingAt = min(requestedStart, fileSize)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: startingAt)

        var readOffset = startingAt
        var carry = Data()
        var candidateFloor = startingAt
        while readOffset < fileSize {
            let readCount = min(
                boundarySearchChunkSize,
                Int(fileSize - readOffset)
            )
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }

            var haystack = Data(capacity: carry.count + chunk.count)
            haystack.append(carry)
            haystack.append(chunk)
            let haystackOffset = readOffset - UInt64(carry.count)
            var searchStart = haystack.startIndex

            while searchStart < haystack.endIndex,
                  let range = haystack.range(
                    of: subagentBoundaryMarker,
                    options: [],
                    in: searchStart..<haystack.endIndex
                  ) {
                let markerOffset = haystackOffset + UInt64(range.lowerBound)
                if markerOffset >= candidateFloor {
                    switch try subagentBoundaryCandidateLine(
                        url: url,
                        fileSize: fileSize,
                        markerOffset: markerOffset
                    ) {
                    case .committed(let line):
                        if let boundary = parseSubagentActivityBoundary(line) {
                            return SubagentBoundarySearchResult(
                                activityStartedAt: boundary,
                                nextSearchOffset: markerOffset
                            )
                        }
                    case .pending:
                        return SubagentBoundarySearchResult(
                            activityStartedAt: nil,
                            nextSearchOffset: markerOffset
                        )
                    case .skip:
                        break
                    }
                    candidateFloor = markerOffset + 1
                }
                searchStart = range.upperBound
            }

            readOffset += UInt64(chunk.count)
            carry = Data(haystack.suffix(overlapCount))
            candidateFloor = max(
                candidateFloor,
                readOffset > UInt64(overlapCount)
                    ? readOffset - UInt64(overlapCount)
                    : startingAt
            )
        }

        let overlap = UInt64(overlapCount)
        return SubagentBoundarySearchResult(
            activityStartedAt: nil,
            nextSearchOffset: max(
                startingAt,
                fileSize > overlap ? fileSize - overlap : 0
            )
        )
    }

    private static func subagentBoundaryCandidateLine(
        url: URL,
        fileSize: UInt64,
        markerOffset: UInt64
    ) throws -> SubagentBoundaryCandidateLine {
        let maximumLineSize = UInt64(maximumRelevantLineSize)
        let windowStart = markerOffset > maximumLineSize
            ? markerOffset - maximumLineSize
            : 0
        let requestedEnd = markerOffset
            + UInt64(subagentBoundaryMarker.count)
            + maximumLineSize
            + 1
        let windowEnd = min(fileSize, requestedEnd)
        guard windowEnd > windowStart else { return .skip }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: windowStart)
        let data = try handle.read(upToCount: Int(windowEnd - windowStart)) ?? Data()
        let relativeMarkerOffset = Int(markerOffset - windowStart)
        guard relativeMarkerOffset <= data.count else { return .pending }

        let lineStart: Int
        if let newline = data[..<relativeMarkerOffset].lastIndex(of: 0x0A) {
            lineStart = newline + 1
        } else if windowStart == 0 {
            lineStart = 0
        } else {
            return .skip
        }

        let suffixStart = min(data.count, relativeMarkerOffset)
        guard let lineEnd = data[suffixStart...].firstIndex(of: 0x0A) else {
            return windowStart + UInt64(data.count) >= fileSize
                ? .pending
                : .skip
        }
        guard lineEnd >= lineStart,
              lineEnd - lineStart <= maximumRelevantLineSize else {
            return .skip
        }
        return .committed(Data(data[lineStart..<lineEnd]))
    }

    private static func parseSubagentActivityBoundary(_ line: Data) -> Date? {
        guard line.range(of: subagentBoundaryMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              object.string("type") == "inter_agent_communication_metadata",
              let timestamp = object.string("timestamp") else {
            return nil
        }
        return parseTimestamp(timestamp)
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
