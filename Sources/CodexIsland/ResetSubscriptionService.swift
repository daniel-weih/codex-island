import AppKit
import Combine
import Foundation

@MainActor
final class ResetSubscriptionService: ObservableObject {
    typealias Fetch = (URL) async throws -> ResetSourceSnapshot
    typealias Analyze = (ResetSourceSnapshot, ResetSubscriptionSettings) async throws -> ResetAnalysisResult
    typealias ListModels = () async throws -> [ResetAnalysisModel]

    @Published private(set) var settings: ResetSubscriptionSettings
    @Published private(set) var phase: ResetSubscriptionPhase = .idle
    @Published private(set) var latest: ResetSubscriptionReport?
    @Published private(set) var history: [ResetSubscriptionReport] = []
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastAnalyzedAt: Date?
    @Published private(set) var nextCheckAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var models: [ResetAnalysisModel] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelError: String?
    @Published private(set) var usageRecords: [ResetUsageRecord] = []

    var isRefreshing: Bool { phase.isBusy }
    var onUsage: ((ResetUsageRecord) -> Void)?
    var onNewReport: ((ResetSubscriptionReport) -> Void)?

    private let fetch: Fetch
    private let analyze: Analyze
    private let listModels: ListModels
    private let analyzer: CodexResetAnalyzer?
    private let catalogAnalyzer: CodexResetAnalyzer?
    private let defaults: UserDefaults
    private let cacheURL: URL
    private let persistenceEnabled: Bool
    private let now: () -> Date
    private let modelCatalogScope: () -> String
    private var modelsScope: String
    private var modelCatalog: ModelCatalog?
    private var nextModelRetryAt: Date?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var checkTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var modelsGeneration: UInt64 = 0
    private var hasStarted = false
    private var consecutiveFailures = 0
    private var analyzedFingerprint: String?
    private var analyzedConfiguration: String?

    private static let settingsKey = "resetSubscription.settings.v1"
    static let historyLimit = 20
    static let usageLimit = 50_000
    static let usageRetention: TimeInterval = 30 * 24 * 3600
    static let modelCatalogLifetime: TimeInterval = 3600
    static let modelRetryDelay: TimeInterval = 60

    private struct ModelCatalog: Codable {
        var models: [ResetAnalysisModel]
        var updatedAt: Date
        var scope: String
    }

    private struct Cache: Codable {
        var schemaVersion = 1
        var sourceURL: String
        var latest: ResetSubscriptionReport?
        var history: [ResetSubscriptionReport]
        var usageRecords: [ResetUsageRecord]
        var lastCheckedAt: Date?
        var lastAnalyzedAt: Date?
        var nextCheckAt: Date?
        var analyzedFingerprint: String?
        var analyzedConfiguration: String?
        var modelCatalog: ModelCatalog?
    }

