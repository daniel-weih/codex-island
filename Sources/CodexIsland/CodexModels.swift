import Foundation

typealias JSONObject = [String: Any]

enum CodexFastModeUsagePolicy {
    private static let modelFamilyMultipliers: [(family: String, multiplier: Double)] = [
        ("gpt-6-astra", 2.5),
        ("gpt-5.6", 2.5),
        ("gpt-5.5", 2.5),
        ("gpt-5.4", 2.0)
    ]

    /// Returns the official ChatGPT Fast-to-Standard credit multiplier.
    /// Models outside the documented Fast support list are left unweighted
    /// instead of guessing a multiplier.
    static func multiplier(for model: String?) -> Double? {
        guard let model else { return nil }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let normalized = slug.lowercased()

        for entry in modelFamilyMultipliers where
            normalized == entry.family || normalized.hasPrefix("\(entry.family)-") {
            return entry.multiplier
        }
        return nil
    }
}

enum CodexDisplayPolicy {
    static let recentThreadLimit = 3
    static let recentThreadFetchLimit = 12
    static let usageHabitDayCount = 7
    static let resetCreditExpiryWarningInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Keeps active work visible when the compact dashboard has fewer rows than
    /// the backing thread query. The input is already ordered by recency, so a
    /// stable partition preserves that order within both groups.
    static func visibleRecentThreads(from threads: [ThreadSummary]) -> [ThreadSummary] {
        let active = threads.filter {
            $0.executionState == .running || $0.executionState == .waitingForInput
        }
        let remaining = threads.filter {
            $0.executionState != .running && $0.executionState != .waitingForInput
        }
        return Array((active + remaining).prefix(recentThreadLimit))
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

    /// Produces a human-facing capacity warning rather than treating every
    /// above-average burst as an emergency. Remaining quota is the primary
    /// gate; projected runway only raises an alert once capacity is genuinely
    /// low enough that the user may need to change behavior.
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
        let remainingPercent = 100 - usedPercent
        let relativeDifferencePercent = (
            usedPercent / elapsedPercent - 1
        ) * 100
        let projectedUsedPercentAtReset = usedPercent / elapsedPercent * 100
        let projectedRemainingPercentAtReset = max(
            0,
            100 - projectedUsedPercentAtReset
        )
        let remainingCyclePercent = 100 - elapsedPercent
        let timeNeededPercentOfCycle = usedPercent > 0
            ? remainingPercent * elapsedPercent / usedPercent
            : .infinity
        let runwayCoverageRatio = remainingCyclePercent > 0
            ? timeNeededPercentOfCycle / remainingCyclePercent
            : .infinity
        let pace: QuotaConsumptionPace

        // Do not call a fresh-cycle burst an emergency while most capacity is
        // still available. Warning states require both low remaining quota and
        // insufficient projected runway, with a safety margin to avoid flapping.
        if remainingPercent <= 15, runwayCoverageRatio < 0.85 {
            pace = .critical
        } else if remainingPercent <= 25, runwayCoverageRatio < 0.5 {
            pace = .critical
        } else if remainingPercent <= 35, runwayCoverageRatio < 0.85 {
            pace = .warning
        } else if elapsedPercent >= 20,
                  projectedRemainingPercentAtReset >= 20 {
            pace = .slow
        } else {
            pace = .normal
        }

        return QuotaConsumptionPaceAssessment(
            pace: pace,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            elapsedPercent: elapsedPercent,
            relativeDifferencePercent: relativeDifferencePercent,
            projectedRemainingPercentAtReset: projectedRemainingPercentAtReset,
            runwayCoverageRatio: runwayCoverageRatio,
            lastResetAt: lastResetAt,
            nextResetAt: resetsAt
        )
    }

    static func quotaRemainingLevel(
        for remainingPercent: Double
    ) -> QuotaRemainingLevel {
        if remainingPercent <= 10 { return .critical }
        if remainingPercent <= 30 { return .warning }
        return .healthy
    }

