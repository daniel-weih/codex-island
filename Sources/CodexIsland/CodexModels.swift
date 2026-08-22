import Foundation

typealias JSONObject = [String: Any]

enum CodexDisplayPolicy {
    static let recentThreadLimit = 3
    static let recentThreadFetchLimit = 12
    static let usageHabitDayCount = 7
    static let resetCreditExpiryWarningInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Keeps active work visible when the compact dashboard has fewer rows than
    /// the backing thread query. The input is already ordered by recency, so a
    /// stable partition preserves that order within both groups.
    static func visibleRecentThreads(from threads: [ThreadSummary]) -> [ThreadSummary] {
        let running = threads.filter { $0.executionState == .running }
        let remaining = threads.filter { $0.executionState != .running }
        return Array((running + remaining).prefix(recentThreadLimit))
    }

    static func shouldAnimateTokenConsumption(
        previous: Int64?,
        current: Int64?
    ) -> Bool {
        guard let previous, let current else { return false }
        return current > previous
    }

    static func updatedTokenConsumptionHighWater(
        previous: Int64?,
        current: Int64?
    ) -> Int64? {
        guard let current else { return previous }
        guard let previous else { return current }
        return max(previous, current)
    }

    static func hasResetCreditExpiringWithinWeek(
        _ summary: ResetCreditSummary,
        now: Date = Date()
    ) -> Bool {
        guard summary.availableCount > 0 else { return false }
        return summary.expirationDates.contains { expiration in
            isResetCreditExpiringWithinWeek(expiration, now: now)
        }
    }

    static func isResetCreditExpiringWithinWeek(
        _ expiration: Date,
        now: Date = Date()
    ) -> Bool {
        let interval = expiration.timeIntervalSince(now)
        return interval >= 0 && interval <= resetCreditExpiryWarningInterval
    }

    /// Compares actual quota use with a perfectly even burn through the current
    /// reset window. The difference is relative to the expected use at this point
    /// in the cycle, so 30% used versus 20% elapsed is 50% ahead of pace.
    static func quotaConsumptionPace(
        window: RateLimitWindow?,
        now: Date = Date()
    ) -> QuotaConsumptionPaceAssessment? {
        guard let window,
              let durationMinutes = window.windowDurationMinutes,
              durationMinutes > 0,
              let resetsAt = window.resetsAt else {
            return nil
        }

        let duration = TimeInterval(durationMinutes) * 60
        let lastResetAt = resetsAt.addingTimeInterval(-duration)
        guard now >= lastResetAt, now < resetsAt else { return nil }

        let elapsedPercent = now.timeIntervalSince(lastResetAt) / duration * 100
        guard elapsedPercent > 0 else { return nil }
        let usedPercent = min(100, max(0, window.usedPercent))
        let relativeDifferencePercent = (
            usedPercent / elapsedPercent - 1
        ) * 100
        let pace: QuotaConsumptionPace

        if relativeDifferencePercent < -10 {
            pace = .slow
        } else if relativeDifferencePercent <= 10 {
            pace = .normal
        } else if relativeDifferencePercent <= 25 {
            pace = .warning
        } else {
            pace = .critical
        }

        return QuotaConsumptionPaceAssessment(
            pace: pace,
            usedPercent: usedPercent,
            elapsedPercent: elapsedPercent,
            relativeDifferencePercent: relativeDifferencePercent,
            lastResetAt: lastResetAt,
            nextResetAt: resetsAt
        )
    }