    init(
        settings: ResetSubscriptionSettings? = nil,
        persistenceEnabled: Bool = true,
        initialReport: ResetSubscriptionReport? = nil,
        initialModels: [ResetAnalysisModel] = [],
        fetch: Fetch? = nil,
        analyze: Analyze? = nil,
        listModels: ListModels? = nil,
        defaults: UserDefaults = .standard,
        cacheURL: URL? = nil,
        modelCatalogScope: (() -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.persistenceEnabled = persistenceEnabled
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexIsland/reset-subscription.json")
        self.now = now
        let scope = modelCatalogScope ?? { Self.currentModelCatalogScope() }
        self.modelCatalogScope = scope
        self.modelsScope = scope()
        let savedSettings = persistenceEnabled ? defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(ResetSubscriptionSettings.self, from: $0) } : nil
        let restoredSettings = (try? (settings ?? savedSettings ?? ResetSubscriptionSettings())
            .migratingLegacyDefaults().validated()) ?? ResetSubscriptionSettings()
        let intervalDefaultsChanged = settings == nil && savedSettings.map { $0.interval != restoredSettings.interval } == true
        self.settings = restoredSettings
        if persistenceEnabled, settings == nil, let savedSettings, savedSettings != restoredSettings {
            defaults.set(try? JSONEncoder().encode(restoredSettings), forKey: Self.settingsKey)
        }
        let analyzer = analyze == nil ? CodexResetAnalyzer() : nil
        let catalogAnalyzer = listModels == nil ? CodexResetAnalyzer() : nil
        self.analyzer = analyzer
        self.catalogAnalyzer = catalogAnalyzer
        self.fetch = fetch ?? { try await ResetSubscriptionSource.fetch(url: $0) }
        self.analyze = analyze ?? { try await analyzer!.analyze(snapshot: $0, settings: $1) }
        self.listModels = listModels ?? { try await catalogAnalyzer!.listModels() }
        if persistenceEnabled,
           let data = try? Data(contentsOf: self.cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.schemaVersion == 1 {
            usageRecords = Array(cache.usageRecords.filter { $0.recordedAt >= now().addingTimeInterval(-Self.usageRetention) }.prefix(Self.usageLimit))
            if let catalog = cache.modelCatalog, catalog.scope == modelsScope, !catalog.models.isEmpty {
                modelCatalog = catalog
                models = catalog.models
            }
            if cache.sourceURL == self.settings.urlString {
                latest = cache.latest
                history = Array(cache.history.prefix(Self.historyLimit))
                lastCheckedAt = cache.lastCheckedAt
                lastAnalyzedAt = cache.lastAnalyzedAt
                nextCheckAt = self.settings.enabled
                    ? (intervalDefaultsChanged
                        ? (cache.lastCheckedAt ?? now()).addingTimeInterval(self.settings.interval)
                        : cache.nextCheckAt)
                    : nil
                analyzedFingerprint = cache.analyzedFingerprint
                analyzedConfiguration = cache.analyzedConfiguration
            }
        }
        if !persistenceEnabled {
            latest = initialReport
            lastCheckedAt = initialReport?.fetchedAt
            lastAnalyzedAt = initialReport?.analyzedAt
            models = initialModels
        }
        analyzer?.onUsage = { [weak self] record in self?.recordUsage(record) }
        if intervalDefaultsChanged { persist() }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfDue() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAfterWake() }
        }
        checkIfDue()
        loadModels()
    }

    func stop() {
        hasStarted = false
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        invalidateCurrentCheck()
        modelsTask?.cancel()
        catalogAnalyzer?.cancel()
        modelsGeneration &+= 1
        modelsTask = nil
        isLoadingModels = false
        nextModelRetryAt = nil
    }

    func updateSettings(_ proposed: ResetSubscriptionSettings) throws {
        let updated = try proposed.validated()
        guard updated != settings else { return }
        let previous = settings
        let needsNewAnalysis = Self.analysisConfiguration(previous) != Self.analysisConfiguration(updated)
        if needsNewAnalysis || (previous.enabled && !updated.enabled) { invalidateCurrentCheck() }
        settings = updated
        lastError = nil
        consecutiveFailures = 0
        if previous.urlString != updated.urlString {
            latest = nil
            history = []
            lastCheckedAt = nil
            lastAnalyzedAt = nil
            analyzedFingerprint = nil
            analyzedConfiguration = nil
        }
        if updated.enabled {
            if !previous.enabled || previous.urlString != updated.urlString || needsNewAnalysis {
                nextCheckAt = now()
            } else {
                nextCheckAt = (lastCheckedAt ?? now()).addingTimeInterval(updated.interval)
            }
        } else {
            nextCheckAt = nil
        }
        persist()
        if hasStarted { checkIfDue() }
    }

    func checkNow(forceAnalysis: Bool = false) {
        guard checkTask == nil else { return }
        let version = generation
        let configuration = settings
        phase = .fetching
        lastCheckedAt = now()
        lastError = nil
        checkTask = Task { [weak self] in
            guard let self else { return }
            await self.performCheck(settings: configuration, generation: version, forceAnalysis: forceAnalysis)
            guard self.generation == version else { return }
            self.checkTask = nil
            self.phase = .idle
        }
    }

    func waitForCurrentCheck() async {
        await checkTask?.value
    }

    func refreshAfterWake() {
        refreshIfDue()
    }

    private func refreshIfDue() {
        guard hasStarted else { return }
        checkIfDue()
        // Use the existing heartbeat so failed/empty catalogs recover even while
        // settings stays open. stop() cancels both the heartbeat and any request.
        if let nextModelRetryAt, nextModelRetryAt <= now() { loadModels() }
    }

    func loadModels() {
        let scope = modelCatalogScope()
        if scope != modelsScope {
            modelsGeneration &+= 1
            modelsTask?.cancel()
            catalogAnalyzer?.cancel()
            modelsTask = nil
            isLoadingModels = false
            modelsScope = scope
            modelCatalog = nil
            models = []
            modelError = nil
            nextModelRetryAt = nil
        }
        guard !isLoadingModels else { return }
        let currentTime = now()
        if let catalog = modelCatalog {
            let age = currentTime.timeIntervalSince(catalog.updatedAt)
            if age >= 0 && age < Self.modelCatalogLifetime { return }
        }
        guard nextModelRetryAt.map({ $0 <= currentTime }) ?? true else { return }
        isLoadingModels = true
        modelError = nil
        nextModelRetryAt = currentTime.addingTimeInterval(Self.modelRetryDelay)
        let version = modelsGeneration
        modelsTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.modelsGeneration == version { self.isLoadingModels = false; self.modelsTask = nil }
            }
            do {
                let result = try await self.listModels()
                try Task.checkCancellation()
                guard self.modelsGeneration == version else { return }
                // Login or profile changes invalidate the old catalog, including
                // a response that was already in flight when the change happened.
                guard self.modelCatalogScope() == scope else {
                    self.loadModels()
                    return
                }
                guard !result.isEmpty else {
                    self.modelError = "当前账户未返回可用模型，请确认 Codex 已登录。"
                    self.nextModelRetryAt = self.now().addingTimeInterval(Self.modelRetryDelay)
                    return
                }
                self.modelCatalog = ModelCatalog(models: result, updatedAt: self.now(), scope: scope)
                self.models = result
                self.nextModelRetryAt = nil
                self.persist()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.modelsGeneration == version else { return }
                self.modelError = error.localizedDescription
                self.nextModelRetryAt = self.now().addingTimeInterval(Self.modelRetryDelay)
            }
        }
    }

    func waitForModels() async {
        while let task = modelsTask { await task.value }
    }

    private static func currentModelCatalogScope() -> String {
        let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = configuredHome.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        // Only file metadata is needed to notice login/configuration changes.
        // Authentication contents are never read or stored in this cache.
        return ([directory.standardizedFileURL.path] + ["auth.json", "config.toml"].map { name in
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            return "\(name):\(modified):\(size)"
        }).joined(separator: "\n")
    }

    private func checkIfDue() {
        guard hasStarted, settings.enabled, nextCheckAt.map({ $0 <= now() }) ?? true else { return }
        checkNow()
    }

    private func invalidateCurrentCheck() {
        generation &+= 1
        checkTask?.cancel()
        checkTask = nil
        analyzer?.cancel()
        phase = .idle
    }

    private func performCheck(settings configuration: ResetSubscriptionSettings, generation version: UInt64, forceAnalysis: Bool) async {
        var stage = "获取失败"
        do {
            let configuration = try configuration.validated()
            let source = try await fetch(URL(string: configuration.urlString)!)
            try Task.checkCancellation()
            guard generation == version else { return }
            lastCheckedAt = now()
            let signature = Self.analysisConfiguration(configuration)
            if !forceAnalysis, configuration.analyzeOnlyChanges,
               source.fingerprint == analyzedFingerprint, signature == analyzedConfiguration {
                if var report = latest { report.fetchedAt = source.fetchedAt; latest = report }
                finishSuccessfulCheck(configuration)
                return
            }
            stage = "分析失败"
            phase = .analyzing
            let result = try await analyze(source, configuration)
            try Task.checkCancellation()
            guard generation == version else { return }
            if let usage = result.usage { recordUsage(usage) }
            let report = ResetReportBuilder.report(source: source, analysis: result, settings: configuration, analyzedAt: now())
            let isNew = latest.map { Self.meaningfulChange(from: $0, to: report) } ?? true
            if let previous = latest, isNew {
                history.insert(previous, at: 0)
                history = Array(history.prefix(Self.historyLimit))
            }
            latest = report
            lastAnalyzedAt = report.analyzedAt
            analyzedFingerprint = source.fingerprint
            analyzedConfiguration = signature
            finishSuccessfulCheck(configuration)
            if settings.notifyOnChange, isNew { onNewReport?(report) }
        } catch is CancellationError {
            return
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            consecutiveFailures += 1
            lastError = "\(stage)：\(error.localizedDescription)"
            nextCheckAt = settings.enabled ? now().addingTimeInterval(Self.retryDelay(failures: consecutiveFailures, interval: settings.interval)) : nil
            persist()
        }
    }

    private func finishSuccessfulCheck(_ configuration: ResetSubscriptionSettings) {
        consecutiveFailures = 0
        lastError = nil
        nextCheckAt = settings.enabled ? now().addingTimeInterval(settings.interval) : nil
        persist()
    }

    private func recordUsage(_ record: ResetUsageRecord) {
        if let index = usageRecords.firstIndex(where: { $0.id == record.id }) {
            let previous = usageRecords[index]
            guard record.recordedAt > previous.recordedAt
                || (record.recordedAt == previous.recordedAt && record.totalTokens >= previous.totalTokens) else { return }
            usageRecords[index] = record
        } else {
            usageRecords.insert(record, at: 0)
        }
        let cutoff = now().addingTimeInterval(-Self.usageRetention)
        usageRecords = Array(usageRecords.filter { $0.recordedAt >= cutoff }.sorted { $0.recordedAt > $1.recordedAt }.prefix(Self.usageLimit))
        onUsage?(record)
        persist()
    }

    private func persist() {
        guard persistenceEnabled else { return }
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.settingsKey)
            let cache = Cache(sourceURL: settings.urlString, latest: latest, history: history, usageRecords: usageRecords,
                              lastCheckedAt: lastCheckedAt, lastAnalyzedAt: lastAnalyzedAt, nextCheckAt: nextCheckAt,
                              analyzedFingerprint: analyzedFingerprint, analyzedConfiguration: analyzedConfiguration,
                              modelCatalog: modelCatalog)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch {
            lastError = "保存追踪缓存失败：\(error.localizedDescription)"
        }
    }

    static func retryDelay(failures: Int, interval: TimeInterval) -> TimeInterval {
        min(max(60, interval), 60 * pow(2, Double(min(max(0, failures - 1), 6))))
    }

    static func analysisConfiguration(_ settings: ResetSubscriptionSettings) -> String {
        [settings.urlString, settings.model, settings.reasoningEffort, String(settings.fast)].joined(separator: "\n")
    }

    static func meaningfulChange(from old: ResetSubscriptionReport, to new: ResetSubscriptionReport) -> Bool {
        old.fingerprint != new.fingerprint || old.status != new.status || old.kind != new.kind
            || old.scheduledAt != new.scheduledAt || old.timeDescription != new.timeDescription
    }
}

