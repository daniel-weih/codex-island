import Foundation

struct LocalTokenUsageSnapshot: Equatable, Sendable {
    /// Actual model tokens, without Fast quota weighting.
    var todayTokens: Int64
    var hourlyBuckets: [HourlyUsageBucket]
    var dailyBuckets: [DailyUsageBucket]
    /// Standard-mode-equivalent tokens for ChatGPT-credit usage, with OpenAI
    /// Fast calls weighted by the model that was active for each call.
    var billedTodayTokens: Int64
    var billedHourlyBuckets: [HourlyUsageBucket]
    var billedDailyBuckets: [DailyUsageBucket]
    /// Rollouts whose metadata was already observed as recently modified while
    /// reducing usage. Reusing this list avoids a second stat pass when
    /// resolving live execution state.
    var recentlyModifiedRolloutPaths: [String]
}

struct DailyTokenUsageCacheDiagnostics: Equatable, Sendable {
    var baselineScanCount: Int
}

/// Computes actual and Standard-mode-equivalent Token increments for local
/// CLI/App calls.
/// Each new `last_token_usage` is counted once at message granularity; only the
/// equivalent series weights eligible Fast calls by their model-specific quota
/// cost.
/// Fork and subagent boundaries exclude timestamp-rewritten parent history.
enum CodexDailyTokenUsageReader {
    static let recentHourCount = 48
    static let recentDayCount = 30
    private static let cache = DailyTokenUsageCache()

    static func readToday(
        from rolloutPaths: [String],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        usesChatGPTCredits: Bool = true
    ) throws -> Int64 {
        try readRecentHours(
            from: rolloutPaths,
            now: now,
            calendar: calendar,
            usesChatGPTCredits: usesChatGPTCredits
        ).todayTokens
    }

