import Foundation

typealias JSONObject = [String: Any]

enum CodexDisplayPolicy {
    static let recentThreadLimit = 3
    static let recentThreadFetchLimit = 12

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

    /// Converts the current percentage allowance into an approximate Token
    /// equivalent using the user's observed Token volume in this reset window.
    /// The first partial day is prorated because account usage is day-bucketed.
    static func estimatedRemainingTokens(
        window: RateLimitWindow?,
        dailyUsageBuckets: [DailyUsageBucket],
        todayTokens: Int64?,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int64? {
        guard let window,
              let durationMinutes = window.windowDurationMinutes,
              durationMinutes > 0,
              let resetsAt = window.resetsAt else {
            return nil
        }

        let usedPercent = min(100, max(0, window.usedPercent))
        let remainingPercent = window.remainingPercent
        guard usedPercent > 0, remainingPercent > 0 else { return nil }

        let duration = TimeInterval(durationMinutes) * 60
        let lastResetAt = resetsAt.addingTimeInterval(-duration)
        guard now >= lastResetAt, now < resetsAt else { return nil }

        let resetDay = calendar.startOfDay(for: lastResetAt)
        let today = calendar.startOfDay(for: now)
        var observedTokens = 0.0

        for bucket in dailyUsageBuckets {
            guard let bucketDay = usageDay(
                from: bucket.startDate,
                calendar: calendar
            ),
            bucketDay >= resetDay,
            bucketDay < today else {
                continue
            }

            var fraction = 1.0
            if bucketDay == resetDay,
               let nextDay = calendar.date(byAdding: .day, value: 1, to: bucketDay) {
                let dayDuration = nextDay.timeIntervalSince(bucketDay)
                if dayDuration > 0 {
                    fraction = min(
                        1,
                        max(0, nextDay.timeIntervalSince(lastResetAt) / dayDuration)
                    )
                }
            }
            observedTokens += Double(max(0, bucket.tokens)) * fraction
        }

        if let todayTokens, today >= resetDay {
            var fraction = 1.0
            if today == resetDay {
                let elapsedToday = now.timeIntervalSince(today)
                if elapsedToday > 0 {
                    fraction = min(
                        1,
                        max(0, now.timeIntervalSince(lastResetAt) / elapsedToday)
                    )
                }
            }
            observedTokens += Double(max(0, todayTokens)) * fraction
        }

        guard observedTokens > 0 else { return nil }
        let estimate = observedTokens * remainingPercent / usedPercent
        guard estimate.isFinite, estimate > 0 else { return nil }
        return Int64(min(estimate.rounded(), Double(Int64.max)))
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
