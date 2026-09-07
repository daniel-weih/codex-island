import Foundation

/// A dated rate card, not a fixed allowance for any subscription plan.
/// Sources (verified 2026-09-07):
/// https://help.openai.com/en/articles/11481834-chatgpt-rate-card-business-enterpriseedu-credit-based-pricing
/// https://learn.chatgpt.com/docs/agent-configuration/speed
/// Purchased-credit promotions do not necessarily change included limits.
/// The estimator therefore learns the quota conversion from observed usage.
enum CodexCreditRateCard {
    static let revision = "2026-09-07"

    struct Rate: Equatable {
        var input: Double
        var cachedInput: Double
        var output: Double
    }

    private static let rates: [String: Rate] = [
        "gpt-6-astra": Rate(input: 250, cachedInput: 25, output: 1_250),
        "gpt-5.6-sol": Rate(input: 100, cachedInput: 10, output: 500),
        "gpt-5.6-terra": Rate(input: 50, cachedInput: 5, output: 300),
        "gpt-5.6-luna": Rate(input: 5, cachedInput: 0.5, output: 30),
        "gpt-5.5": Rate(input: 125, cachedInput: 12.5, output: 750),
        "gpt-5.4": Rate(input: 62.5, cachedInput: 6.25, output: 375),
        "gpt-5.4-mini": Rate(input: 18.75, cachedInput: 1.875, output: 113),
        "gpt-5.3-codex": Rate(input: 43.75, cachedInput: 4.375, output: 350),
        "gpt-5.2": Rate(input: 43.75, cachedInput: 4.375, output: 350)
    ]

    static func rate(for model: String?) -> Rate? {
        guard let model else { return nil }
        let slug = model.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        if let rate = rates[slug] { return rate }
        // Accept dated snapshots, but never assign a larger family's price to
        // an unlisted mini, Spark, image, auto-review, or other model variant.
        for (name, rate) in rates where slug.hasPrefix(name + "-") {
            let suffix = String(slug.dropFirst(name.count + 1))
            if suffix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                return rate
            }
        }
        return nil
    }

    static func credits(
        model: String?,
        serviceTier: String?,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64
    ) -> Double? {
        guard inputTokens >= 0, cachedInputTokens >= 0,
              cachedInputTokens <= inputTokens, outputTokens >= 0,
              let rate = rate(for: model) else { return nil }
        let tier = serviceTier?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let multiplier: Double
        if CodexDisplayPolicy.isFastServiceTier(tier) {
            guard let fastMultiplier = CodexFastModeUsagePolicy.multiplier(for: model) else {
                return nil
            }
            multiplier = fastMultiplier
        } else if tier == nil || tier == "default" || tier == "standard" {
            multiplier = 1
        } else {
            return nil
        }
        // Rollout input_tokens already INCLUDES cached_input_tokens, and
        // output_tokens already includes reasoning_output_tokens.
        let value = (
            Double(inputTokens - cachedInputTokens) * rate.input
                + Double(cachedInputTokens) * rate.cachedInput
                + Double(outputTokens) * rate.output
        ) / 1_000_000 * multiplier
        return value.isFinite && value >= 0 ? value : nil
    }
}

/// Only numeric usage and the quota identity are retained, never prompt text.
struct CodexTokenCostSample: Equatable, Sendable {
    var timestamp: Date
    var tokens: Int64
    var credits: Double?
    var quota: RateLimitBucket
}

struct CodexRemainingTokenEstimate: Equatable, Sendable {
    var tokens: Int64
    var windowDurationMinutes: Int
    var resetsAt: Date
    var sampleCount: Int
    var observedQuotaPercent: Double
    var pricedTokenCoverage: Double
    var usesHistoricalCalibration: Bool = false
}

enum CodexTokenEstimator {
    static let historyInterval = TimeInterval(CodexDisplayPolicy.usageHabitDayCount * 24 * 60 * 60)
    static let minimumQuotaChange = 5.0
    private static let minimumCoverage = 0.9
    private static let habitHalfLife: TimeInterval = 3 * 24 * 60 * 60

    /// Uses the recent workload's actual model/Fast mix. Each reset cycle is
    /// calibrated separately; recent same-plan cycles can supply a baseline
    /// until the current one has enough observations. No fixed plan capacity
    /// or purchased-credit-to-included-quota conversion is assumed.
    static func estimate(
        quota: RateLimitBucket?,
        samples: [CodexTokenCostSample],
        now: Date = Date(),
        historyNotBefore: Date? = nil
    ) -> CodexRemainingTokenEstimate? {
        guard let quota, let primary = quota.primary,
              valid(primary, now: now) else { return nil }
        var windows = [primary]
        if let secondary = quota.secondary {
            guard valid(secondary, now: now) else { return nil }
            windows.append(secondary)
        }
        if let exhausted = windows.first(where: { $0.remainingPercent == 0 }) {
            return CodexRemainingTokenEstimate(
                tokens: 0,
                windowDurationMinutes: exhausted.windowDurationMinutes!,
                resetsAt: exhausted.resetsAt!,
                sampleCount: 0,
                observedQuotaPercent: 0,
                pricedTokenCoverage: 1
            )
        }

        let eligible = samples.filter {
            $0.timestamp > now.addingTimeInterval(-historyInterval)
                && $0.timestamp <= now
                && $0.timestamp >= (historyNotBefore ?? .distantPast)
                && $0.quota.id == quota.id
                && normalized($0.quota.planType) == normalized(quota.planType)
        }.sorted { $0.timestamp < $1.timestamp }
        var estimates: [CodexRemainingTokenEstimate] = []
        for window in windows {
            guard let value = estimate(window: window, samples: eligible, now: now) else {
                // A second allowance can be the actual bottleneck. Do not
                // advertise the primary's capacity when that constraint is unknown.
                return nil
            }
            estimates.append(value)
        }
        return estimates.min { $0.tokens < $1.tokens }
    }