    static func readRecentHours(
        from rolloutPaths: [String],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        usesChatGPTCredits: Bool = true
    ) throws -> LocalTokenUsageSnapshot {
        try cache.readRecentHours(
            from: rolloutPaths,
            now: now,
            calendar: calendar,
            hourCount: recentHourCount,
            usesChatGPTCredits: usesChatGPTCredits
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

    static func cacheDiagnosticsForTesting() -> DailyTokenUsageCacheDiagnostics {
        cache.diagnostics()
    }
}

private struct DailyTokenEvent {
    var timestamp: Date
    var totalTokens: Int64
    var lastTokens: Int64?
}

private struct DailyRuntimeSettingsEvent {
    var timestamp: Date
    var model: String?
    var modelProvider: String?
    var serviceTier: String?
}

private enum DailyUsageRecord {
    case runtimeSettings(DailyRuntimeSettingsEvent)
    case token(DailyTokenEvent)
}

private enum ActivityBoundaryKind {
    case subagent
    case fork(sessionID: String)
}

private struct DailyTokenFileEntry {
    var fileIdentity: String
    var fileSize: UInt64
    var modifiedAt: Date
    var previousTotal: Int64?
    var model: String?
    var sessionModelProvider: String?
    var modelProvider: String?
    var serviceTier: String?
    var todayTotal: Int64
    var hourlyTotals: [Date: Int64]
    var dailyTotals: [Date: Int64]
    var billedTodayTotal: Int64
    var billedHourlyTotals: [Date: Int64]
    var billedDailyTotals: [Date: Int64]
    var trailingLineStartOffset: UInt64?
    var countingStart: Date
    var isExcluded: Bool
    var isWaitingForActivityBoundary: Bool
    var activityBoundaryKind: ActivityBoundaryKind?
    var activityBoundarySearchOffset: UInt64?
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

private struct DailyTokenCalendarSignature: Equatable {
    var identifier: String
    var timeZoneIdentifier: String

    init(calendar: Calendar) {
        identifier = String(describing: calendar.identifier)
        timeZoneIdentifier = calendar.timeZone.identifier
    }
}

private final class DailyTokenUsageCache: @unchecked Sendable {
    private static let chunkSize = 64 * 1024
    private static let boundarySearchChunkSize = 1024 * 1024
    private static let maximumRelevantLineSize = 64 * 1024
    private static let maximumSessionMetaSize = 512 * 1024
    private static let tokenCountMarker = Data("token_count".utf8)
    private static let threadSettingsMarker = Data("thread_settings_applied".utf8)
    private static let turnContextMarker = Data("turn_context".utf8)
    private static let subagentBoundaryMarker = Data(
        "inter_agent_communication_metadata".utf8
    )
    private static let freshRunningLookback: TimeInterval = 30 * 60

    private let lock = NSLock()
    private var dayStart: Date?
    private var nextDayStart: Date?
    private var hourlyRangeStart: Date?
    private var hourlyRangeEnd: Date?
    private var dailyRangeStart: Date?
    private var usesChatGPTCredits: Bool?
    private var calendarSignature: DailyTokenCalendarSignature?
    private var lastObservedNow: Date?
    private var cachedRolloutPaths: Set<String> = []
    private var entries: [String: DailyTokenFileEntry] = [:]
    private var baselineScanCount = 0

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
        dailyRangeStart = nil
        usesChatGPTCredits = nil
        calendarSignature = nil
        lastObservedNow = nil
        cachedRolloutPaths.removeAll()
        entries.removeAll()
        baselineScanCount = 0
    }

    func diagnostics() -> DailyTokenUsageCacheDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return DailyTokenUsageCacheDiagnostics(
            baselineScanCount: baselineScanCount
        )
    }

    func readRecentHours(
        from rolloutPaths: [String],
        now: Date,
        calendar: Calendar,
        hourCount: Int,
        usesChatGPTCredits: Bool
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
        guard let resolvedDailyRangeStart = calendar.date(
            byAdding: .day,
            value: -(CodexDailyTokenUsageReader.recentDayCount - 1),
            to: resolvedDayStart
        ), let resolvedNextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: resolvedDayStart
        ) else {
            throw DailyTokenUsageError.noReadableRollouts
        }

        lock.lock()
        defer { lock.unlock() }

        let resolvedCalendarSignature = DailyTokenCalendarSignature(
            calendar: calendar
        )
        let hasCompleteWindow = dayStart != nil
            && nextDayStart != nil
            && hourlyRangeStart != nil
            && hourlyRangeEnd != nil
            && dailyRangeStart != nil
            && self.usesChatGPTCredits != nil
            && calendarSignature != nil
        let mustRebuild = !hasCompleteWindow
            || self.usesChatGPTCredits != usesChatGPTCredits
            || calendarSignature != resolvedCalendarSignature
            || now < (lastObservedNow ?? now)
            || resolvedDayStart < (dayStart ?? resolvedDayStart)
            || resolvedNextDayStart < (nextDayStart ?? resolvedNextDayStart)
            || resolvedHourlyRangeStart
                < (hourlyRangeStart ?? resolvedHourlyRangeStart)
            || resolvedHourlyRangeEnd
                < (hourlyRangeEnd ?? resolvedHourlyRangeEnd)
            || resolvedDailyRangeStart
                < (dailyRangeStart ?? resolvedDailyRangeStart)
        let windowChanged = dayStart != resolvedDayStart
            || nextDayStart != resolvedNextDayStart
            || hourlyRangeStart != resolvedHourlyRangeStart
            || hourlyRangeEnd != resolvedHourlyRangeEnd
            || dailyRangeStart != resolvedDailyRangeStart

        if mustRebuild {
            entries.removeAll()
        } else if windowChanged {
            rollCachedEntries(
                dayStart: resolvedDayStart,
                hourlyRangeStart: resolvedHourlyRangeStart,
                dailyRangeStart: resolvedDailyRangeStart
            )
        }
        dayStart = resolvedDayStart
        nextDayStart = resolvedNextDayStart
        hourlyRangeStart = resolvedHourlyRangeStart
        hourlyRangeEnd = resolvedHourlyRangeEnd
        dailyRangeStart = resolvedDailyRangeStart
        self.usesChatGPTCredits = usesChatGPTCredits
        calendarSignature = resolvedCalendarSignature
        lastObservedNow = now

        let paths = Array(Set(
            rolloutPaths
                .filter { !$0.isEmpty }
                .map {
                    URL(fileURLWithPath: $0).standardizedFileURL.path
                }
        )).sorted()
        let activePathSet = Set(paths)
        if activePathSet != cachedRolloutPaths {
            entries = entries.filter { activePathSet.contains($0.key) }
            cachedRolloutPaths = activePathSet
        }
        guard !paths.isEmpty else {
            let emptyHourlyBuckets = Self.emptyHourlyBuckets(
                startingAt: resolvedHourlyRangeStart,
                count: hourCount,
                calendar: calendar
            )
            let emptyDailyBuckets = Self.emptyDailyBuckets(
                startingAt: resolvedDailyRangeStart,
                count: CodexDailyTokenUsageReader.recentDayCount,
                calendar: calendar
            )
            return LocalTokenUsageSnapshot(
                todayTokens: 0,
                hourlyBuckets: emptyHourlyBuckets,
                dailyBuckets: emptyDailyBuckets,
                billedTodayTokens: 0,
                billedHourlyBuckets: emptyHourlyBuckets,
                billedDailyBuckets: emptyDailyBuckets,
                recentlyModifiedRolloutPaths: []
            )
        }

        var readableCount = 0
        var total: Int64 = 0
        var hourlyTotals: [Date: Int64] = [:]
        var dailyTotals: [Date: Int64] = [:]
        var billedTotal: Int64 = 0
        var billedHourlyTotals: [Date: Int64] = [:]
        var billedDailyTotals: [Date: Int64] = [:]
        var recentlyModifiedRolloutPaths: [String] = []
        let recentModificationCutoff = now.addingTimeInterval(
            -Self.freshRunningLookback
        )
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            do {
                let entry = try refreshedEntry(
                    for: url,
                    dayStart: resolvedDayStart,
                    nextDayStart: resolvedNextDayStart,
                    hourlyRangeStart: resolvedHourlyRangeStart,
                    dailyRangeStart: resolvedDailyRangeStart,
                    usesChatGPTCredits: usesChatGPTCredits,
                    calendar: calendar
                )
                entries[url.path] = entry
                readableCount += 1
                if entry.modifiedAt >= recentModificationCutoff {
                    recentlyModifiedRolloutPaths.append(url.path)
                }
                total = Self.clampedAdd(total, entry.todayTotal)
                for (hourStart, tokens) in entry.hourlyTotals {
                    hourlyTotals[hourStart] = Self.clampedAdd(
                        hourlyTotals[hourStart, default: 0],
                        tokens
                    )
                }
                billedTotal = Self.clampedAdd(
                    billedTotal,
                    entry.billedTodayTotal
                )
                for (hourStart, tokens) in entry.billedHourlyTotals {
                    billedHourlyTotals[hourStart] = Self.clampedAdd(
                        billedHourlyTotals[hourStart, default: 0],
                        tokens
                    )
                }
                for (dateStart, tokens) in entry.billedDailyTotals {
                    billedDailyTotals[dateStart] = Self.clampedAdd(
                        billedDailyTotals[dateStart, default: 0],
                        tokens
                    )
                }
                for (dateStart, tokens) in entry.dailyTotals {
                    dailyTotals[dateStart] = Self.clampedAdd(
                        dailyTotals[dateStart, default: 0],
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
        let dailyBuckets = Self.emptyDailyBuckets(
            startingAt: resolvedDailyRangeStart,
            count: CodexDailyTokenUsageReader.recentDayCount,
            calendar: calendar
        ).map { bucket in
            DailyUsageBucket(
                startDate: bucket.startDate,
                tokens: Self.dayDate(bucket.startDate, calendar: calendar)
                    .flatMap { dailyTotals[$0] } ?? 0
            )
        }
        let billedBuckets = Self.emptyHourlyBuckets(
            startingAt: resolvedHourlyRangeStart,
            count: hourCount,
            calendar: calendar
        ).map { bucket in
            HourlyUsageBucket(
                hourStart: bucket.hourStart,
                tokens: billedHourlyTotals[bucket.hourStart] ?? 0
            )
        }
        let billedDailyBuckets = Self.emptyDailyBuckets(
            startingAt: resolvedDailyRangeStart,
            count: CodexDailyTokenUsageReader.recentDayCount,
            calendar: calendar
        ).map { bucket in
            DailyUsageBucket(
                startDate: bucket.startDate,
                tokens: Self.dayDate(bucket.startDate, calendar: calendar)
                    .flatMap { billedDailyTotals[$0] } ?? 0
            )
        }
        return LocalTokenUsageSnapshot(
            todayTokens: total,
            hourlyBuckets: buckets,
            dailyBuckets: dailyBuckets,
            billedTodayTokens: billedTotal,
            billedHourlyBuckets: billedBuckets,
            billedDailyBuckets: billedDailyBuckets,
            recentlyModifiedRolloutPaths: recentlyModifiedRolloutPaths
        )
    }

    /// Time windows only move forward during normal operation. Preserve the
    /// expensive EOF reducer state and discard buckets that have simply aged
    /// out instead of reparsing every rollout at each hour or midnight.
    private func rollCachedEntries(
        dayStart: Date,
        hourlyRangeStart: Date,
        dailyRangeStart: Date
    ) {
        for path in Array(entries.keys) {
            guard var entry = entries[path] else { continue }
            entry.hourlyTotals = entry.hourlyTotals.filter {
                $0.key >= hourlyRangeStart
            }
            entry.billedHourlyTotals = entry.billedHourlyTotals.filter {
                $0.key >= hourlyRangeStart
            }
            entry.dailyTotals = entry.dailyTotals.filter {
                $0.key >= dailyRangeStart
            }
            entry.billedDailyTotals = entry.billedDailyTotals.filter {
                $0.key >= dailyRangeStart
            }
            entry.todayTotal = entry.dailyTotals[dayStart] ?? 0
            entry.billedTodayTotal = entry.billedDailyTotals[dayStart] ?? 0
            entry.countingStart = max(entry.countingStart, dailyRangeStart)
            entries[path] = entry
        }
    }

    static func discoverLocalUsageRollouts(
        now: Date,
        calendar: Calendar
    ) throws -> [String] {
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let historyStart = calendar.date(
            byAdding: .day,
            value: -(CodexDailyTokenUsageReader.recentDayCount - 1),
            to: calendar.startOfDay(for: now)
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
        dailyRangeStart: Date,
        usesChatGPTCredits: Bool,
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
           cached.isWaitingForActivityBoundary,
           let boundaryKind = cached.activityBoundaryKind {
            let search = try Self.firstActivityBoundary(
                url: url,
                fileSize: fileSize,
                kind: boundaryKind,
                startingAt: cached.activityBoundarySearchOffset ?? 0
            )
            cached.fileSize = fileSize
            cached.modifiedAt = modifiedAt
            cached.trailingLineStartOffset = try Self.findTrailingLineStartOffset(
                url: url,
                fileSize: fileSize
            )
            cached.activityBoundarySearchOffset = search.activityStartedAt == nil
                ? search.nextSearchOffset
                : nil

            guard let activityStartedAt = search.activityStartedAt else {
                return cached
            }

            cached.countingStart = max(dailyRangeStart, activityStartedAt)
            cached.isExcluded = false
            cached.isWaitingForActivityBoundary = false
            cached.previousTotal = nil
            cached.model = nil
            cached.modelProvider = cached.sessionModelProvider
            cached.serviceTier = nil
            cached.todayTotal = 0
            cached.hourlyTotals = [:]
            cached.dailyTotals = [:]
            cached.billedTodayTotal = 0
            cached.billedHourlyTotals = [:]
            cached.billedDailyTotals = [:]
            let resumedCountingStart = cached.countingStart
            guard modifiedAt >= resumedCountingStart else { return cached }

            baselineScanCount += 1
            let records = try Self.scanBackwardToDailyBaseline(
                url: url,
                fileSize: fileSize,
                dayStart: resumedCountingStart
            )
            for record in records.reversed() {
                Self.consume(
                    record,
                    previousTotal: &cached.previousTotal,
                    model: &cached.model,
                    modelProvider: &cached.modelProvider,
                    serviceTier: &cached.serviceTier,
                    todayTotal: &cached.todayTotal,
                    hourlyTotals: &cached.hourlyTotals,
                    dailyTotals: &cached.dailyTotals,
                    billedTodayTotal: &cached.billedTodayTotal,
                    billedHourlyTotals: &cached.billedHourlyTotals,
                    billedDailyTotals: &cached.billedDailyTotals,
                    countingStart: resumedCountingStart,
                    dayStart: dayStart,
                    nextDayStart: nextDayStart,
                    hourlyRangeStart: hourlyRangeStart,
                    dailyRangeStart: dailyRangeStart,
                    usesChatGPTCredits: usesChatGPTCredits,
                    calendar: calendar
                )
            }
            return cached
        }

        if var cached = entries[url.path],
           cached.fileIdentity == fileIdentity,
           fileSize > cached.fileSize,
           !cached.isWaitingForActivityBoundary {
            let originalSize = cached.fileSize
            let scanStart = min(
                cached.trailingLineStartOffset ?? originalSize,
                originalSize
            )
            cached.fileSize = fileSize
            cached.modifiedAt = modifiedAt
            if !cached.isExcluded {
                var previousTotal = cached.previousTotal
                var model = cached.model
                var modelProvider = cached.modelProvider
                var serviceTier = cached.serviceTier
                var todayTotal = cached.todayTotal
                var hourlyTotals = cached.hourlyTotals
                var dailyTotals = cached.dailyTotals
                var billedTodayTotal = cached.billedTodayTotal
                var billedHourlyTotals = cached.billedHourlyTotals
                var billedDailyTotals = cached.billedDailyTotals
                try Self.scanForward(
                    url: url,
                    from: scanStart,
                    to: fileSize
                ) { record in
                    Self.consume(
                        record,
                        previousTotal: &previousTotal,
                        model: &model,
                        modelProvider: &modelProvider,
                        serviceTier: &serviceTier,
                        todayTotal: &todayTotal,
                        hourlyTotals: &hourlyTotals,
                        dailyTotals: &dailyTotals,
                        billedTodayTotal: &billedTodayTotal,
                        billedHourlyTotals: &billedHourlyTotals,
                        billedDailyTotals: &billedDailyTotals,
                        countingStart: cached.countingStart,
                        dayStart: dayStart,
                        nextDayStart: nextDayStart,
                        hourlyRangeStart: hourlyRangeStart,
                        dailyRangeStart: dailyRangeStart,
                        usesChatGPTCredits: usesChatGPTCredits,
                        calendar: calendar
                    )
                }
                cached.previousTotal = previousTotal
                cached.model = model
                cached.modelProvider = modelProvider
                cached.serviceTier = serviceTier
                cached.todayTotal = todayTotal
                cached.hourlyTotals = hourlyTotals
                cached.dailyTotals = dailyTotals
                cached.billedTodayTotal = billedTodayTotal
                cached.billedHourlyTotals = billedHourlyTotals
                cached.billedDailyTotals = billedDailyTotals
                cached.trailingLineStartOffset = try Self.findTrailingLineStartOffset(
                    url: url,
                    fileSize: fileSize
                )
            }
            return cached
        }

        let session = try Self.localUsageSession(url: url, fileSize: fileSize)
        let countingStart = max(
            dailyRangeStart,
            session.activityStartedAt ?? session.startedAt ?? dailyRangeStart
        )
        var entry = DailyTokenFileEntry(
            fileIdentity: fileIdentity,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            previousTotal: nil,
            model: nil,
            sessionModelProvider: session.modelProvider,
            modelProvider: session.modelProvider,
            serviceTier: nil,
            todayTotal: 0,
            hourlyTotals: [:],
            dailyTotals: [:],
            billedTodayTotal: 0,
            billedHourlyTotals: [:],
            billedDailyTotals: [:],
            trailingLineStartOffset: try Self.findTrailingLineStartOffset(
                url: url,
                fileSize: fileSize
            ),
            countingStart: countingStart,
            isExcluded: !session.isIncluded || session.isWaitingForActivityBoundary,
            isWaitingForActivityBoundary: session.isWaitingForActivityBoundary,
            activityBoundaryKind: session.activityBoundaryKind,
            activityBoundarySearchOffset: session.activityBoundarySearchOffset
        )
        guard !entry.isExcluded, modifiedAt >= countingStart else { return entry }

        baselineScanCount += 1
        let records = try Self.scanBackwardToDailyBaseline(
            url: url,
            fileSize: fileSize,
            dayStart: countingStart
        )
        for record in records.reversed() {
            Self.consume(
                record,
                previousTotal: &entry.previousTotal,
                model: &entry.model,
                modelProvider: &entry.modelProvider,
                serviceTier: &entry.serviceTier,
                todayTotal: &entry.todayTotal,
                hourlyTotals: &entry.hourlyTotals,
                dailyTotals: &entry.dailyTotals,
                billedTodayTotal: &entry.billedTodayTotal,
                billedHourlyTotals: &entry.billedHourlyTotals,
                billedDailyTotals: &entry.billedDailyTotals,
                countingStart: countingStart,
                dayStart: dayStart,
                nextDayStart: nextDayStart,
                hourlyRangeStart: hourlyRangeStart,
                dailyRangeStart: dailyRangeStart,
                usesChatGPTCredits: usesChatGPTCredits,
                calendar: calendar
            )
        }
        return entry
    }

    private static func consume(
        _ record: DailyUsageRecord,
        previousTotal: inout Int64?,
        model: inout String?,
        modelProvider: inout String?,
        serviceTier: inout String?,
        todayTotal: inout Int64,
        hourlyTotals: inout [Date: Int64],
        dailyTotals: inout [Date: Int64],
        billedTodayTotal: inout Int64,
        billedHourlyTotals: inout [Date: Int64],
        billedDailyTotals: inout [Date: Int64],
        countingStart: Date,
        dayStart: Date,
        nextDayStart: Date,
        hourlyRangeStart: Date,
        dailyRangeStart: Date,
        usesChatGPTCredits: Bool,
        calendar: Calendar
    ) {
        guard case .token(let event) = record else {
            if case .runtimeSettings(let settings) = record {
                if let recordedModel = settings.model {
                    model = recordedModel
                }
                if let recordedModelProvider = settings.modelProvider {
                    modelProvider = recordedModelProvider
                }
                if let recordedServiceTier = settings.serviceTier {
                    serviceTier = recordedServiceTier
                }
            }
            return
        }

        let rawDelta: Int64
        if let previousTotal {
            if event.totalTokens > previousTotal {
                // A forked or parent task can absorb a child's cumulative
                // counter between notifications. `last_token_usage` is the
                // message-level call that belongs to this rollout; using the
                // whole cumulative jump would count the child twice.
                rawDelta = max(
                    0,
                    event.lastTokens ?? (event.totalTokens - previousTotal)
                )
            } else if event.totalTokens < previousTotal {
                rawDelta = max(0, event.lastTokens ?? event.totalTokens)
            } else {
                rawDelta = 0
            }
        } else {
            rawDelta = max(0, event.lastTokens ?? event.totalTokens)
        }
        previousTotal = event.totalTokens
        let billedDelta = budgetWeightedTokens(
            rawDelta,
            model: model,
            modelProvider: modelProvider,
            serviceTier: serviceTier,
            usesChatGPTCredits: usesChatGPTCredits
        )

        guard event.timestamp >= countingStart else { return }
        if event.timestamp >= dayStart, event.timestamp < nextDayStart {
            todayTotal = clampedAdd(todayTotal, rawDelta)
            billedTodayTotal = clampedAdd(billedTodayTotal, billedDelta)
        }
        // Keep already-parsed future buckets. A file can receive the first
        // record of the next hour after `now` was captured but before this
        // scan starts. Advancing the EOF reducer while dropping that record
        // would make it impossible to recover without a cold rescan.
        if event.timestamp >= hourlyRangeStart,
           let hourStart = calendar.dateInterval(
            of: .hour,
            for: event.timestamp
           )?.start {
            hourlyTotals[hourStart] = clampedAdd(
                hourlyTotals[hourStart, default: 0],
                rawDelta
            )
            billedHourlyTotals[hourStart] = clampedAdd(
                billedHourlyTotals[hourStart, default: 0],
                billedDelta
            )
        }
        if event.timestamp >= dailyRangeStart {
            let dateStart = calendar.startOfDay(for: event.timestamp)
            dailyTotals[dateStart] = clampedAdd(
                dailyTotals[dateStart, default: 0],
                rawDelta
            )
            billedDailyTotals[dateStart] = clampedAdd(
                billedDailyTotals[dateStart, default: 0],
                billedDelta
            )
        }
    }

    private static func budgetWeightedTokens(
        _ tokens: Int64,
        model: String?,
        modelProvider: String?,
        serviceTier: String?,
        usesChatGPTCredits: Bool
    ) -> Int64 {
        guard tokens > 0 else { return 0 }
        guard usesChatGPTCredits else { return tokens }
        guard normalizedModelProvider(modelProvider) == "openai" else {
            return tokens
        }
        guard CodexDisplayPolicy.isFastServiceTier(serviceTier) else {
            return tokens
        }
        guard let multiplier = CodexFastModeUsagePolicy.multiplier(for: model) else {
            return tokens
        }
        let weighted = Double(tokens) * multiplier
        guard weighted.isFinite else { return Int64.max }
        return Int64(min(weighted.rounded(), Double(Int64.max)))
    }

    private static func normalizedModelProvider(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty else {
            return nil
        }
        return normalized
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

    private static func emptyDailyBuckets(
        startingAt start: Date,
        count: Int,
        calendar: Calendar
    ) -> [DailyUsageBucket] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map {
                DailyUsageBucket(startDate: formatter.string(from: $0), tokens: 0)
            }
        }
    }

    private static func dayDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ).map { calendar.startOfDay(for: $0) }
    }

    /// Returns newest-to-oldest events, including the first absolute counter
    /// before the requested range as the cumulative baseline.
    private static func scanBackwardToDailyBaseline(
        url: URL,
        fileSize: UInt64,
        dayStart: Date
    ) throws -> [DailyUsageRecord] {
        var records: [DailyUsageRecord] = []
        var crossedTokenBaseline = false
        var capturedModelBaseline = false
        var capturedModelProviderBaseline = false
        var capturedServiceTierBaseline = false
        try scanLinesBackward(url: url, fileSize: fileSize) { line in
            guard let record = parseUsageRecord(line) else { return true }
            records.append(record)
            switch record {
            case .token(let event):
                if event.timestamp < dayStart {
                    crossedTokenBaseline = true
                }
            case .runtimeSettings(let settings):
                if settings.timestamp <= dayStart {
                    capturedModelBaseline = capturedModelBaseline
                        || settings.model != nil
                    capturedModelProviderBaseline = capturedModelProviderBaseline
                        || settings.modelProvider != nil
                    capturedServiceTierBaseline = capturedServiceTierBaseline
                        || settings.serviceTier != nil
                }
            }
            // Keep the last model, provider, and service tier from before the
            // range so the first counted message receives the active settings.
            return !(crossedTokenBaseline
                && capturedModelBaseline
                && capturedModelProviderBaseline
                && capturedServiceTierBaseline)
        }
        return records
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
        consumeRecord: (DailyUsageRecord) -> Void
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
                       let record = parseUsageRecord(line) {
                        consumeRecord(record)
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

    private static func parseUsageRecord(_ line: Data) -> DailyUsageRecord? {
        if let event = parseTokenEvent(line) {
            return .token(event)
        }
        guard line.range(of: threadSettingsMarker) != nil
                || line.range(of: turnContextMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              let timestampString = object.string("timestamp"),
              let timestamp = parseTimestamp(timestampString),
              let payload = object.dictionary("payload") else {
            return nil
        }

        let model: String?
        let modelProvider: String?
        let serviceTier: String?
        if object.string("type") == "event_msg",
           payload.string("type") == "thread_settings_applied" {
            let settings = payload.dictionary("thread_settings")
            model = settings?.string("model")
            modelProvider = settings?.string("model_provider_id")
            serviceTier = settings?.string("service_tier")
        } else if object.string("type") == "turn_context" {
            model = payload.string("model")
            modelProvider = nil
            serviceTier = payload.string("service_tier")
        } else {
            model = nil
            modelProvider = nil
            serviceTier = nil
        }
        guard model != nil || modelProvider != nil || serviceTier != nil else {
            return nil
        }
        return .runtimeSettings(
            DailyRuntimeSettingsEvent(
                timestamp: timestamp,
                model: model,
                modelProvider: modelProvider,
                serviceTier: serviceTier
            )
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
        var modelProvider: String?
        var isIncluded: Bool
        var isWaitingForActivityBoundary: Bool
        var activityBoundaryKind: ActivityBoundaryKind?
        var activityBoundarySearchOffset: UInt64?
    }

    private struct ActivityBoundarySearchResult {
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
                modelProvider: nil,
                isIncluded: false,
                isWaitingForActivityBoundary: false,
                activityBoundaryKind: nil,
                activityBoundarySearchOffset: nil
            )
        }
        guard let object = sessionMetaObject(line),
              let payload = object.dictionary("payload") else {
            return LocalUsageSession(
                startedAt: nil,
                activityStartedAt: nil,
                modelProvider: nil,
                isIncluded: containsLocalUsageSourceMarker(line),
                isWaitingForActivityBoundary: false,
                activityBoundaryKind: nil,
                activityBoundarySearchOffset: nil
            )
        }
        let isSubagent = isSubagentUsageSession(payload)
        let boundaryKind: ActivityBoundaryKind?
        if isSubagent {
            boundaryKind = .subagent
        } else if payload.string("forked_from_id") != nil,
                  let sessionID = payload.string("id")
                    ?? payload.string("session_id") {
            boundaryKind = .fork(sessionID: sessionID)
        } else {
            boundaryKind = nil
        }
        let boundarySearch = try boundaryKind.map {
            try firstActivityBoundary(
                url: url,
                fileSize: fileSize,
                kind: $0,
                startingAt: 0
            )
        }
        let activityStartedAt = boundarySearch?.activityStartedAt
        return LocalUsageSession(
            startedAt: object.string("timestamp").flatMap(parseTimestamp),
            activityStartedAt: activityStartedAt,
            modelProvider: payload.string("model_provider"),
            isIncluded: isLocalUsageSession(payload),
            isWaitingForActivityBoundary: boundaryKind != nil
                && activityStartedAt == nil,
            activityBoundaryKind: boundaryKind,
            activityBoundarySearchOffset: activityStartedAt == nil
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
    private static func firstActivityBoundary(
        url: URL,
        fileSize: UInt64,
        kind: ActivityBoundaryKind,
        startingAt: UInt64
    ) throws -> ActivityBoundarySearchResult {
        switch kind {
        case .subagent:
            return try firstSubagentActivityBoundary(
                url: url,
                fileSize: fileSize,
                startingAt: startingAt
            )
        case .fork(let sessionID):
            return try firstForkActivityBoundary(
                url: url,
                fileSize: fileSize,
                sessionID: sessionID
            )
        }
    }

    private static func firstSubagentActivityBoundary(
        url: URL,
        fileSize: UInt64,
        startingAt requestedStart: UInt64
    ) throws -> ActivityBoundarySearchResult {
        guard fileSize > 0 else {
            return ActivityBoundarySearchResult(
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
                            return ActivityBoundarySearchResult(
                                activityStartedAt: boundary,
                                nextSearchOffset: markerOffset
                            )
                        }
                    case .pending:
                        return ActivityBoundarySearchResult(
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
        return ActivityBoundarySearchResult(
            activityStartedAt: nil,
            nextSearchOffset: max(
                startingAt,
                fileSize > overlap ? fileSize - overlap : 0
            )
        )
    }

    /// A user-created fork also starts with a timestamp-rewritten copy of its
    /// parent. Codex writes the fork's own `session_meta` again immediately
    /// before the first real turn; that second matching row is the reliable
    /// boundary between replayed history and new model calls.
    private static func firstForkActivityBoundary(
        url: URL,
        fileSize: UInt64,
        sessionID: String
    ) throws -> ActivityBoundarySearchResult {
        guard fileSize > 0 else {
            return ActivityBoundarySearchResult(
                activityStartedAt: nil,
                nextSearchOffset: 0
            )
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        var line = Data()
        var skippingOversizedLine = false
        var hasSeenInitialSessionMeta = false
        while offset < fileSize {
            let readCount = min(chunkSize, Int(fileSize - offset))
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }
            offset += UInt64(chunk.count)

            for byte in chunk {
                if byte == 0x0A {
                    if !skippingOversizedLine,
                       let object = sessionMetaObject(line),
                       let payload = object.dictionary("payload"),
                       (payload.string("id")
                            ?? payload.string("session_id")) == sessionID {
                        if hasSeenInitialSessionMeta,
                           let timestamp = object.string("timestamp")
                            .flatMap(parseTimestamp) {
                            return ActivityBoundarySearchResult(
                                activityStartedAt: timestamp,
                                nextSearchOffset: offset
                            )
                        }
                        hasSeenInitialSessionMeta = true
                    }
                    line.removeAll(keepingCapacity: true)
                    skippingOversizedLine = false
                } else if !skippingOversizedLine {
                    if line.count < maximumSessionMetaSize {
                        line.append(byte)
                    } else {
                        line.removeAll(keepingCapacity: false)
                        skippingOversizedLine = true
                    }
                }
            }
        }

        // Rescan from the beginning after an append so the initial matching
        // metadata row is still available to distinguish from the boundary.
        return ActivityBoundarySearchResult(
            activityStartedAt: nil,
            nextSearchOffset: 0
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
