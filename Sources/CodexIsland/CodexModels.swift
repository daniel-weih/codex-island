import Foundation

typealias JSONObject = [String: Any]

enum CodexDisplayPolicy {
    static let recentThreadLimit = 5

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
    /// Token increments persisted by local root CLI/App conversations today.
    /// `nil` means the local activity index has not been loaded yet.
    var todayThreadTokens: Int64? = nil
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
