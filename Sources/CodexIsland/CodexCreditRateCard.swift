import Foundation

/// A dated rate card, not a fixed allowance for any subscription plan.
/// Current GPT-6 rates and Fast multipliers verified 2026-09-23.
/// Older model rates retained from the 2026-09-07 rate card.
/// https://learn.chatgpt.com/docs/pricing#token-rates
/// https://help.openai.com/en/articles/11481834-chatgpt-rate-card-business-enterpriseedu-credit-based-pricing
/// https://learn.chatgpt.com/docs/agent-configuration/speed
enum CodexCreditRateCard {
    static let revision = "2026-09-23"

    struct Rate: Equatable {
        var input: Double
        var cachedInput: Double
        var output: Double
    }

    private static let rates: [String: Rate] = [
        "gpt-6-astra": Rate(input: 250, cachedInput: 25, output: 1_250),
        "gpt-6-sol": Rate(input: 50, cachedInput: 5, output: 250),
        "gpt-6-luna": Rate(input: 2.5, cachedInput: 0.25, output: 12.5),
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
