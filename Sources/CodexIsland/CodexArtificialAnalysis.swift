import Foundation
import CoreFoundation

/// Reads the public site's serialized page data without executing its JavaScript.
enum CodexArtificialAnalysis {
    static let modelsURL = URL(string: "https://artificialanalysis.ai/models")!
    private static let efforts = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]

    static func fetchScores(_ models: [CodexCreditConfiguration.CatalogModel]) async throws -> [CodexCreditConfiguration.AAScore] {
        let index = try await CodexConfigurationRefresh.fetchPage(modelsURL)
        let releases = try releaseURLs(in: index, models: models)
        var scores: [CodexCreditConfiguration.AAScore] = []
        // One request per release, not per reasoning effort. Bound work for unexpected catalogs.
        guard releases.count <= 40 else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
        for model in models {
            try Task.checkCancellation()
            guard let url = releases[model.id] else { continue }
            let page = try await CodexConfigurationRefresh.fetchPage(url)
            scores += try parseScores(page, modelID: model.id, source: url)
        }
        return scores
    }

    static func releaseURLs(in html: String, models: [CodexCreditConfiguration.CatalogModel]) throws -> [String: URL] {
        let objects = try pageObjects(html)
        let allowed = Set(models.map(\.id))
        var result: [String: URL] = [:]
        var hasRelease = false
        for object in objects {
            guard (object["creator"] as? [String: Any])?["slug"] as? String == "openai",
                  object["release"] == nil, object["releaseDate"] is String,
                  let name = object["name"] as? String, let slug = object["slug"] as? String else { continue }
            let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
            // Exact release identity prevents matching a similarly named specialist variant.
            guard slug == id.replacingOccurrences(of: ".", with: "-") else { continue }
            hasRelease = true
            if allowed.contains(id) {
                result[id] = modelsURL.appendingPathComponent("releases").appendingPathComponent(slug)
            }
        }
        guard hasRelease else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
        return result
    }

    static func parseScores(_ html: String, modelID: String, source: URL) throws -> [CodexCreditConfiguration.AAScore] {
        let objects = try pageObjects(html)
        let versions = Set(objects.compactMap { object -> String? in
            guard object["slug"] as? String == "artificial-analysis-intelligence-index",
                  let name = object["name"] as? String else { return nil }
            return CodexConfigurationRefresh.captures(#"^Artificial Analysis Intelligence Index (v[0-9]+(?:\.[0-9]+)*)$"#, name).first?.first
        })
        guard versions.count == 1, let version = versions.first else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
        var result: [String: CodexCreditConfiguration.AAScore] = [:]
        for object in objects {
            guard (object["creator"] as? [String: Any])?["slug"] as? String == "openai",
                  let release = object["release"] as? [String: Any], let releaseName = release["name"] as? String,
                  releaseName.lowercased().replacingOccurrences(of: " ", with: "-") == modelID,
                  release["slug"] as? String == modelID.replacingOccurrences(of: ".", with: "-"),
                  let name = object["name"] as? String,
                  let rawScore = object["intelligenceIndex"] else { continue }
            // Release pages currently omit effort.slug; the exact displayed suffix is authoritative.
            let suffix = CodexConfigurationRefresh.captures(
                "^" + NSRegularExpression.escapedPattern(for: releaseName) + #" \(([A-Za-z-]+)\)$"#, name).first?.first?.lowercased()
            let effort = (object["effort"] as? [String: Any])?["slug"] as? String
                ?? (suffix == "non-reasoning" ? "none" : suffix)
            guard let effort, efforts.contains(effort) else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
            let score: Double?
            if rawScore is NSNull { score = nil }
            else {
                guard let number = rawScore as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, (0...100).contains(number.doubleValue) else {
                    throw CodexConfigurationRefresh.RefreshError.invalidAA
                }
                score = number.doubleValue
            }
            let entry = CodexCreditConfiguration.AAScore(model: modelID, effort: effort, score: score,
                                                        version: version, source: source.absoluteString)
            if let previous = result[effort], previous != entry { throw CodexConfigurationRefresh.RefreshError.invalidAA }
            result[effort] = entry
        }
        guard !result.isEmpty else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
        return efforts.compactMap { result[$0] }
    }

    private static func pageObjects(_ html: String) throws -> [[String: Any]] {
        guard html.utf8.count <= 8_000_000 else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
        var stream = ""
        for match in CodexConfigurationRefresh.captures(#"(?s)self\.__next_f\.push\((\[.*?\])\)</script>"#, html) {
            guard let data = match[0].data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  chunk.count == 2, chunk[0] as? Int == 1, let payload = chunk[1] as? String else { continue }
            stream += payload
        }
        var objects: [[String: Any]] = []
        func visit(_ value: Any, depth: Int = 0) {
            guard depth < 100 else { return }
            if let object = value as? [String: Any] {
                objects.append(object)
                for child in object.values { visit(child, depth: depth + 1) }
            } else if let array = value as? [Any] {
                for child in array { visit(child, depth: depth + 1) }
            }
        }
        // Flight chunks can split JSON records; join first, then decode complete records.
        for line in stream.split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":"),
                  let data = String(line[line.index(after: separator)...]).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else { continue }
            visit(value)
        }
        guard !objects.isEmpty else { throw CodexConfigurationRefresh.RefreshError.invalidAA }
        return objects
    }
}
