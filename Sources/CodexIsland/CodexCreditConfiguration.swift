import Foundation

/// Versioned pricing data. An invalid or absent card leaves calls unpriced.
/// Bundled fallback plus an atomically installed, validated runtime configuration.
struct CodexCreditConfiguration: Codable {
    static let resourceName = "CodexCreditRates"
    static let bundled = load(resources: .shared)
    private static let runtimeLock = NSLock()
    private static var runtime: Self? = bundled
    private static var runtimeGeneration: UInt64 = 0
    static var current: Self? { runtimeLock.withLock { runtime } }
    static var generation: UInt64 { runtimeLock.withLock { runtimeGeneration } }
    static func activate(_ configuration: Self) {
        runtimeLock.withLock { runtime = configuration; runtimeGeneration &+= 1 }
    }

    struct CatalogModel: Codable, Equatable {
        let id: String
        let displayName: String
        let reasoningEfforts: [String]
        let serviceTiers: [String]
        var supportsFast: Bool {
            serviceTiers.contains { ["fast", "priority"].contains($0.lowercased()) }
        }
    }

    struct SubscriptionEstimate: Codable {
        let credits: Double
        let basis: String
    }

    // Remember models actually observed in Codex, so retired models can still price old logs.
    var knownCodexModelIDs: [String]? = nil
    var catalog: [CatalogModel]? = nil
    var catalogUpdatedAt: Date? = nil
    var pricingUpdatedAt: Date? = nil
    var subscriptionEstimates: [String: SubscriptionEstimate]? = nil
    var subscriptionMultipliers: [String: Double]? = nil
    var updateIntervalDays: Int? = nil

    struct Rate: Codable, Equatable {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    struct Model: Codable {
        let id: String
        let verifiedOn: String
        let rate: Rate
    }

    struct FastPolicy: Codable {
        let family: String
        let verifiedOn: String
        let includedSubscription: Double
        // Optional for historical policies whose purchased-credit rate is unverified.
        let purchasedCredits: Double?
    }

    let schemaVersion: Int
    var revision: String
    let unit: String
    let sources: [String]
    var models: [Model]
    var fastPolicies: [FastPolicy]