    static func isFastServiceTier(_ serviceTier: String?) -> Bool {
        guard let normalized = serviceTier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return normalized == "priority" || normalized == "fast"
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

    /// Returns tasks that have just paused for explicit user input.
    static func inputRequestedThreadIDs(
        previousStates: [String: ThreadExecutionState],
        currentThreads: [ThreadSummary]
    ) -> [String] {
        currentThreads.compactMap { thread in
            guard previousStates[thread.id] != .waitingForInput,
                  thread.executionState == .waitingForInput else {
                return nil
            }
            return thread.id
        }
    }

    /// Uses lowercase effort labels, folding historical `minimal` and `light`
    /// records into `low` and abbreviating extra high to keep rows compact.
    static func reasoningEffortLabel(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        switch normalized {
        case "minimal", "low", "light": return "low"
        case "medium": return "medium"
        case "high": return "high"
        case "xhigh", "extra-high", "extra_high", "extra high": return "xhigh"
        case "max": return "max"
        case "ultra": return "ultra"
        default: return normalized
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

    /// `account/read` reports both Pro tiers as `pro`. The Codex quota bucket
    /// currently distinguishes the lower tier as `prolite`; keep an explicit
    /// fallback because that subtype is not a documented public contract.
    static func planBadgeLabel(
        accountPlanType: String?,
        rateLimitPlanType: String?
    ) -> String? {
        let accountPlan = normalizedPlanType(accountPlanType)
        let quotaPlan = normalizedPlanType(rateLimitPlanType)

        if accountPlan == "prolite" { return "PRO5X" }

        if accountPlan == "pro"
            || (accountPlan == nil && (quotaPlan == "prolite" || quotaPlan == "pro")) {
            switch quotaPlan {
            case "prolite": return "PRO5X"
            case "pro": return "PRO 20X"
            default: return "PRO"
            }
        }

        return (accountPlan ?? quotaPlan)?.uppercased()
    }

    /// User-defined display allowance: Plus baseline with the plan's multiplier.
    static func remainingCredits(planLabel: String?, remainingPercent: Double?) -> Double? {
        guard let remainingPercent, remainingPercent.isFinite else { return nil }
        let multiplier: Double
        switch planLabel?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PLUS": multiplier = 1
        case "PRO5X": multiplier = 5
        case "PRO 20X": multiplier = 20
        default: return nil
        }
        return 2_750 * multiplier * min(100, max(0, remainingPercent)) / 100
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

struct RateLimitWindow: Equatable, Sendable {
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

enum QuotaRemainingLevel: Equatable, Sendable {
    case healthy
    case warning
    case critical
}

struct QuotaConsumptionPaceAssessment: Equatable, Sendable {
    var pace: QuotaConsumptionPace
    var usedPercent: Double
    var remainingPercent: Double
    var elapsedPercent: Double
    var relativeDifferencePercent: Double
    var projectedRemainingPercentAtReset: Double
    var runwayCoverageRatio: Double
    var lastResetAt: Date
    var nextResetAt: Date
}

struct RateLimitBucket: Equatable, Sendable {
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
    /// Estimated cost of this exact cumulative usage, priced with each call's
    /// recorded model and tier rather than the thread's latest settings.
    var creditEstimate: CodexThreadCreditEstimate? = nil
}

enum ThreadExecutionState: Equatable, Sendable {
    case running
    case waitingForInput
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
    /// Local message-level Token increments for the last 30 calendar days.
    var dailyThreadTokens: [DailyUsageBucket] = []
    /// The same local activity expressed as Standard-mode quota, using each
    /// Fast call's model-specific quota multiplier.
    var billedTodayThreadTokens: Int64? = nil
    var billedHourlyThreadTokens: [HourlyUsageBucket] = []
    var billedDailyThreadTokens: [DailyUsageBucket] = []
    var chartCreditTotals: [Date: CodexChartCreditTotal] = [:]
    /// Calibrated from quota changes and priced local calls, independently of
    /// the display chart's account/local daily-history merge.
    var remainingTokenEstimate: CodexRemainingTokenEstimate? = nil
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

/// Numeric per-hour costs; incomplete history retains its known priced subtotal.
struct CodexChartCreditTotal: Equatable, Sendable {
    var tokens: Double = 0
    var credits: Double = 0
    var unpricedCalls: Int = 0

    var standardCredits: Double = 0
    var wastedCredits: Double { max(0, credits - standardCredits) }

    init(tokens: Double = 0, credits: Double = 0,
         standardCredits: Double? = nil, unpricedCalls: Int = 0) {
        self.tokens = tokens
        self.credits = credits
        self.standardCredits = standardCredits ?? credits
        self.unpricedCalls = unpricedCalls
    }

    mutating func merge(_ other: Self, sign: Double = 1) {
        tokens += sign * other.tokens
        credits += sign * other.credits
        standardCredits += sign * other.standardCredits
        unpricedCalls += Int(sign) * other.unpricedCalls
    }

    func displayText(matching actualTokens: Int64) -> String {
        // Account tokens can include other computers. Price local history
        // independently; only absent local records or missing local prices
        // affect the availability/completeness of this amount.
        guard tokens > 0 || actualTokens == 0 else { return "— credits" }
        return amountText(for: credits) + " credits"
    }

    func chartDisplayText(matching actualTokens: Int64, showsStandard: Bool, showsActual: Bool) -> String {
        guard tokens > 0 || actualTokens == 0 else { return "—" }
        var amounts: [String] = []
        if showsStandard { amounts.append(amountText(for: standardCredits)) }
        if showsActual { amounts.append(amountText(for: credits)) }
        return amounts.isEmpty ? "—" : amounts.joined(separator: " / ")
    }

    private func amountText(for cost: Double) -> String {
        guard cost.isFinite else { return "—" }
        let complete = unpricedCalls == 0
        guard complete || cost >= 0.1 else { return "—" }
        // A lower bound must never round above the known subtotal.
        let displayed = complete ? max(0, cost) : floor(cost * 10) / 10
        let amount = CodexThreadCreditEstimate(credits: displayed).amountText
        return complete ? amount : "≥" + amount
    }
}
