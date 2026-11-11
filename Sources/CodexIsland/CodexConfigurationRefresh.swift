import Foundation

/// Parses the official documentation, never a model-generated price guess.
enum CodexConfigurationRefresh {
    static let pricingURL = URL(string: "https://learn.chatgpt.com/docs/pricing.md")!

    enum RefreshError: LocalizedError {
        case invalidSource, invalidCatalog, invalidAA
        var errorDescription: String? {
            switch self {
            case .invalidSource: return "官方费率页面格式变化或数据不完整，已保留上次配置。 / Official pricing could not be verified; previous configuration retained."
            case .invalidCatalog: return "Codex 模型目录不可用，已保留上次目录。 / Model catalog unavailable; previous catalog retained."
            case .invalidAA: return "AA 评分不可用，已保留上次数据。 / AA scores unavailable; previous data retained."
            }
        }
    }

    static func fetchPricing() async throws -> String {
        try await fetchPage(pricingURL)
    }

    static func fetchPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == url.host, http.url?.scheme == "https",
              data.count <= 8_000_000, let text = String(data: data, encoding: .utf8) else {
            throw RefreshError.invalidSource
        }
        return text
    }

    static func applyingPricing(_ text: String, to original: CodexCreditConfiguration,
                                now: Date = Date()) throws -> CodexCreditConfiguration {
        let date = ISO8601DateFormatter().string(from: now).prefix(10).description
        // Scope extraction to the table with explicit credit units and all three token columns.
        let tables = captures(#"(?is)<table\b[^>]*>(.*?)</table>"#, text).map { $0[0] }
        guard let table = tables.first(where: {
            $0.contains("Credits per 1M tokens") && $0.contains("Cached input tokens") && $0.contains("Output Tokens")
        }) else { throw RefreshError.invalidSource }
        var parsed: [CodexCreditConfiguration.Model] = []
        for row in captures(#"(?is)<tr\b[^>]*>(.*?)</tr>"#, table) {
            let cells = captures(#"(?is)<td\b[^>]*>(.*?)</td>"#, row[0]).map { stripTags($0[0]) }
            guard cells.count == 4 else { continue }
            // Text model IDs have a direct documented display-name → slug mapping.
            // Image modality rows must not be flattened into text token rates.
            let name = cells[0].lowercased()
            guard !name.contains("("), !name.contains("image") else { continue }
            let id = name.replacingOccurrences(of: " ", with: "-")
            guard id.range(of: #"^[a-z0-9][a-z0-9.-]*$"#, options: .regularExpression) != nil else { continue }
            let amounts = cells.dropFirst().compactMap { cell -> Double? in
                guard cell.hasSuffix(" credits") else { return nil }
                return Double(cell.replacingOccurrences(of: " credits", with: "").replacingOccurrences(of: ",", with: ""))
            }
            guard amounts.count == 3, !parsed.contains(where: { $0.id == id }) else { throw RefreshError.invalidSource }
            parsed.append(.init(id: id, verifiedOn: date, rate: .init(input: amounts[0], cachedInput: amounts[1], output: amounts[2])))
        }
        guard !parsed.isEmpty else { throw RefreshError.invalidSource }
        // Match the speed table and its billing columns, not API prices or prose speed ratios.
        guard let header = text.range(of: #"(?m)^\|\s*Speed mode\s*\|\s*Included subscription usage\s*\|\s*Purchased credits and Enterprise pay-as-you-go usage\s*\|"#, options: .regularExpression) else {
            throw RefreshError.invalidSource
        }
        let section = String(text[header.lowerBound...]).components(separatedBy: "\n\n").first ?? ""
        let fast = captures(#"(?m)^\|\s*Fast\s*\|\s*([0-9.]+)x\s*\|\s*([0-9.]+)x\s*\|"#, section)
        guard fast.count == 1, let included = Double(fast[0][0]), let purchased = Double(fast[0][1]) else {
            throw RefreshError.invalidSource
        }
        var result = original.retainingCodexModels()
        let allowed = Set(result.models.map(\.id) + (result.knownCodexModelIDs ?? []))
        result.revision = max(original.revision, date)
        for model in parsed where allowed.contains(model.id) {
            if let index = result.models.firstIndex(where: { $0.id == model.id }) { result.models[index] = model }
            else { result.models.append(model) }
            // A price row alone does not establish that Fast exists for this model.
            guard result.fastModels.contains(where: { $0.id == model.id }) else { continue }
            let policy = CodexCreditConfiguration.FastPolicy(family: model.id, verifiedOn: date,
                                                             includedSubscription: included, purchasedCredits: purchased)
            if let index = result.fastPolicies.firstIndex(where: { $0.family == model.id }) { result.fastPolicies[index] = policy }
            else { result.fastPolicies.append(policy) }
        }
        // Retired models keep their dated historical reference rates. Project plan estimates
        // are deliberately preserved: the official page does not publish fixed plan balances.
        result.pricingUpdatedAt = now
        return try CodexCreditConfiguration.decode(JSONEncoder().encode(result))
    }

    static func listModels() async throws -> [CodexCreditConfiguration.CatalogModel] {
        let startedAt = Date()
        let client = CodexAppServerClient(clientName: "codex_island_catalog")
        defer { client.stop() }
        return try await withTaskCancellationHandler(operation: {
            try await client.start()
            var models: [CodexCreditConfiguration.CatalogModel] = []
            var cursor: String?
            var seen = Set<String>()
            repeat {
                var params: JSONObject = ["limit": 100, "includeHidden": false]
                if let cursor { params["cursor"] = cursor }
                let response = try await client.request(method: "model/list", params: params)
                guard let items = response.array("data") as? [JSONObject] else { throw RefreshError.invalidCatalog }
                for item in items where item.bool("hidden") != true {
                    guard let id = item.string("model") ?? item.string("id"),
                          let name = item.string("displayName") else { throw RefreshError.invalidCatalog }
                    if models.contains(where: { $0.id == id }) { continue }
                    models.append(.init(id: id, displayName: name,
                        reasoningEfforts: (item.array("supportedReasoningEfforts") as? [JSONObject] ?? []).compactMap { $0.string("reasoningEffort") },
                        serviceTiers: (item.array("serviceTiers") as? [JSONObject] ?? []).compactMap { $0.string("id") }))
                }
                cursor = response.string("nextCursor")
                if let cursor, !seen.insert(cursor).inserted { throw RefreshError.invalidCatalog }
                guard seen.count < 20 else { throw RefreshError.invalidCatalog }
            } while cursor != nil
            guard !models.isEmpty else { throw RefreshError.invalidCatalog }
            return reconcileCatalog(models, cacheData: readModelCache(), newerThan: startedAt.addingTimeInterval(-300))
        }, onCancel: { client.stop() })
    }

    static func readModelCache() -> Data? {
        let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { ($0 as NSString).expandingTildeInPath }
        let home = configuredHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return try? Data(contentsOf: home.appendingPathComponent("models_cache.json"))
    }

    /// Some CLI catalogs include bundled fallback models. A newer remote catalog
    /// bounds picker availability; prices and historical usage never establish it.
    static func reconcileCatalog(_ models: [CodexCreditConfiguration.CatalogModel], cacheData: Data?,
                                 newerThan date: Date, now: Date = Date()) -> [CodexCreditConfiguration.CatalogModel] {
        struct Cache: Decodable {
            struct Model: Decodable { let slug: String; let visibility: String }
            let fetched_at: String
            let models: [Model]
        }
        guard let cacheData, let cache = try? JSONDecoder().decode(Cache.self, from: cacheData) else { return models }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fetchedAt = formatter.date(from: cache.fetched_at)
            ?? ISO8601DateFormatter().date(from: cache.fetched_at)
        guard let fetchedAt, fetchedAt >= date, fetchedAt <= now,
              !cache.models.isEmpty,
              cache.models.allSatisfy({ !$0.slug.isEmpty && ["list", "hide"].contains($0.visibility) }),
              Set(cache.models.map(\.slug)).count == cache.models.count else { return models }
        let visibleIDs = Set(cache.models.filter { $0.visibility == "list" }.map(\.slug))
        guard !visibleIDs.isEmpty else { return models }
        // Keep app-server metadata and auth filtering; never add cache-only models.
        return models.filter { visibleIDs.contains($0.id) }
    }

    static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }
    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
