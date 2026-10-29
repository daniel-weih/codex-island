import Foundation

/// Versioned pricing data. An invalid or absent card leaves calls unpriced.
/// Loaded once per process; restarting the app rebuilds its in-memory usage caches.
struct CodexCreditConfiguration: Decodable {
    static let resourceName = "CodexCreditRates"
    static let bundled = load(resources: .shared)

    struct Rate: Decodable, Equatable {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    struct Model: Decodable {
        let id: String
        let verifiedOn: String
        let rate: Rate
    }

    struct FastPolicy: Decodable {
        let family: String
        let verifiedOn: String
        let includedSubscription: Double
        // Optional for historical policies whose purchased-credit rate is unverified.
        let purchasedCredits: Double?
    }

    let schemaVersion: Int
    let revision: String
    let unit: String
    let sources: [String]
    let models: [Model]
    let fastPolicies: [FastPolicy]

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
