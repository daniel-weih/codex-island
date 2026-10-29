import Foundation

/// Estimates included-subscription consumption using the bundled, validated rate card.
/// Purchased-credit multipliers are reference metadata, not inferred from rollout logs.
enum CodexCreditRateCard {
    typealias Rate = CodexCreditConfiguration.Rate

    static var revision: String? { CodexCreditConfiguration.bundled?.revision }

    static func rate(for model: String?) -> Rate? {
        CodexCreditConfiguration.bundled?.rate(for: model)
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