    /// Converts the remaining allowance into a personalized Token estimate.
    /// The baseline is the user's average daily volume over the previous 7
    /// complete calendar days, including inactive days, scaled to the quota
    /// window and its remaining percentage.
    static func estimatedRemainingTokens(
        window: RateLimitWindow?,
        dailyUsageBuckets: [DailyUsageBucket],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int64? {
        guard let window,
              let durationMinutes = window.windowDurationMinutes,
              durationMinutes > 0,
              let resetsAt = window.resetsAt else {
            return nil
        }

        let remainingPercent = window.remainingPercent
        guard remainingPercent > 0 else { return nil }

        let duration = TimeInterval(durationMinutes) * 60
        let lastResetAt = resetsAt.addingTimeInterval(-duration)
        guard now >= lastResetAt, now < resetsAt else { return nil }

        let today = calendar.startOfDay(for: now)
        guard let historyStart = calendar.date(
            byAdding: .day,
            value: -usageHabitDayCount,
            to: today
        ) else {
            return nil
        }

        var historicalTokens = 0.0

        for bucket in dailyUsageBuckets {
            guard let bucketDay = usageDay(
                from: bucket.startDate,
                calendar: calendar
            ),
            bucketDay >= historyStart,
            bucketDay < today else {
                continue
            }
            historicalTokens += Double(max(0, bucket.tokens))
        }

        guard historicalTokens > 0 else { return nil }
        let averageDailyTokens = historicalTokens / Double(usageHabitDayCount)
        let windowDays = Double(durationMinutes) / (24 * 60)
        let estimate = averageDailyTokens * windowDays * remainingPercent / 100
        guard estimate.isFinite, estimate > 0 else { return nil }
        return Int64(min(estimate.rounded(), Double(Int64.max)))
    }

    static func displayModelName(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = trimmedValue.split(separator: "/").last.map(String.init) ?? trimmedValue
        var parts = slug.split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
        if parts.first?.lowercased() == "gpt" {
            parts.removeFirst()
        }
        guard !parts.isEmpty else { return slug }
        return parts.map { part -> String in
            let lowercased = part.lowercased()
            if lowercased == "sol" { return "Sol" }
            if lowercased.first == "o", lowercased.dropFirst().first?.isNumber == true {
                return lowercased.uppercased()
            }
            guard let first = lowercased.first else { return part }
            if first.isNumber { return part }
            return first.uppercased() + lowercased.dropFirst()
        }
        .joined(separator: "-")
    }

    /// Returns tasks that have genuinely moved from running to completed.
    /// Missing, interrupted, failed, and already-idle tasks are intentionally
    /// excluded so startup and list reordering cannot trigger notifications.
    static func completedThreadIDs(
        previousStates: [String: ThreadExecutionState],
        currentThreads: [ThreadSummary]
    ) -> [String] {
        currentThreads.compactMap { thread in
            guard previousStates[thread.id] == .running,
                  thread.executionState == .idle else {
                return nil
            }
            return thread.id
        }
    }

    /// Matches the effort names shown by Codex App. Historical `minimal`
    /// records are folded into Light; Extra High is the only abbreviated
    /// label so the row remains compact.
    static func reasoningEffortLabel(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        switch normalized {
        case "minimal", "low", "light": return "LIGHT"
        case "medium": return "MEDIUM"
        case "high": return "HIGH"
        case "xhigh", "extra-high", "extra_high", "extra high": return "XHIGH"
        case "max": return "MAX"
        case "ultra": return "ULTRA"
        default: return normalized.uppercased()
        }
    }

    /// Keeps the expanded-header counters predictable and narrow. Scaled
    /// values omit the decimal once their displayed integer part is three
    /// digits; one- and two-digit values retain one decimal place.
    static func headerTokenCount(_ value: Int64) -> String {
        let clampedValue = max(0, value)
        let units: [(suffix: String, divisor: Double)] = [
            ("K", 1_000),
            ("M", 1_000_000),
            ("B", 1_000_000_000),
            ("T", 1_000_000_000_000),
            ("P", 1_000_000_000_000_000),
            ("E", 1_000_000_000_000_000_000)
        ]
        guard var unitIndex = units.lastIndex(where: {
            Double(clampedValue) >= $0.divisor
        }) else {
            return String(clampedValue)
        }

        var scaledValue = Double(clampedValue) / units[unitIndex].divisor
        var hidesFraction = headerTokenCountHidesFraction(scaledValue)
        let promotionThreshold = hidesFraction ? 999.5 : 999.95
        if scaledValue >= promotionThreshold, unitIndex < units.count - 1 {
            unitIndex += 1
            scaledValue = Double(clampedValue) / units[unitIndex].divisor
            hidesFraction = headerTokenCountHidesFraction(scaledValue)
        }
        return String(
            format: hidesFraction ? "%.0f%@" : "%.1f%@",
            scaledValue,
            units[unitIndex].suffix
        )
    }

    private static func headerTokenCountHidesFraction(
        _ scaledValue: Double
    ) -> Bool {
        scaledValue >= 99.95
    }

    private static func usageDay(
        from value: String,
        calendar: Calendar
    ) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        )).map { calendar.startOfDay(for: $0) }
    }

    /// `account/read` reports both Pro tiers as `pro`. The Codex quota bucket
    /// currently distinguishes the lower tier as `prolite`; keep an explicit
    /// fallback because that subtype is not a documented public contract.
    static func planBadgeLabel(
        accountPlanType: String?,
        rateLimitPlanType: String?
    ) -> String? {
        let accountPlan = normalizedPlanType(accountPlanType)
        let quotaPlan = normalizedPlanType(rateLimitPlanType)

        if accountPlan == "pro"
            || (accountPlan == nil && (quotaPlan == "prolite" || quotaPlan == "pro")) {
            switch quotaPlan {
            case "prolite": return "PRO 5X"
            case "pro": return "PRO 20X"
            default: return "PRO"
            }
        }

        return (accountPlan ?? quotaPlan)?.uppercased()
    }

    private static func normalizedPlanType(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

enum CodexConnectionState: Equatable {
    case connecting
    case connected
    case disconnected(String?)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct AccountSummary: Equatable {
    var authType: String?
    var planType: String?
    var requiresOpenAIAuth: Bool

    static let empty = AccountSummary(authType: nil, planType: nil, requiresOpenAIAuth: false)
}

struct RateLimitWindow: Equatable {
    var usedPercent: Double
    var windowDurationMinutes: Int?
    var resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

enum QuotaConsumptionPace: Equatable, Sendable {
    case slow
    case normal
    case warning
    case critical
}

struct QuotaConsumptionPaceAssessment: Equatable, Sendable {
    var pace: QuotaConsumptionPace
    var usedPercent: Double
    var elapsedPercent: Double
    var relativeDifferencePercent: Double
    var lastResetAt: Date
    var nextResetAt: Date
}

struct RateLimitBucket: Equatable {
    var id: String
    var name: String?
    var planType: String?
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
    var reachedType: String?
}

struct ResetCreditSummary: Equatable {
    var availableCount: Int
    var earliestExpiration: Date?
    var expirationDates: [Date] = []

    static let empty = ResetCreditSummary(
        availableCount: 0,
        earliestExpiration: nil,
        expirationDates: []
    )
}

struct UsageSummary: Equatable {
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSeconds: Int?
    var currentStreakDays: Int?
    var longestStreakDays: Int?
    var dailyUsageBuckets: [DailyUsageBucket] = []

    static let empty = UsageSummary(
        lifetimeTokens: nil,
        peakDailyTokens: nil,
        longestRunningTurnSeconds: nil,
        currentStreakDays: nil,
        longestStreakDays: nil,
        dailyUsageBuckets: []
    )
}

struct DailyUsageBucket: Equatable, Identifiable, Sendable {
    var startDate: String
    var tokens: Int64

    var id: String { startDate }
}

struct HourlyUsageBucket: Equatable, Identifiable, Sendable {
    var hourStart: Date
    var tokens: Int64

    var id: Date { hourStart }
}

struct ProfileIdentitySummary: Equatable {
    var displayName: String?
    var avatarData: Data?

    static let empty = ProfileIdentitySummary(displayName: nil, avatarData: nil)
}

enum ThreadClientSource: String, Equatable, Sendable {
    case tui = "TUI"
    case app = "APP"

    var displayLabel: String { rawValue }
}

struct ThreadSummary: Equatable, Sendable {
    var id: String
    var title: String
    var status: String
    var clientSource: ThreadClientSource?
    var model: String?
    var reasoningEffort: String?
    var serviceTier: String?
    var serviceTierSource: ThreadServiceTierSource?
    var tokenUsage: ThreadTokenUsage?
    var executionState: ThreadExecutionState
    var cwd: String?
    var rolloutPath: String?
    var updatedAt: Date?
}

struct ThreadTokenUsage: Equatable, Sendable {
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var totalTokens: Int64
    /// Tokens currently occupying the model context, as reported by the
    /// latest `last_token_usage` event. This is distinct from the cumulative
    /// task total above.
    var contextTokensUsed: Int64? = nil
    /// The model context capacity reported alongside the latest token count.
    var contextWindowTokens: Int64? = nil
}

enum ThreadExecutionState: Equatable, Sendable {
    case running
    case idle
    case interrupted
    case failed
    case unknown
}

struct ThreadActivitySnapshot: Equatable, Sendable {
    var executionState: ThreadExecutionState
    var tokenUsage: ThreadTokenUsage?
    var updatedAt: Date
}

enum ThreadServiceTierSource: Equatable, Sendable {
    /// Persisted by the task itself, so this describes its recorded runtime state.
    case recorded
    /// Resolved from the task directory's current config; this describes the next resume.
    case effectiveConfig
}

struct ThreadRuntimeSettings: Equatable, Sendable {
    var model: String?
    var reasoningEffort: String?
    var serviceTier: String?
}

struct ModelSummary: Equatable {
    var id: String
    var displayName: String
    var isDefault: Bool
}

struct CodexSnapshot: Equatable {
    var connection: CodexConnectionState
    var account: AccountSummary
    var rateLimit: RateLimitBucket?
    var resetCredits: ResetCreditSummary?
    var usage: UsageSummary
    var profileIdentity: ProfileIdentitySummary = .empty
    var recentThreads: [ThreadSummary]
    /// Token increments persisted by local CLI/App model calls today.
    /// `nil` means the local activity index has not been loaded yet.
    var todayThreadTokens: Int64? = nil
    /// Local model-call Token increments for the last 48 clock hours,
    /// including the current partial hour.
    var hourlyThreadTokens: [HourlyUsageBucket] = []
    /// Compact-island activity state. This intentionally differs from the
    /// expanded header's app-server connection indicator.
    var hasRunningSession: Bool = false
    var activeModel: ModelSummary?
    var lastUpdated: Date?
    var warning: String?

    static let initial = CodexSnapshot(
        connection: .connecting,
        account: .empty,
        rateLimit: nil,
        resetCredits: nil,
        usage: .empty,
        profileIdentity: .empty,
        recentThreads: [],
        todayThreadTokens: nil,
        hasRunningSession: false,
        activeModel: nil,
        lastUpdated: nil,
        warning: nil
    )
}
