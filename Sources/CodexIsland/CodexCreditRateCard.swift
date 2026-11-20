import Foundation

/// Estimates included-subscription consumption using the current, validated rate card.
/// Purchased-credit multipliers are reference metadata, not inferred from rollout logs.
enum CodexCreditRateCard {
    typealias Rate = CodexCreditConfiguration.Rate

    static var revision: String? { CodexCreditConfiguration.current?.revision }

    static func rate(for model: String?) -> Rate? {
        CodexCreditConfiguration.current?.rate(for: model)
    }

    private static func includedSpeedMultiplier(
        model: String?, serviceTier: String?, configuration: CodexCreditConfiguration
    ) -> Double? {
        switch serviceTier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "default", "standard": return 1
        case "priority", "fast": return CodexFastModeUsagePolicy.multiplier(for: model, in: configuration)
        case "ultrafast": return configuration.ultrafastPolicy(for: model)?.includedSubscription
        default: return nil
        }
    }

    static func credits(
        model: String?,
        serviceTier: String?,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64
    ) -> Double? {
        estimatedCredits(model: model, serviceTier: serviceTier, inputTokens: inputTokens,
                         cachedInputTokens: cachedInputTokens, outputTokens: outputTokens)?.actual
    }

    static func estimatedCredits(
        model: String?,
        serviceTier: String?,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64
    ) -> (standard: Double, actual: Double)? {
        guard inputTokens >= 0, cachedInputTokens >= 0,
              cachedInputTokens <= inputTokens, outputTokens >= 0,
              let configuration = CodexCreditConfiguration.current,
              let rate = configuration.rate(for: model),
              let multiplier = includedSpeedMultiplier(model: model, serviceTier: serviceTier,
                                                       configuration: configuration) else { return nil }
        // Rollout input_tokens already INCLUDES cached_input_tokens, and
        // output_tokens already includes reasoning_output_tokens.
        let standard = (
            Double(inputTokens - cachedInputTokens) * rate.input
                + Double(cachedInputTokens) * rate.cachedInput
                + Double(outputTokens) * rate.output
        ) / 1_000_000
        let actual = standard * multiplier
        return actual.isFinite && actual >= 0 ? (standard, actual) : nil
    }
}
