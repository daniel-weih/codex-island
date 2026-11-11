import AppKit
import Combine

@MainActor
final class CodexConfigurationService: ObservableObject {
    @Published private(set) var configuration: CodexCreditConfiguration?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    var onUpdate: (() -> Void)?
    let fileURL: URL
    private let persistenceEnabled: Bool
    private let fetchPricing: () async throws -> String
    private let listModels: () async throws -> [CodexCreditConfiguration.CatalogModel]
    private let fetchAA: ([CodexCreditConfiguration.CatalogModel]) async throws -> [CodexCreditConfiguration.AAScore]
    private let clock: () -> Date
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var needsScopeMigration = false
    private var retryAfter: Date?

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexIsland", isDirectory: true).appendingPathComponent("CodexConfiguration.json")
    }
    var intervalDays: Int { configuration?.updateIntervalDays ?? 7 }
    var nextUpdate: Date? {
        guard let pricing = configuration?.pricingUpdatedAt, let catalog = configuration?.catalogUpdatedAt,
              let aa = configuration?.aaUpdatedAt else { return nil }
        return min(pricing, catalog, aa).addingTimeInterval(Double(intervalDays) * 86400)
    }

    init(persistenceEnabled: Bool = true, fileURL: URL = CodexConfigurationService.defaultFileURL,
         initialConfiguration: CodexCreditConfiguration? = CodexCreditConfiguration.bundled,
         fetchPricing: @escaping () async throws -> String = CodexConfigurationRefresh.fetchPricing,
         listModels: @escaping () async throws -> [CodexCreditConfiguration.CatalogModel] = CodexConfigurationRefresh.listModels,
         fetchAA: @escaping ([CodexCreditConfiguration.CatalogModel]) async throws -> [CodexCreditConfiguration.AAScore] = CodexArtificialAnalysis.fetchScores,
         readModelCache: () -> Data? = CodexConfigurationRefresh.readModelCache,
         clock: @escaping () -> Date = Date.init) {
        self.persistenceEnabled = persistenceEnabled
        self.fileURL = fileURL
        self.fetchPricing = fetchPricing
        self.listModels = listModels
        self.fetchAA = fetchAA
        self.clock = clock
        configuration = initialConfiguration
        if persistenceEnabled {
            var loadedConfiguration = false
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    configuration = try CodexCreditConfiguration.decode(Data(contentsOf: fileURL))
                    loadedConfiguration = true
                }
                catch { self.error = "本地配置无效，使用内置配置 / Invalid local configuration; using bundled defaults" }
            }
            if let original = configuration {
                var scoped = original.migratingSubscriptionEstimates().retainingCodexModels()
                if loadedConfiguration, let catalog = scoped.catalog, let updatedAt = scoped.catalogUpdatedAt {
                    scoped.catalog = CodexConfigurationRefresh.reconcileCatalog(catalog, cacheData: readModelCache(),
                                                                               newerThan: updatedAt, now: clock())
                }
                needsScopeMigration = loadedConfiguration && (
                    scoped.catalog != original.catalog
                    || scoped.models.count != original.models.count
                    || scoped.fastPolicies.count != original.fastPolicies.count
                    || scoped.knownCodexModelIDs != original.knownCodexModelIDs
                    || scoped.subscriptionMultipliers != original.subscriptionMultipliers
                    || scoped.subscriptionEstimates?.count != original.subscriptionEstimates?.count)
                configuration = scoped
                CodexCreditConfiguration.activate(scoped)
            }
        }
    }

    func start() {
        guard timer == nil else { return }
        if needsScopeMigration || !FileManager.default.fileExists(atPath: fileURL.path), let configuration {
            do { try save(configuration); needsScopeMigration = false } catch { self.error = error.localizedDescription }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        checkIfDue()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        task?.cancel(); task = nil
        isRefreshing = false
    }
    func setIntervalDays(_ days: Int) {
        guard (1...365).contains(days), var updated = configuration else { return }
        updated.updateIntervalDays = days
        do { try save(updated); checkIfDue() } catch { self.error = error.localizedDescription }
    }

    enum EditError: Error {
        case invalidPlusCredits, unavailable
    }

    /// The same atomic save updates both the configuration page and dashboard estimates.
    func setPlusCredits(_ credits: Double) throws {
        guard credits.isFinite, credits > 0 else { throw EditError.invalidPlusCredits }
        guard var updated = configuration?.migratingSubscriptionEstimates() else { throw EditError.unavailable }
        guard (updated.subscriptionMultipliers ?? [:]).values.allSatisfy({
            let allowance = credits * $0
            return allowance.isFinite && allowance > 0
        }) else { throw EditError.invalidPlusCredits }
        let basis = updated.subscriptionEstimates?["plus"]?.basis
            ?? "User-configurable project estimate; not an official account balance."
        if updated.subscriptionEstimates == nil { updated.subscriptionEstimates = [:] }
        updated.subscriptionEstimates?["plus"] = .init(credits: credits, basis: basis)
        try save(updated)
    }

    func checkIfDue() {
        guard !isRefreshing, retryAfter.map({ $0 <= clock() }) ?? true,
              nextUpdate.map({ $0 <= clock() }) ?? true else { return }
        updateNow()
    }
    func updateNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            var pricing: String?
            var models: [CodexCreditConfiguration.CatalogModel]?
            var aa: [CodexCreditConfiguration.AAScore]?
            // Independent failures must not prevent the other source from refreshing.
            do { pricing = try await fetchPricing() } catch { failures.append(error.localizedDescription) }
            guard !Task.isCancelled else { return }
            do { models = try await listModels() } catch { failures.append(error.localizedDescription) }
            guard !Task.isCancelled else { return }
            do {
                guard let catalog = models ?? configuration?.catalog, !catalog.isEmpty else {
                    throw CodexConfigurationRefresh.RefreshError.invalidAA
                }
                aa = try await fetchAA(catalog)
            } catch { failures.append(CodexConfigurationRefresh.RefreshError.invalidAA.localizedDescription) }
            guard !Task.isCancelled else { return }
            if var updated = configuration {
                // Read the latest configuration after I/O, so interval edits made in flight survive.
                if let models {
                    var candidate = updated.retainingCodexModels()
                    candidate.catalog = models
                    candidate.catalogUpdatedAt = clock()
                    do { updated = try CodexCreditConfiguration.decode(JSONEncoder().encode(candidate)) }
                    catch { failures.append(CodexConfigurationRefresh.RefreshError.invalidCatalog.localizedDescription) }
                }
                if let pricing {
                    do { updated = try CodexConfigurationRefresh.applyingPricing(pricing, to: updated, now: clock()) }
                    catch { failures.append(error.localizedDescription) }
                }
                if let aa {
                    var candidate = updated
                    candidate.aaScores = aa
                    candidate.aaUpdatedAt = clock()
                    do { updated = try CodexCreditConfiguration.decode(JSONEncoder().encode(candidate)) }
                    catch { failures.append(CodexConfigurationRefresh.RefreshError.invalidAA.localizedDescription) }
                }
                do { try save(updated) } catch { failures.append(error.localizedDescription) }
            } else { failures.append("配置不可用 / Configuration unavailable") }
            error = failures.isEmpty ? nil : failures.joined(separator: "\n")
            retryAfter = failures.isEmpty ? nil : clock().addingTimeInterval(3600)
            isRefreshing = false
            task = nil
        }
    }
    private func save(_ proposed: CodexCreditConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(proposed.migratingSubscriptionEstimates().retainingCodexModels())
        let valid = try CodexCreditConfiguration.decode(data)
        if persistenceEnabled {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            CodexCreditConfiguration.activate(valid)
        }
        configuration = valid
        onUpdate?()
    }
}