    private struct ObservedSample {
        var sample: CodexTokenCostSample
        var percent: Double
        var resetsAt: Date
    }

    private struct Calibration {
        var capacity: Double
        var weight: Double
        var quotaChange: Double
        var resetsAt: Date
    }

    private static func estimate(
        window: RateLimitWindow,
        samples: [CodexTokenCostSample],
        now: Date
    ) -> CodexRemainingTokenEstimate? {
        let duration = window.windowDurationMinutes!
        let resetsAt = window.resetsAt!
        var matching: [ObservedSample] = []
        for sample in samples {
            let observed = [sample.quota.primary, sample.quota.secondary]
                .compactMap { $0 }
                .first { $0.windowDurationMinutes == duration }
            guard let observed, let observedReset = observed.resetsAt,
                  observedReset <= resetsAt,
                  valid(observed, now: sample.timestamp) else { continue }
            matching.append(ObservedSample(
                sample: sample, percent: observed.usedPercent, resetsAt: observedReset
            ))
        }

        var totalTokens = 0.0
        var pricedTokens = 0.0
        var habitTokens = 0.0
        var habitCredits = 0.0
        var sampleCount = 0
        for observed in matching where observed.sample.tokens > 0 {
            let sample = observed.sample
            totalTokens += Double(sample.tokens)
            guard let credits = sample.credits, credits.isFinite, credits > 0 else { continue }
            pricedTokens += Double(sample.tokens)
            let weight = pow(0.5, now.timeIntervalSince(sample.timestamp) / habitHalfLife)
            habitTokens += Double(sample.tokens) * weight
            habitCredits += credits * weight
            sampleCount += 1
        }
        guard sampleCount >= 10, totalTokens > 0,
              pricedTokens / totalTokens >= minimumCoverage,
              habitTokens > 0, habitCredits > 0 else { return nil }

        // Never subtract percentages across a reset. Combine all sessions
        // inside each cycle, then compare the independently inferred capacities.
        let cycles = Dictionary(grouping: matching, by: \.resetsAt)
        let allCalibrations = cycles.values.flatMap { calibrate($0, now: now) }
        let currentCalibrations = allCalibrations.filter { $0.resetsAt == resetsAt }
        let calibrations = currentCalibrations.count >= 2 ? currentCalibrations : allCalibrations
        guard calibrations.count >= 2,
              let capacity = weightedMedian(calibrations) else { return nil }
        let creditsPerToken = habitCredits / habitTokens
        let remaining = capacity * window.remainingPercent / 100 / creditsPerToken
        guard remaining.isFinite, remaining >= 0,
              remaining < Double(Int64.max) else { return nil }
        return CodexRemainingTokenEstimate(
            tokens: Int64(remaining.rounded(.down)),
            windowDurationMinutes: duration,
            resetsAt: resetsAt,
            sampleCount: sampleCount,
            observedQuotaPercent: calibrations.reduce(0) { $0 + $1.quotaChange },
            pricedTokenCoverage: pricedTokens / totalTokens,
            usesHistoricalCalibration: currentCalibrations.count < 2
        )
    }

    private static func calibrate(_ samples: [ObservedSample], now: Date) -> [Calibration] {
        var anchorPercent: Double?
        var intervalCredits = 0.0
        var intervalTokens = 0.0
        var intervalPricedTokens = 0.0
        var intervalCalls = 0
        var calibrations: [Calibration] = []
        for observed in samples {
            let sample = observed.sample
            let percent = observed.percent
            guard let anchor = anchorPercent else {
                anchorPercent = percent
                continue
            }
            if sample.tokens > 0 {
                intervalTokens += Double(sample.tokens)
                if let credits = sample.credits, credits.isFinite, credits > 0 {
                    intervalCredits += credits
                    intervalPricedTokens += Double(sample.tokens)
                    intervalCalls += 1
                }
            }
            // Ignore stale lower percentages. 100% is censored after a limit
            // is reached, so it cannot be a calibration endpoint.
            let change = percent - anchor
            guard change >= minimumQuotaChange else { continue }
            if percent < 100, intervalCalls >= 3, intervalTokens > 0,
               intervalPricedTokens / intervalTokens >= minimumCoverage {
                let capacity = intervalCredits / change * 100
                let recency = pow(0.5, now.timeIntervalSince(sample.timestamp) / habitHalfLife)
                if capacity.isFinite, capacity > 0 {
                    calibrations.append(Calibration(
                        capacity: capacity, weight: change * recency,
                        quotaChange: change, resetsAt: observed.resetsAt
                    ))
                }
            }
            anchorPercent = percent
            intervalCredits = 0
            intervalTokens = 0
            intervalPricedTokens = 0
            intervalCalls = 0
        }
        return calibrations
    }

    private static func weightedMedian(_ values: [Calibration]) -> Double? {
        let ordered = values.sorted { $0.capacity < $1.capacity }
        let midpoint = ordered.reduce(0) { $0 + $1.weight } / 2
        var cumulative = 0.0
        for value in ordered {
            cumulative += value.weight
            if cumulative >= midpoint { return value.capacity }
        }
        return nil
    }

    private static func valid(_ window: RateLimitWindow, now: Date) -> Bool {
        guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              let minutes = window.windowDurationMinutes, minutes > 0,
              let reset = window.resetsAt else { return false }
        return now < reset && now >= reset.addingTimeInterval(-Double(minutes) * 60)
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