    static func load(resources: AppResources) -> Self? {
        guard let data = resources.data(named: resourceName, withExtension: "json") else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> Self {
        let card = try JSONDecoder().decode(Self.self, from: data)
        guard card.schemaVersion == 1,
              card.unit == "credits_per_million_tokens",
              isDate(card.revision),
              !card.sources.isEmpty,
              card.sources.allSatisfy({ URL(string: $0)?.scheme == "https" && URL(string: $0)?.host != nil }),
              (card.updateIntervalDays.map { (1...365).contains($0) } ?? true),
              (card.subscriptionEstimates?.allSatisfy { isID($0.key) && $0.value.credits.isFinite && $0.value.credits > 0 && !$0.value.basis.isEmpty } ?? true),
              (card.subscriptionMultipliers?.allSatisfy { plan, multiplier in
                  isID(plan) && plan != "plus" && multiplier.isFinite && multiplier > 0
                      && card.subscriptionEstimates?["plus"].map { ($0.credits * multiplier).isFinite } == true
              } ?? true),
              (card.catalog.map { Set($0.map(\.id)).count == $0.count && $0.allSatisfy { isID($0.id) && !$0.displayName.isEmpty } } ?? true),
              (card.knownCodexModelIDs.map { Set($0).count == $0.count && $0.allSatisfy(isID) } ?? true),
              !card.models.isEmpty,
              Set(card.models.map(\.id)).count == card.models.count,
              Set(card.fastPolicies.map(\.family)).count == card.fastPolicies.count,
              card.models.allSatisfy({ model in
                  isID(model.id) && isDate(model.verifiedOn) && model.verifiedOn <= card.revision
                      && [model.rate.input, model.rate.cachedInput, model.rate.output]
                          .allSatisfy { $0.isFinite && $0 > 0 }
                      && model.rate.cachedInput <= model.rate.input
              }),
              card.fastPolicies.allSatisfy({ policy in
                  isID(policy.family) && isDate(policy.verifiedOn) && policy.verifiedOn <= card.revision
                      && policy.includedSubscription.isFinite && policy.includedSubscription >= 1
                      && (policy.purchasedCredits.map { $0.isFinite && $0 >= 1 } ?? true)
                      && card.models.contains { $0.id == policy.family || $0.id.hasPrefix(policy.family + "-") }
              }) else {
            throw ValidationError.invalidRateCard
        }
        return card
    }

    func subscriptionCredits(for plan: String) -> Double? {
        if let multiplier = subscriptionMultipliers?[plan] {
            guard let plus = subscriptionEstimates?["plus"]?.credits else { return nil }
            let value = plus * multiplier
            return value.isFinite && value > 0 ? value : nil
        }
        return subscriptionEstimates?[plan]?.credits
    }

    /// Convert old independent Pro estimates into ratios, preserving the user's Plus value.
    func migratingSubscriptionEstimates() -> Self {
        var result = self
        if result.subscriptionMultipliers == nil {
            result.subscriptionMultipliers = Self.bundled?.subscriptionMultipliers
            if result.subscriptionEstimates?["plus"] == nil,
               let plus = Self.bundled?.subscriptionEstimates?["plus"] {
                if result.subscriptionEstimates == nil { result.subscriptionEstimates = [:] }
                result.subscriptionEstimates?["plus"] = plus
            }
        }
        for plan in (result.subscriptionMultipliers ?? [:]).keys {
            result.subscriptionEstimates?.removeValue(forKey: plan)
        }
        return result
    }

    /// Highest Standard output-token credit rate first; unknown rates last.
    /// Preserve catalog order for equal prices to avoid reshuffling on refresh.
    var modelsByOutputCost: [CatalogModel] {
        (catalog ?? []).enumerated().sorted { lhs, rhs in
            let left = rate(for: lhs.element.id)?.output ?? -.infinity
            let right = rate(for: rhs.element.id)?.output ?? -.infinity
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    var fastModels: [CatalogModel] {
        modelsByOutputCost.filter { $0.supportsFast }
    }

    /// Only the Codex catalog establishes availability. Pricing rows never add models.
    func retainingCodexModels() -> Self {
        var result = self
        let observed = Set((knownCodexModelIDs ?? []) + (catalog ?? []).map(\.id))
        result.knownCodexModelIDs = observed.sorted()
        let allowed = observed.union(Self.bundled?.models.map(\.id) ?? [])
        result.models.removeAll { !allowed.contains($0.id) }
        result.fastPolicies.removeAll { policy in
            !allowed.contains { $0 == policy.family || $0.hasPrefix(policy.family + "-") }
        }
        return result
    }

    func rate(for model: String?) -> Rate? {
        guard let slug = Self.normalizedModel(model) else { return nil }
        if let exact = models.first(where: { $0.id == slug }) { return exact.rate }
        // Only dated snapshots inherit prices; unknown variants stay unpriced.
        return models.first { entry in
            slug.hasPrefix(entry.id + "-")
                && Self.isDate(String(slug.dropFirst(entry.id.count + 1)))
        }?.rate
    }

    func fastPolicy(for model: String?) -> FastPolicy? {
        guard let slug = Self.normalizedModel(model) else { return nil }
        // Preserve historical family matching, preferring the most specific entry.
        return fastPolicies.filter {
            slug == $0.family || slug.hasPrefix($0.family + "-")
        }.max { $0.family.count < $1.family.count }
    }

    private static func normalizedModel(_ model: String?) -> String? {
        model?.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/").last.map { $0.lowercased() }
    }

    private static func isID(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9][a-z0-9.-]*$"#, options: .regularExpression) != nil
    }

    private static func isDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }

    private enum ValidationError: Error {
        case invalidRateCard
    }
}