enum ResetReportBuilder {
    static func report(source: ResetSourceSnapshot, analysis: ResetAnalysisResult, settings: ResetSubscriptionSettings, analyzedAt: Date) -> ResetSubscriptionReport {
        let event = source.event
        // Structured source facts override model guesses, including an explicitly unknown time.
        let scheduledAt: Date?
        let status: ResetEventStatus
        if let event {
            scheduledAt = event.scheduledAt
            status = event.status
        } else {
            // For arbitrary pages, require a verbatim time quote before enabling a countdown.
            let hasTimeEvidence = analysis.timeEvidence.map {
                source.text.contains($0) && ResetDateParser.containsExplicitDate($0, matching: analysis.scheduledAt)
            } ?? false
            scheduledAt = hasTimeEvidence ? analysis.scheduledAt : nil
            status = analysis.status == .scheduled && scheduledAt == nil ? .announced : analysis.status
        }
        return ResetSubscriptionReport(
            fingerprint: source.fingerprint, title: analysis.title, summary: analysis.summary,
            applicability: analysis.applicability, kind: event?.kind ?? analysis.kind, status: status,
            evidenceLevel: event?.evidenceLevel ?? .inference, evidence: event?.text ?? analysis.evidence,
            sourceURL: event?.sourceURL ?? source.url, sourcePublishedAt: event?.publishedAt,
            scheduledAt: scheduledAt, timeDescription: event?.timeDescription ?? analysis.timeDescription,
            expiresAt: event?.expiresAt, fetchedAt: source.fetchedAt, analyzedAt: analyzedAt,
            model: settings.model, reasoningEffort: settings.reasoningEffort, fast: settings.fast, usage: analysis.usage
        )
    }
}
