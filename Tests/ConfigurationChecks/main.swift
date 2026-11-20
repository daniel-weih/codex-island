import Foundation

@main
struct ConfigurationChecks {
    @MainActor
    static func main() async throws {
        let navigation = IslandNavigation()
        navigation.toggleModelInformation()
        precondition(navigation.page == .modelInformation)
        navigation.toggleModelInformation()
        precondition(navigation.page == .dashboard)
        navigation.navigate(to: .islandSettings)
        navigation.toggleModelInformation()
        navigation.back()
        precondition(navigation.page == .islandSettings)
        navigation.toggleModelInformation()
        navigation.reset()
        navigation.toggleModelInformation()
        navigation.back()
        precondition(navigation.page == .dashboard)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var base = try CodexCreditConfiguration.decode(Data(contentsOf: root.appendingPathComponent("Sources/CodexIsland/Resources/CodexCreditRates.json")))
        base.catalog = [
            .init(id: "gpt-6.1-sol", displayName: "GPT-6.1 Sol", reasoningEfforts: ["high"], serviceTiers: ["priority"]),
            .init(id: "gpt-6.1-terra", displayName: "GPT-6.1 Terra", reasoningEfforts: ["high"], serviceTiers: []),
            .init(id: "gpt-fixture", displayName: "GPT-Fixture", reasoningEfforts: ["high"], serviceTiers: ["fast"])
        ]
        let fixture = try String(contentsOf: root.appendingPathComponent("Tests/ConfigurationChecks/pricing.md"), encoding: .utf8)
        let aaFixture = try String(contentsOf: root.appendingPathComponent("Tests/ConfigurationChecks/aa.html"), encoding: .utf8)
        let aaSource = URL(string: "https://artificialanalysis.ai/models/releases/gpt-6-1-sol")!
        let aaScores = try CodexArtificialAnalysis.parseScores(aaFixture, modelID: "gpt-6.1-sol", source: aaSource)
        precondition(aaScores.map(\.effort) == ["low", "medium", "high", "xhigh", "max"])
        precondition(aaScores.first?.score == 34.8029244314559 && aaScores.last?.score == 54.6087338138148)
        precondition(aaScores.allSatisfy { $0.version == "v5.0.1" })
        let releaseURLs = try CodexArtificialAnalysis.releaseURLs(in: aaFixture, models: base.catalog!)
        precondition(releaseURLs == ["gpt-6.1-sol": aaSource])
        for invalid in ["<html>Unavailable</html>", aaFixture.replacingOccurrences(of: "34.8029244314559", with: "-1"),
                        aaFixture.replacingOccurrences(of: "34.8029244314559", with: "true"),
                        aaFixture.replacingOccurrences(of: "v5.0.1", with: "unknown"),
                        aaFixture.replacingOccurrences(of: "GPT-6.1 Sol", with: "GPT-6 Sol")] {
            do { _ = try CodexArtificialAnalysis.parseScores(invalid, modelID: "gpt-6.1-sol", source: aaSource); fatalError("Invalid AA page accepted") }
            catch {}
        }
        let unscored = try CodexArtificialAnalysis.parseScores(aaFixture.replacingOccurrences(of: "34.8029244314559", with: "null"), modelID: "gpt-6.1-sol", source: aaSource)
        precondition(unscored.first?.score == nil)
        let nonReasoning = try CodexArtificialAnalysis.parseScores(aaFixture.replacingOccurrences(of: "(Low)", with: "(Non-reasoning)"), modelID: "gpt-6.1-sol", source: aaSource)
        precondition(nonReasoning.first?.effort == "none" && nonReasoning.first?.score == aaScores.first?.score)
        var aaTable = base
        aaTable.catalog = ["gpt-6.9-sol", "gpt-6.10-sol", "gpt-6-terra", "gpt-6-luna"].map {
            .init(id: $0, displayName: $0, reasoningEfforts: ["low", "high"], serviceTiers: [])
        }
        precondition(Set(aaTable.aaModels.map(\.id)) == ["gpt-6.10-sol", "gpt-6-terra", "gpt-6-luna"])
        func score(_ model: String, _ effort: String, _ value: Double?) -> CodexCreditConfiguration.AAScore {
            .init(model: model, effort: effort, score: value, version: "v5.0.1", source: aaSource.absoluteString)
        }
        aaTable.aaScores = [score("gpt-6.9-sol", "max", 95), score("gpt-6.10-sol", "max", nil),
                            score("gpt-6.10-sol", "high", 90), score("gpt-6-terra", "max", 50),
                            score("gpt-6-luna", "max", 55)]
        precondition(aaTable.aaModels.map(\.id) == ["gpt-6-luna", "gpt-6-terra", "gpt-6.10-sol"])
        aaTable.aaScores = [score("gpt-6-terra", "max", 50), score("gpt-6-luna", "max", 50)]
        precondition(aaTable.aaModels.map(\.id) == ["gpt-6-terra", "gpt-6-luna", "gpt-6.10-sol"])
        aaTable.catalog! += ["gpt-5-sol", "gpt-5-terra", "gpt-5-luna"].map {
            .init(id: $0, displayName: $0, reasoningEfforts: ["max"], serviceTiers: [])
        }
        aaTable.aaScores! += [score("gpt-6.9-sol", "high", 99), score("gpt-5-sol", "max", 60),
                              score("gpt-5-terra", "max", 90), score("gpt-5-luna", "max", 60)]
        precondition(aaTable.creditModels.map(\.id) == [
            "gpt-6-terra", "gpt-6-luna", "gpt-6.10-sol",
            "gpt-5-terra", "gpt-5-sol", "gpt-5-luna", "gpt-6.9-sol"
        ])
        let now = ISO8601DateFormatter().date(from: "2026-11-02T08:00:00Z")!
        let cacheData = Data(#"{"fetched_at":"2026-11-02T08:00:00.000Z","models":[{"slug":"gpt-6.1-sol","visibility":"list"},{"slug":"gpt-hidden","visibility":"hide"},{"slug":"gpt-cache-only","visibility":"list"}]}"#.utf8)
        var staleCatalog = base
        staleCatalog.catalog! += [
            .init(id: "gpt-5.5", displayName: "GPT-5.5", reasoningEfforts: ["high"], serviceTiers: ["priority"]),
            .init(id: "gpt-hidden", displayName: "Hidden", reasoningEfforts: ["high"], serviceTiers: ["priority"])
        ]
        staleCatalog.aaScores = [score("gpt-5.5", "high", 99), score("gpt-6.1-sol", "high", 50)]
        staleCatalog.catalogUpdatedAt = now.addingTimeInterval(-60)
        let reconciled = CodexConfigurationRefresh.reconcileCatalog(staleCatalog.catalog!, cacheData: cacheData,
            newerThan: staleCatalog.catalogUpdatedAt!, now: now)
        precondition(reconciled == [base.catalog![0]])
        for unusableCache in [nil, Data("{}".utf8), Data(#"{"fetched_at":"2026-11-02T08:00:00Z","models":[]}"#.utf8)] as [Data?] {
            precondition(CodexConfigurationRefresh.reconcileCatalog(staleCatalog.catalog!, cacheData: unusableCache,
                newerThan: .distantPast, now: now) == staleCatalog.catalog)
        }
        precondition(CodexConfigurationRefresh.reconcileCatalog(staleCatalog.catalog!, cacheData: cacheData,
            newerThan: now.addingTimeInterval(1), now: now) == staleCatalog.catalog)
        precondition(CodexConfigurationRefresh.reconcileCatalog(staleCatalog.catalog!, cacheData: cacheData,
            newerThan: .distantPast, now: now.addingTimeInterval(-1)) == staleCatalog.catalog)
        let updated = try CodexConfigurationRefresh.applyingPricing(fixture, to: base, now: now)
        precondition(updated.rate(for: "gpt-6.1-terra")?.cachedInput == 1.25)
        precondition(updated.fastPolicy(for: "gpt-6.1-sol")?.includedSubscription == 2.5)
        precondition(updated.fastPolicy(for: "gpt-6.1-sol")?.purchasedCredits == 2)
        precondition(!updated.models.contains { ["daybreak-blue", "daybreak-red", "gpt-rosalind-research"].contains($0.id) })
        precondition(updated.fastModels.map(\.id) == ["gpt-6.1-sol", "gpt-fixture"])
        precondition(!updated.fastPolicies.contains { $0.family == "daybreak-blue" })
        let grouped = try String(contentsOf: root.appendingPathComponent("Tests/ConfigurationChecks/pricing-grouped.md"), encoding: .utf8)
        let groupedNow = ISO8601DateFormatter().date(from: "2026-11-19T08:00:00Z")!
        var newCatalog = base
        newCatalog.catalog! += ["gpt-6.2-astra", "gpt-6.2-sol"].map {
            .init(id: $0, displayName: $0, reasoningEfforts: ["max"], serviceTiers: ["priority"])
        }
        let groupedUpdate = try CodexConfigurationRefresh.applyingPricing(grouped, to: newCatalog, now: groupedNow)
        precondition(groupedUpdate.rate(for: "gpt-6.2-astra") == .init(input: 200, cachedInput: 10, output: 1000))
        precondition(groupedUpdate.rate(for: "gpt-6.2-sol") == .init(input: 50, cachedInput: 2.5, output: 250))
        for model in ["gpt-6.2-astra", "gpt-6.2-sol"] {
            precondition(groupedUpdate.fastPolicy(for: model)?.includedSubscription == 2)
            precondition(groupedUpdate.fastPolicy(for: model)?.purchasedCredits == 2)
            precondition(groupedUpdate.ultrafastPolicy(for: model)?.includedSubscription == 6)
        }
        precondition(groupedUpdate.fastPolicy(for: "gpt-6.1-sol")?.includedSubscription == 2.5)
        precondition(groupedUpdate.fastPolicy(for: "gpt-6.1-sol")?.purchasedCredits == 2)
        precondition(groupedUpdate.fastPolicy(for: "gpt-6.1-terra")?.verifiedOn == base.fastPolicy(for: "gpt-6.1-terra")?.verifiedOn)
        let indented = grouped.replacingOccurrences(of: "\n| GPT-6.1 Sol<br", with: "\n | GPT-6.1 Sol<br")
        let indentedUpdate = try CodexConfigurationRefresh.applyingPricing(indented, to: newCatalog, now: groupedNow)
        precondition(indentedUpdate.fastPolicy(for: "gpt-6.1-sol")?.verifiedOn == groupedUpdate.revision)
        let splitRows = grouped.replacingOccurrences(of: "| GPT-6.2 Astra<br />GPT-6.2 Sol | 2x | 2x |",
                                                    with: "| GPT-6.2 Astra | 2x | 2x |\n| GPT-6.2 Sol | 2x | 2x |")
        let mixedPipes = splitRows.replacingOccurrences(of: "\n| GPT-6.2 Sol |", with: "\n GPT-6.2 Sol |")
        func withoutOuterPipes(_ page: String) -> String {
            page.replacingOccurrences(of: #"(?m)^\|\h*|\h*\|$"#, with: "", options: .regularExpression)
        }
        for page in [splitRows, mixedPipes, withoutOuterPipes(splitRows)] {
            let refreshed = try CodexConfigurationRefresh.applyingPricing(page, to: newCatalog, now: groupedNow)
            precondition(refreshed.fastPolicy(for: "gpt-6.2-sol")?.purchasedCredits == 2)
            precondition(refreshed.fastPolicy(for: "gpt-6.1-sol")?.verifiedOn == refreshed.revision)
            CodexCreditConfiguration.activate(refreshed)
            precondition(CodexCreditRateCard.credits(model: "gpt-6.2-sol", serviceTier: "fast",
                inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0) == 100)
            precondition(CodexCreditRateCard.credits(model: "openai/gpt-6.2-sol-2026-11-18", serviceTier: "ultrafast",
                inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0) == 300)
        }
        CodexCreditConfiguration.activate(base)
        let markdownHeadings = grouped
            .replacingOccurrences(of: "\nFast\n", with: "\n### Fast\n")
            .replacingOccurrences(of: "\nUltrafast\n", with: "\n### Ultrafast ###\n")
            .replacingOccurrences(of: "| 6x |", with: "| 7x |")
        let headingUpdate = try CodexConfigurationRefresh.applyingPricing(markdownHeadings, to: newCatalog, now: groupedNow)
        precondition(headingUpdate.fastPolicy(for: "gpt-6.2-sol")?.includedSubscription == 2)
        precondition(headingUpdate.ultrafastPolicy(for: "gpt-6.2-sol")?.includedSubscription == 7)
        let borderlessLegacy = try CodexConfigurationRefresh.applyingPricing(withoutOuterPipes(fixture), to: base, now: now)
        precondition(borderlessLegacy.fastPolicy(for: "gpt-6.1-sol")?.verifiedOn == "2026-11-02")
        let unrecognizedUltrafastTable = grouped.replacingOccurrences(of: "\nUltrafast\n", with: "\nUnknown speed\n")
        let ultrafastRow = "| GPT-6.1 Sol | 9x | 6x |"
        let completeUltrafast = grouped.replacingOccurrences(of: "\n\n<table>", with: "\n\(ultrafastRow)\n\n<table>")
        let completeUpdate = try CodexConfigurationRefresh.applyingPricing(completeUltrafast, to: newCatalog, now: groupedNow)
        precondition(completeUpdate.ultrafastPolicy(for: "gpt-6.1-sol")?.includedSubscription == 9)
        let interruptedUltrafast = completeUltrafast.replacingOccurrences(of: "\n\(ultrafastRow)", with: "\n\n\(ultrafastRow)")
        let interruptedFast = grouped.replacingOccurrences(of: "\n| GPT-6.1 Sol<br", with: "\n\n| GPT-6.1 Sol<br")
        let missingTokenRateCell = grouped.replacingOccurrences(
            of: "<td>2.5 credits</td><td>250 credits</td>", with: "<td>250 credits</td>"
        )
        let withTokenRateNote = grouped.replacingOccurrences(
            of: "</tbody>", with: #"<tr><td colspan="4" style="text-align:center">Rate card note.</td></tr></tbody>"#
        )
        let noteUpdate = try CodexConfigurationRefresh.applyingPricing(withTokenRateNote, to: newCatalog, now: groupedNow)
        precondition(noteUpdate.models == groupedUpdate.models)
        for invalid in [grouped.replacingOccurrences(of: "Fast\n", with: "Unknown\n"),
                        unrecognizedUltrafastTable,
                        interruptedUltrafast,
                        withoutOuterPipes(interruptedUltrafast),
                        interruptedFast,
                        missingTokenRateCell,
                        grouped.replacingOccurrences(of: "GPT-6.", with: "Unrelated-"),
                        grouped.replacingOccurrences(of: "6x | 3x", with: "unknown | 3x"),
                        grouped.replacingOccurrences(of: "2.5x |", with: "unknown |"),
                        mixedPipes.replacingOccurrences(of: "GPT-6.2 Sol | 2x | 2x |", with: "GPT-6.2 Sol | | 2x |"),
                        mixedPipes.replacingOccurrences(of: "GPT-6.2 Sol | 2x | 2x |", with: "GPT-6.2 Sol"),
                        grouped.replacingOccurrences(of: "GPT-6.1 Sol<br", with: "GPT-6.2 Sol<br")] {
            do { _ = try CodexConfigurationRefresh.applyingPricing(invalid, to: newCatalog); fatalError("Invalid speed table accepted") }
            catch {}
        }
        let future = try CodexConfigurationRefresh.applyingPricing(fixture.replacingOccurrences(of: "Daybreak Blue", with: "GPT-Fixture"), to: base, now: now)
        precondition(future.rate(for: "gpt-fixture")?.input == 100 && future.fastPolicy(for: "gpt-fixture")?.includedSubscription == 2.5)
        var retired = future
        retired.catalog = []
        retired = retired.retainingCodexModels()
        precondition(retired.rate(for: "gpt-fixture")?.input == 100 && retired.fastModels.isEmpty)
        precondition(updated.rate(for: "gpt-5.3-codex") == base.rate(for: "gpt-5.3-codex"))
        precondition(updated.subscriptionCredits(for: "plus") == 1250)
        precondition(updated.subscriptionCredits(for: "prolite") == 12500)
        precondition(updated.subscriptionCredits(for: "pro") == 25000)
        precondition(updated.subscriptionCredits(for: "promax") == 62500)
        precondition(updated.subscriptionEstimates?.count == 1)
        var manual = updated
        manual.subscriptionEstimates?["plus"] = .init(credits: 1500, basis: "Manual reference")
        let repriced = try CodexConfigurationRefresh.applyingPricing(fixture, to: manual, now: now)
        precondition(repriced.subscriptionCredits(for: "prolite") == 15000)
        precondition(repriced.subscriptionCredits(for: "pro") == 30000)
        precondition(repriced.subscriptionCredits(for: "promax") == 75000)
        CodexCreditConfiguration.activate(repriced)
        precondition(CodexDisplayPolicy.remainingCredits(plan: .promax, remainingPercent: 50) == 37500)
        CodexCreditConfiguration.activate(base)
        for bad in [0.0, -1.0, Double.greatestFiniteMagnitude] {
            var invalid = base
            invalid.subscriptionMultipliers?["pro"] = bad
            do { _ = try CodexCreditConfiguration.decode(JSONEncoder().encode(invalid)); fatalError("Invalid multiplier accepted") }
            catch {}
        }
        for invalid in ["<html>Sign in</html>", fixture.replacingOccurrences(of: "2.5x", with: "unknown"),
                        fixture.replacingOccurrences(of: "25 credits", with: "-1 credits"),
                        fixture.replacingOccurrences(of: "Credits per 1M tokens", with: "USD per 1M tokens")] {
            do { _ = try CodexConfigurationRefresh.applyingPricing(invalid, to: base); fatalError("Invalid source accepted") }
            catch {}
        }
        // Previously saved speed fields are ignored without discarding rates or AA scores.
        var legacy = base
        legacy.aaScores = aaScores
        legacy.aaUpdatedAt = now
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        legacyJSON["fastSpeeds"] = [["family": "gpt-5.6", "multiplier": 1.5]]
        legacyJSON["speedUpdatedAt"] = now.timeIntervalSinceReferenceDate
        let compatible = try CodexCreditConfiguration.decode(JSONSerialization.data(withJSONObject: legacyJSON))
        precondition(compatible.aaScores == aaScores && compatible.rate(for: "gpt-6.1-sol") == base.rate(for: "gpt-6.1-sol"))
        let resaved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(compatible)) as! [String: Any]
        precondition(resaved["fastSpeeds"] == nil && resaved["speedUpdatedAt"] == nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("island-configuration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder); CodexCreditConfiguration.activate(base) }
        let file = folder.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var beforeUltrafast = newCatalog
        beforeUltrafast.ultrafastPolicies = nil
        beforeUltrafast.models.removeAll { $0.id.hasPrefix("gpt-6.2-") }
        beforeUltrafast.fastPolicies.removeAll { $0.family.hasPrefix("gpt-6.2-") }
        beforeUltrafast.subscriptionEstimates?["plus"] = .init(credits: 1500, basis: "Manual reference")
        beforeUltrafast.pricingUpdatedAt = groupedNow
        beforeUltrafast.catalogUpdatedAt = groupedNow
        beforeUltrafast.aaUpdatedAt = groupedNow
        let upgradeFile = folder.appendingPathComponent("before-ultrafast.json")
        try JSONEncoder().encode(beforeUltrafast).write(to: upgradeFile)
        let upgraded = CodexConfigurationService(fileURL: upgradeFile, readModelCache: { nil }, clock: { groupedNow })
        precondition(upgraded.configuration?.rate(for: "gpt-6.2-sol")?.input == 50)
        precondition(upgraded.configuration?.ultrafastPolicy(for: "gpt-6.2-sol")?.includedSubscription == 6)
        precondition(upgraded.configuration?.subscriptionCredits(for: "plus") == 1500)
        for (model, credits) in [("gpt-6.2-sol", 100.0), ("gpt-6.2-astra", 400.0)] {
            precondition(CodexCreditRateCard.credits(model: model, serviceTier: "fast",
                inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0) == credits)
        }
        upgraded.start()
        upgraded.stop()
        var partialUpgrade = try CodexCreditConfiguration.decode(Data(contentsOf: upgradeFile))
        precondition(partialUpgrade.fastPolicy(for: "gpt-6.2-sol")?.includedSubscription == 2)
        partialUpgrade.fastPolicies.removeAll { $0.family == "gpt-6.2-sol" }
        try JSONEncoder().encode(partialUpgrade).write(to: upgradeFile)
        let repaired = CodexConfigurationService(fileURL: upgradeFile, readModelCache: { nil }, clock: { groupedNow })
        precondition(repaired.configuration?.fastPolicy(for: "gpt-6.2-sol")?.includedSubscription == 2)
        precondition(repaired.configuration?.ultrafastPolicies == partialUpgrade.ultrafastPolicies)

        var equalCountUpgrade = try CodexCreditConfiguration.decode(Data(contentsOf: upgradeFile))
        equalCountUpgrade.fastPolicies.append(base.fastPolicy(for: "gpt-6.2-sol")!)
        let lunaRate = equalCountUpgrade.rate(for: "gpt-6-luna")!
        equalCountUpgrade.models.removeAll { $0.id == "gpt-6-luna" }
        equalCountUpgrade.models.append(.init(id: "gpt-unlisted-fixture", verifiedOn: "2026-11-19", rate: lunaRate))
        equalCountUpgrade.fastPolicies.removeAll { $0.family == "gpt-6-luna" }
        equalCountUpgrade.fastPolicies.append(.init(family: "gpt-unlisted-fixture", verifiedOn: "2026-11-19",
                                                     includedSubscription: 2.5, purchasedCredits: 2))
        try JSONEncoder().encode(equalCountUpgrade).write(to: upgradeFile)
        let equalCountService = CodexConfigurationService(fileURL: upgradeFile, readModelCache: { nil }, clock: { groupedNow })
        equalCountService.start()
        equalCountService.stop()
        let equalCountSaved = try CodexCreditConfiguration.decode(Data(contentsOf: upgradeFile))
        precondition(equalCountSaved.models.count == equalCountUpgrade.models.count)
        precondition(equalCountSaved.fastPolicies.count == equalCountUpgrade.fastPolicies.count)
        precondition(equalCountSaved.rate(for: "gpt-6-luna") == lunaRate)
        precondition(equalCountSaved.fastPolicy(for: "gpt-6-luna") != nil)
        precondition(equalCountSaved.rate(for: "gpt-unlisted-fixture") == nil)

        // Hidden Fast multipliers still refresh and survive a restart.
        let policyFile = folder.appendingPathComponent("fast-policy.json")
        let policyService = CodexConfigurationService(fileURL: policyFile, initialConfiguration: base,
            fetchPricing: { fixture.replacingOccurrences(of: "2.5x", with: "3.5x").replacingOccurrences(of: "2x", with: "3x") },
            listModels: { base.catalog! }, fetchAA: { _ in aaScores }, readModelCache: { nil }, clock: { now })
        policyService.updateNow()
        try await wait(policyService)
        precondition(policyService.error == nil)
        let policyReload = CodexConfigurationService(fileURL: policyFile, readModelCache: { nil })
        precondition(policyReload.configuration?.fastPolicy(for: "gpt-6.1-sol")?.includedSubscription == 3.5)
        precondition(policyReload.configuration?.fastPolicy(for: "gpt-6.1-sol")?.purchasedCredits == 3)
        precondition(policyReload.configuration?.aaScores == aaScores)
        policyService.stop()
        policyReload.stop()
        let migratedFile = folder.appendingPathComponent("stale-catalog.json")
        try JSONEncoder().encode(staleCatalog).write(to: migratedFile)
        let migratedCatalog = CodexConfigurationService(fileURL: migratedFile,
            fetchPricing: { fixture }, listModels: { reconciled }, fetchAA: { _ in throw CodexConfigurationRefresh.RefreshError.invalidAA },
            readModelCache: { cacheData }, clock: { now })
        precondition(migratedCatalog.configuration?.creditModels.map(\.id) == ["gpt-6.1-sol"])
        precondition(migratedCatalog.configuration?.aaModels.map(\.id) == ["gpt-6.1-sol"])
        precondition(migratedCatalog.configuration?.fastModels.map(\.id) == ["gpt-6.1-sol"])
        precondition(migratedCatalog.configuration?.rate(for: "gpt-5.5") == base.rate(for: "gpt-5.5"))
        migratedCatalog.start()
        try await wait(migratedCatalog)
        migratedCatalog.stop()
        let migratedReadback = try CodexCreditConfiguration.decode(Data(contentsOf: migratedFile))
        precondition(migratedReadback.catalog == reconciled && migratedReadback.aaScores == staleCatalog.aaScores)
        precondition(migratedReadback.rate(for: "gpt-5.5") == base.rate(for: "gpt-5.5"))
        let catalog = [CodexCreditConfiguration.CatalogModel(id: "gpt-fixture", displayName: "Fixture", reasoningEfforts: ["high"], serviceTiers: ["fast"])]
        var requests = 0
        var failPricing = false
        var failAA = false
        var pricingPage = fixture
        var currentTime = now
        let service = CodexConfigurationService(fileURL: file, initialConfiguration: base,
            fetchPricing: {
                requests += 1
                if failPricing { throw CodexConfigurationRefresh.RefreshError.invalidSource }
                return pricingPage
            },
            listModels: { catalog }, fetchAA: { _ in if failAA { throw CodexConfigurationRefresh.RefreshError.invalidAA }; return aaScores }, clock: { currentTime })
        precondition(service.intervalDays == 7 && service.nextUpdate == nil)
        service.start()
        try await wait(service)
        precondition(requests == 1 && service.error == nil)
        let persisted = try CodexCreditConfiguration.decode(Data(contentsOf: file))
        precondition(persisted.aaScores == aaScores && persisted.aaUpdatedAt == now)
        precondition(persisted.catalog == catalog && persisted.catalogUpdatedAt == now && persisted.pricingUpdatedAt == now)
        precondition(service.nextUpdate == now.addingTimeInterval(7 * 86400))
        service.checkIfDue()
        precondition(!service.isRefreshing)
        currentTime = now.addingTimeInterval(2 * 86400)
        failPricing = true
        failAA = true
        service.setIntervalDays(1)
        try await wait(service)
        precondition(requests == 2 && service.error != nil)
        precondition(service.configuration?.aaScores == aaScores && service.configuration?.aaUpdatedAt == now)
        precondition(service.configuration?.pricingUpdatedAt == now && service.configuration?.catalogUpdatedAt == currentTime)
        precondition(service.configuration?.rate(for: "gpt-6.1-sol") == persisted.rate(for: "gpt-6.1-sol"))
        service.checkIfDue()
        precondition(!service.isRefreshing, "Failed updates should back off")
        failPricing = false
        failAA = false
        pricingPage = interruptedUltrafast
        service.updateNow()
        try await wait(service)
        precondition(requests == 3 && service.error == CodexConfigurationRefresh.RefreshError.invalidSource.localizedDescription)
        let afterInvalidTable = try CodexCreditConfiguration.decode(Data(contentsOf: file))
        precondition(afterInvalidTable.pricingUpdatedAt == persisted.pricingUpdatedAt)
        precondition(afterInvalidTable.models == persisted.models && afterInvalidTable.fastPolicies == persisted.fastPolicies)
        precondition(afterInvalidTable.ultrafastPolicies == persisted.ultrafastPolicies)
        precondition(service.nextUpdate == currentTime.addingTimeInterval(3600))
        service.stop()
        let earlyRefreshFile = folder.appendingPathComponent("early-refresh.json")
        var retryClock = now.addingTimeInterval(60)
        var retryPage = missingTokenRateCell
        var retryRequests = 0
        let earlyRefresh = CodexConfigurationService(fileURL: earlyRefreshFile, initialConfiguration: persisted,
            fetchPricing: { retryRequests += 1; return retryPage }, listModels: { catalog },
            fetchAA: { _ in aaScores }, readModelCache: { nil }, clock: { retryClock })
        earlyRefresh.updateNow()
        try await wait(earlyRefresh)
        precondition(retryRequests == 1 && earlyRefresh.error != nil)
        let afterPartialPricing = try CodexCreditConfiguration.decode(Data(contentsOf: earlyRefreshFile))
        precondition(afterPartialPricing.models == persisted.models && afterPartialPricing.pricingUpdatedAt == now)
        let retryAt = retryClock.addingTimeInterval(3600)
        precondition(earlyRefresh.nextUpdate == retryAt)
        retryClock = retryAt.addingTimeInterval(-1)
        earlyRefresh.checkIfDue()
        precondition(!earlyRefresh.isRefreshing && retryRequests == 1)
        retryPage = fixture
        retryClock = retryAt
        earlyRefresh.checkIfDue()
        try await wait(earlyRefresh)
        precondition(retryRequests == 2 && earlyRefresh.error == nil)
        precondition(earlyRefresh.configuration?.pricingUpdatedAt == retryAt)
        earlyRefresh.stop()
        let restored = CodexConfigurationService(fileURL: file, initialConfiguration: base, readModelCache: { nil })
        precondition(restored.intervalDays == 1 && restored.configuration?.catalog == catalog)
        restored.stop()
        // Migrate the previous release's price-table-only entries without changing user estimates.
        var polluted = persisted
        polluted.models.append(.init(id: "daybreak-blue", verifiedOn: "2026-11-02", rate: .init(input: 100, cachedInput: 10, output: 500)))
        polluted.fastPolicies.append(.init(family: "daybreak-blue", verifiedOn: "2026-11-02", includedSubscription: 2.5, purchasedCredits: 2))
        polluted.subscriptionEstimates?["plus"] = .init(credits: 3456, basis: "User estimate")
        polluted.subscriptionMultipliers = nil
        polluted.subscriptionEstimates?["prolite"] = .init(credits: 10000, basis: "Legacy")
        polluted.subscriptionEstimates?["pro"] = .init(credits: 20000, basis: "Legacy")
        polluted.updateIntervalDays = 14
        try JSONEncoder().encode(polluted).write(to: file)
        let migrated = CodexConfigurationService(fileURL: file, initialConfiguration: base, clock: { currentTime })
        precondition(migrated.configuration?.rate(for: "daybreak-blue") == nil)
        migrated.start()
        precondition(!migrated.isRefreshing)
        migrated.stop()
        let cleaned = try CodexCreditConfiguration.decode(Data(contentsOf: file))
        precondition(cleaned.fastPolicy(for: "daybreak-blue") == nil)
        precondition(cleaned.subscriptionEstimates?["plus"]?.credits == 3456 && cleaned.updateIntervalDays == 14)
        precondition(cleaned.subscriptionEstimates?.count == 1)
        precondition(cleaned.subscriptionCredits(for: "prolite") == 34560)
        precondition(cleaned.subscriptionCredits(for: "pro") == 69120)
        precondition(cleaned.subscriptionCredits(for: "promax") == 172800)
        let reloaded = CodexConfigurationService(fileURL: file, initialConfiguration: base, readModelCache: { nil })
        precondition(reloaded.configuration?.subscriptionCredits(for: "promax") == 172800)
        reloaded.stop()

        // Exercise the UI's save action, including edits while a network refresh is suspended.
        let editFile = folder.appendingPathComponent("editable.json")
        var fetchContinuation: CheckedContinuation<String, Error>?
        let editing = CodexConfigurationService(fileURL: editFile, initialConfiguration: base,
            fetchPricing: { try await withCheckedThrowingContinuation { fetchContinuation = $0 } },
            listModels: { catalog }, fetchAA: { _ in aaScores }, clock: { now })
        var updates = 0
        editing.onUpdate = { updates += 1 }
        try editing.setPlusCredits(1500)
        precondition(updates == 1)
        let savedEdit = try Data(contentsOf: editFile)
        let editedCard = try CodexCreditConfiguration.decode(savedEdit)
        precondition(editedCard.subscriptionCredits(for: "prolite") == 15000)
        precondition(editedCard.subscriptionCredits(for: "pro") == 30000)
        precondition(editedCard.subscriptionCredits(for: "promax") == 75000)
        precondition(CodexDisplayPolicy.remainingCredits(plan: .promax, remainingPercent: 50) == 37500)
        for invalid in [0.0, -1.0, Double.nan, .infinity, .greatestFiniteMagnitude] {
            do { try editing.setPlusCredits(invalid); fatalError("Invalid Plus edit accepted") }
            catch {}
            let unchanged = try Data(contentsOf: editFile)
            precondition(unchanged == savedEdit && updates == 1)
        }
        editing.updateNow()
        for _ in 0..<1000 {
            if fetchContinuation != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard let fetchContinuation else { fatalError("Refresh did not start") }
        try editing.setPlusCredits(1750)
        fetchContinuation.resume(returning: fixture)
        try await wait(editing)
        precondition(editing.configuration?.subscriptionCredits(for: "promax") == 87500)
        let editedRestart = CodexConfigurationService(fileURL: editFile, initialConfiguration: base, readModelCache: { nil })
        precondition(editedRestart.configuration?.subscriptionCredits(for: "plus") == 1750)
        editing.stop()
        editedRestart.stop()

        try Data("invalid".utf8).write(to: file)
        let corrupt = CodexConfigurationService(fileURL: file, initialConfiguration: base, readModelCache: { nil })
        precondition(corrupt.error != nil && corrupt.configuration?.revision == base.revision)
        // A storage failure cannot activate a new configuration or destroy existing data.
        let blocked = CodexConfigurationService(fileURL: file.appendingPathComponent("child.json"), initialConfiguration: base,
                                                fetchPricing: { fixture }, listModels: { catalog }, fetchAA: { _ in aaScores }, clock: { now })
        let generationBeforeFailedSave = CodexCreditConfiguration.generation
        do { try blocked.setPlusCredits(2000); fatalError("Failed write reported as saved") }
        catch {}
        precondition(blocked.configuration?.subscriptionCredits(for: "plus") == 1250)
        precondition(CodexCreditConfiguration.generation == generationBeforeFailedSave)
        blocked.updateNow()
        try await wait(blocked)
        precondition(blocked.error != nil && blocked.configuration?.pricingUpdatedAt == nil)
        let untouched = try String(contentsOf: file, encoding: .utf8)
        precondition(untouched == "invalid")
        if CommandLine.arguments.contains("--live-catalog") {
            let models = try await CodexConfigurationRefresh.listModels()
            let local = CodexConfigurationService()
            var configuration = local.configuration!
            configuration.catalog = models
            precondition(Set(configuration.creditModels.map(\.id)) == Set(models.map(\.id)))
            print("Live selectable catalog: " + models.map(\.id).joined(separator: ", "))
            print("Migrated local catalog: " + (local.configuration?.catalog ?? []).map(\.id).joined(separator: ", "))
            if let index = CommandLine.arguments.firstIndex(of: "--output"), CommandLine.arguments.indices.contains(index + 1) {
                try JSONEncoder().encode(configuration).write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
            }
        }
        if CommandLine.arguments.contains("--live") {
            let text = try await CodexConfigurationRefresh.fetchPricing()
            let models = try await CodexConfigurationRefresh.listModels()
            var liveBase = base
            liveBase.catalog = models
            var live = try CodexConfigurationRefresh.applyingPricing(text, to: liveBase)
            live.aaScores = try await CodexArtificialAnalysis.fetchScores(models)
            live.aaUpdatedAt = Date()
            _ = try CodexCreditConfiguration.decode(JSONEncoder().encode(live))
            print("Live AA: \(live.aaScores?.count ?? 0) effort scores")
            for model in models {
                let entries = live.aaScores?.filter { $0.model == model.id } ?? []
                print(model.id + ": " + entries.map { $0.effort + "=" + ($0.score.map { String(format: "%.1f", $0) } ?? "nil") }.joined(separator: ", "))
            }
            if let outputIndex = CommandLine.arguments.firstIndex(of: "--output"), CommandLine.arguments.indices.contains(outputIndex + 1) {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(live).write(to: URL(fileURLWithPath: CommandLine.arguments[outputIndex + 1]), options: .atomic)
            }
            precondition(live.fastModels.allSatisfy { models.contains($0) && $0.supportsFast })
            print("Visible Fast models: " + live.fastModels.map(\.id).joined(separator: ", "))
            print("Live official pricing: \(live.models.count) rates; local Codex catalog: \(models.count) models; no inference calls")
        }
        print("Configuration checks passed")
    }
    @MainActor static func wait(_ service: CodexConfigurationService) async throws {
        for _ in 0..<1000 {
            if !service.isRefreshing { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        fatalError("Update timeout")
    }
}
