import Foundation

@MainActor
final class CodexStatusViewModel: ObservableObject {
    @Published private(set) var snapshot: CodexSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var tokenConsumptionGeneration: UInt64 = 0
    @Published var isExpanded = false

    private let client: CodexAppServerClient
    private var pollTimer: Timer?
    private var activityTask: Task<Void, Never>?
    private var threadRefreshGeneration: UInt64 = 0
    private var accountGeneration: UInt64 = 0
    private var refreshPending = false
    private var nextUsageRefreshAt: Date?
    private var nextProfileRefreshAt: Date?
    private var nextDailyThreadDiscoveryAt: Date?
    private var localActivityRolloutPaths: [String] = []
    private var hasDiscoveredLocalActivity = false
    private var tokenConsumptionHighWater: Int64?
    private var tokenConsumptionDayStart: Date?
    private var hasStarted = false

    private static let usageRefreshInterval: TimeInterval = 5 * 60
    private static let profileRefreshInterval: TimeInterval = 15 * 60
    private static let failedRefreshRetryInterval: TimeInterval = 60
    private static let dailyThreadDiscoveryInterval: TimeInterval = 15

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        initialSnapshot: CodexSnapshot = .initial
    ) {
        snapshot = initialSnapshot
        self.client = client

        client.onConnectionChanged = { [weak self] connected, message in
            Task { @MainActor in
                guard let self else { return }
                self.snapshot.connection = connected ? .connected : .disconnected(message)
            }
        }

        client.onNotification = { [weak self] method, _ in
            guard method == "account/rateLimits/updated" || method == "account/updated" else { return }
            Task { @MainActor in
                guard let self else { return }
                if method == "account/updated" {
                    self.accountGeneration &+= 1
                    self.nextUsageRefreshAt = nil
                    self.nextProfileRefreshAt = nil
                    self.snapshot.account = .empty
                    self.snapshot.rateLimit = nil
                    self.snapshot.resetCredits = nil
                    self.snapshot.usage = .empty
                    self.snapshot.profileIdentity = .empty
                    self.snapshot.todayThreadTokens = nil
                    self.tokenConsumptionHighWater = nil
                    self.tokenConsumptionDayStart = nil
                    self.localActivityRolloutPaths = []
                    self.hasDiscoveredLocalActivity = false
                    self.nextDailyThreadDiscoveryAt = nil
                }
                self.refresh()
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        snapshot.connection = .connecting
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.refreshRecentThreadStates()
                await self.refreshDailyThreadTokens()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        activityTask?.cancel()
        activityTask = nil
        threadRefreshGeneration &+= 1
        hasStarted = false
        client.stop()
    }

    func refreshIfStale(maxAge: TimeInterval = 12) {
        guard let lastUpdated = snapshot.lastUpdated else {
            refresh()
            return
        }
        if Date().timeIntervalSince(lastUpdated) > maxAge {
            refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true

        Task {
            repeat {
                refreshPending = false
                await performRefresh()
            } while refreshPending
            isRefreshing = false
        }
    }

    private func performRefresh() async {
        do {
            try await client.start()
            snapshot.connection = .connected
        } catch {
            snapshot.connection = .disconnected(error.localizedDescription)
            snapshot.warning = error.localizedDescription
            return
        }

        let generation = accountGeneration
        var updated = snapshot
        updated.connection = .connected
        var warnings: [String] = []
        var resolvedNextUsageRefreshAt = nextUsageRefreshAt
        var resolvedNextProfileRefreshAt = nextProfileRefreshAt

        do {
            let result = try await client.request(
                method: "account/read",
                params: ["refreshToken": false]
            )
            updated.account = CodexStatusPayloadParser.parseAccount(result)
        } catch {
            warnings.append("账户信息不可用")
        }

        let now = Date()
        let shouldRefreshProfile = updated.account.authType == "chatgpt"
            && isRefreshDue(nextRefreshAt: nextProfileRefreshAt, now: now)
        let profileTask: Task<ProfileIdentityLoadResult, Never>?
        if shouldRefreshProfile {
            profileTask = Task { [weak self] in
                guard let self else {
                    return ProfileIdentityLoadResult(
                        identity: .empty,
                        isRemoteProfile: false,
                        authorizationRejected: false,
                        retrySoon: true
                    )
                }
                return await self.requestProfileIdentity()
            }
        } else {
            profileTask = nil
        }

        do {
            let result = try await client.request(method: "account/rateLimits/read")
            let (limit, resets) = CodexStatusPayloadParser.parseRateLimits(result)
            updated.rateLimit = limit
            updated.resetCredits = resets
        } catch {
            warnings.append("额度信息不可用")
        }

        if isRefreshDue(nextRefreshAt: nextUsageRefreshAt, now: now) {
            do {
                let result = try await client.request(method: "account/usage/read")
                updated.usage = CodexStatusPayloadParser.parseUsage(result)
                resolvedNextUsageRefreshAt = Date().addingTimeInterval(
                    Self.usageRefreshInterval
                )
            } catch {
                resolvedNextUsageRefreshAt = Date().addingTimeInterval(
                    Self.failedRefreshRetryInterval
                )
                if updated.usage == .empty {
                    warnings.append("账户统计不可用")
                }
            }
        }

        let threadGeneration = beginThreadRefresh()
        var refreshedThreads: [ThreadSummary]?
        do {
            let recentThreads = try await requestRecentThreads()
            let resolvedThreads = await resolveNewThreadList(recentThreads)
            if threadGeneration == threadRefreshGeneration {
                refreshedThreads = resolvedThreads
            }
        } catch {
            warnings.append("会话状态不可用")
        }

        // A newer lightweight refresh may have completed while the account and
        // quota requests above were in flight. Never replace its list with the
        // older copy captured at the beginning of this full refresh.
        updated.recentThreads = refreshedThreads ?? snapshot.recentThreads
        updated.hasRunningSession = updated.recentThreads.contains {
            $0.executionState == .running
        }

        if let profileTask {
            let loadedProfile = await profileTask.value
            if loadedProfile.isRemoteProfile {
                updated.profileIdentity = loadedProfile.retrySoon
                    ? Self.fillingMissingProfileFields(
                        in: loadedProfile.identity,
                        from: updated.profileIdentity
                    )
                    : loadedProfile.identity
                resolvedNextProfileRefreshAt = Date().addingTimeInterval(
                    loadedProfile.retrySoon
                        ? Self.failedRefreshRetryInterval
                        : Self.profileRefreshInterval
                )
            } else {
                updated.profileIdentity = Self.fillingMissingProfileFields(
                    in: updated.profileIdentity,
                    from: loadedProfile.identity
                )
                resolvedNextProfileRefreshAt = Date().addingTimeInterval(
                    Self.failedRefreshRetryInterval
                )
            }
        }

        // Account changes invalidate every result captured above. The queued
        // refresh will run immediately after this one and load the new account.
        guard generation == accountGeneration else { return }
        nextUsageRefreshAt = resolvedNextUsageRefreshAt
        nextProfileRefreshAt = resolvedNextProfileRefreshAt
        updated.lastUpdated = Date()
        updated.warning = warnings.isEmpty ? nil : warnings.joined(separator: " · ")

        // Profile/account requests can outlive the one-second activity poll.
        // Preserve any newer local activity instead of publishing the stale
        // snapshot copy captured at the start of this full refresh.
        if threadGeneration != threadRefreshGeneration {
            updated.recentThreads = snapshot.recentThreads
        }
        updated.todayThreadTokens = snapshot.todayThreadTokens
        updated.hasRunningSession = snapshot.hasRunningSession
            || updated.recentThreads.contains { $0.executionState == .running }
        if case .disconnected = snapshot.connection {
            // A termination callback may have arrived while this refresh was awaiting a response.
            updated.connection = snapshot.connection
        }
        snapshot = updated
    }

    private func requestProfileIdentity() async -> ProfileIdentityLoadResult {
        let initialAuth = try? await client.request(
            method: "getAuthStatus",
            params: ["includeToken": true, "refreshToken": false]
        )
        var result = await CodexProfileIdentityProvider.load(
            authToken: initialAuth?.string("authToken")
        )
        guard result.authorizationRejected else { return result }

        let refreshedAuth = try? await client.request(
            method: "getAuthStatus",
            params: ["includeToken": true, "refreshToken": true]
        )
        result = await CodexProfileIdentityProvider.load(
            authToken: refreshedAuth?.string("authToken")
        )
        return result
    }

    private func isRefreshDue(nextRefreshAt: Date?, now: Date) -> Bool {
        guard let nextRefreshAt else { return true }
        return now >= nextRefreshAt
    }

    private static func fillingMissingProfileFields(
        in current: ProfileIdentitySummary,
        from fallback: ProfileIdentitySummary
    ) -> ProfileIdentitySummary {
        ProfileIdentitySummary(
            displayName: current.displayName ?? fallback.displayName,
            avatarData: current.avatarData ?? fallback.avatarData
        )
    }

    /// Refreshes the small, state-db-backed thread list every second without
    /// touching account or quota endpoints. Runtime settings and config
    /// fallbacks are only resolved when a thread enters or leaves the recent
    /// list; the common path only reads appended rollout activity.
    private func refreshRecentThreadStates() async {
        let generation = beginThreadRefresh()

        let listedThreads: [ThreadSummary]
        do {
            listedThreads = try await requestRecentThreads(timeout: 3)
        } catch {
            // The 30-second full refresh owns connection and warning state. A
            // transient fast-poll failure should not make the island flicker.
            return
        }

        guard generation == threadRefreshGeneration else { return }

        let currentThreads = snapshot.recentThreads
        let listedIDs = Set(listedThreads.map(\.id))
        let currentIDs = Set(currentThreads.map(\.id))
        let currentByID = Dictionary(uniqueKeysWithValues: currentThreads.map { ($0.id, $0) })
        let rolloutMetadataChanged = listedThreads.contains { listed in
            guard let current = currentByID[listed.id] else { return true }
            return listed.rolloutPath != current.rolloutPath || listed.cwd != current.cwd
        }

        let updatedThreads: [ThreadSummary]
        if listedIDs != currentIDs
            || listedThreads.count != currentThreads.count
            || rolloutMetadataChanged {
            updatedThreads = await resolveNewThreadList(listedThreads)
        } else {
            // Preserve the already-resolved model, reasoning, and Fast values,
            // while following the newest recency ordering and rollout path from
            // thread/list. The latter matters while a brand-new task is still
            // being initialized and its path appears one poll later.
            let orderedThreads = Self.mergingListMetadata(
                listedThreads,
                withResolvedThreads: currentThreads
            )
            let activities = await Self.loadExecutionSnapshots(for: orderedThreads)
            updatedThreads = Self.applying(activities, to: orderedThreads)
        }

        // Full refreshes and notification-triggered refreshes can overlap this
        // work. Only the newest thread request is allowed to publish a result.
        guard generation == threadRefreshGeneration else { return }
        let recentHasRunningSession = updatedThreads.contains {
            $0.executionState == .running
        }
        guard updatedThreads != snapshot.recentThreads
                || (recentHasRunningSession && !snapshot.hasRunningSession) else {
            return
        }
        snapshot.recentThreads = updatedThreads
        // Recent rows can light the indicator immediately. Only the subsequent
        // all-rollout pass is authoritative enough to clear it again.
        if recentHasRunningSession {
            snapshot.hasRunningSession = true
        }
    }

    private func beginThreadRefresh() -> UInt64 {
        threadRefreshGeneration &+= 1
        return threadRefreshGeneration
    }

    private func requestRecentThreads(timeout: TimeInterval = 12) async throws -> [ThreadSummary] {
        try await requestThreads(
            limit: CodexDisplayPolicy.recentThreadLimit,
            archived: false,
            timeout: timeout
        )
    }

    private func requestThreads(
        limit: Int,
        archived: Bool,
        timeout: TimeInterval
    ) async throws -> [ThreadSummary] {
        let result = try await client.request(
            method: "thread/list",
            params: [
                "limit": limit,
                "sortKey": "recency_at",
                "sortDirection": "desc",
                "archived": archived,
                "sourceKinds": ["cli", "vscode"],
                "useStateDbOnly": true
            ],
            timeout: timeout
        )
        return CodexStatusPayloadParser.parseRecentThreads(result, limit: limit)
    }

    /// Discovers every local root CLI/App rollout periodically, then reduces
    /// cumulative counters and lifecycle events every second. The visible five
    /// rows remain an immediate fallback while a new rollout awaits discovery.
    private func refreshDailyThreadTokens() async {
        let now = Date()
        let dayStart = Calendar.autoupdatingCurrent.startOfDay(for: now)
        if tokenConsumptionDayStart != dayStart {
            tokenConsumptionDayStart = dayStart
            tokenConsumptionHighWater = nil
        }
        if isRefreshDue(nextRefreshAt: nextDailyThreadDiscoveryAt, now: now) {
            let discovered = await Task.detached(priority: .utility) {
                try? CodexDailyTokenUsageReader.discoverRootConversationRollouts(
                    now: now
                )
            }.value
            if let discovered {
                localActivityRolloutPaths = discovered
                hasDiscoveredLocalActivity = true
                nextDailyThreadDiscoveryAt = now.addingTimeInterval(
                    Self.dailyThreadDiscoveryInterval
                )
            } else {
                nextDailyThreadDiscoveryAt = now.addingTimeInterval(
                    Self.failedRefreshRetryInterval
                )
                guard hasDiscoveredLocalActivity else { return }
            }
        }

        guard hasDiscoveredLocalActivity else { return }
        let discoveredPaths = localActivityRolloutPaths
        let recentPaths = snapshot.recentThreads.compactMap(\.rolloutPath)
        let tokenPaths = Array(Set(discoveredPaths + recentPaths))
        let recentHasRunningSession = snapshot.recentThreads.contains {
            $0.executionState == .running
        }
        let localActivity = await Task.detached(priority: .utility) {
            let total = try? CodexDailyTokenUsageReader.readToday(
                from: tokenPaths,
                now: now
            )
            let runningCutoff = now.addingTimeInterval(-30 * 60)
            let freshPaths = discoveredPaths.filter { path in
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                let modifiedAt = attributes?[.modificationDate] as? Date
                return modifiedAt.map { $0 >= runningCutoff } ?? false
            }
            let hasRunningSession = freshPaths.contains { path in
                (try? CodexThreadActivityReader.readLatest(from: path))?
                    .executionState == .running
            }
            return (total, hasRunningSession)
        }.value
        if let total = localActivity.0 {
            if total != snapshot.todayThreadTokens {
                snapshot.todayThreadTokens = total
            }
            if CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: tokenConsumptionHighWater,
                current: total
            ) {
                tokenConsumptionGeneration &+= 1
            }
            tokenConsumptionHighWater = CodexDisplayPolicy
                .updatedTokenConsumptionHighWater(
                    previous: tokenConsumptionHighWater,
                    current: total
                )
        }
        let hasRunningSession = recentHasRunningSession || localActivity.1
        if hasRunningSession != snapshot.hasRunningSession {
            snapshot.hasRunningSession = hasRunningSession
        }
    }

    private func resolveNewThreadList(_ threads: [ThreadSummary]) async -> [ThreadSummary] {
        let recordedThreads = await Self.loadRuntimeSettings(for: threads)
        let configuredThreads = await loadEffectiveServiceTierFallbacks(for: recordedThreads)
        let activities = await Self.loadExecutionSnapshots(for: configuredThreads)
        return Self.applying(activities, to: configuredThreads)
    }

    private static func mergingListMetadata(
        _ listedThreads: [ThreadSummary],
        withResolvedThreads currentThreads: [ThreadSummary]
    ) -> [ThreadSummary] {
        let currentByID = Dictionary(uniqueKeysWithValues: currentThreads.map { ($0.id, $0) })
        return listedThreads.compactMap { listed in
            guard let current = currentByID[listed.id] else { return nil }
            var merged = listed
            merged.model = current.model ?? listed.model
            merged.reasoningEffort = current.reasoningEffort ?? listed.reasoningEffort
            merged.serviceTier = current.serviceTier ?? listed.serviceTier
            merged.serviceTierSource = current.serviceTierSource ?? listed.serviceTierSource
            merged.tokenUsage = current.tokenUsage
            merged.executionState = current.executionState
            merged.updatedAt = current.updatedAt ?? listed.updatedAt
            return merged
        }
    }

    private nonisolated static func loadExecutionSnapshots(
        for threads: [ThreadSummary]
    ) async -> [String: ThreadActivitySnapshot] {
        await withTaskGroup(of: (String, ThreadActivitySnapshot?).self) { group in
            for thread in threads {
                guard let rolloutPath = thread.rolloutPath else { continue }
                group.addTask(priority: .utility) {
                    let snapshot = try? CodexThreadActivityReader.readLatest(
                        from: rolloutPath,
                        threadID: thread.id
                    )
                    return (thread.id, snapshot)
                }
            }

            var snapshots: [String: ThreadActivitySnapshot] = [:]
            for await (threadID, snapshot) in group {
                if let snapshot {
                    snapshots[threadID] = snapshot
                }
            }
            return snapshots
        }
    }

    private static func applying(
        _ activities: [String: ThreadActivitySnapshot],
        to threads: [ThreadSummary]
    ) -> [ThreadSummary] {
        var resolved = threads
        for index in resolved.indices {
            guard let activity = activities[resolved[index].id] else { continue }
            resolved[index].executionState = activity.executionState
            resolved[index].tokenUsage = activity.tokenUsage
            resolved[index].updatedAt = activity.updatedAt
        }
        return resolved
    }

    private nonisolated static func loadRuntimeSettings(
        for threads: [ThreadSummary]
    ) async -> [ThreadSummary] {
        var resolved = threads
        await withTaskGroup(of: (Int, ThreadRuntimeSettings?).self) { group in
            for (index, thread) in threads.enumerated() {
                guard let rolloutPath = thread.rolloutPath else { continue }
                group.addTask(priority: .utility) {
                    let settings = try? CodexThreadSettingsReader.readLatest(
                        from: rolloutPath,
                        threadID: thread.id
                    )
                    return (index, settings)
                }
            }

            for await (index, settings) in group {
                guard resolved.indices.contains(index), let settings else { continue }
                resolved[index].model = settings.model ?? resolved[index].model
                resolved[index].reasoningEffort = settings.reasoningEffort
                    ?? resolved[index].reasoningEffort
                if let serviceTier = settings.serviceTier {
                    resolved[index].serviceTier = serviceTier
                    resolved[index].serviceTierSource = .recorded
                }
            }
        }
        return resolved
    }

    /// TUI rollouts do not always persist `service_tier`. In that case, use the
    /// task directory's current effective config as a clearly marked fallback.
    /// This is the tier Codex would use on the next resume, not historical proof.
    private func loadEffectiveServiceTierFallbacks(
        for threads: [ThreadSummary]
    ) async -> [ThreadSummary] {
        var resolved = threads
        var attemptedDirectories = Set<String>()
        var tierByDirectory: [String: String] = [:]

        for index in resolved.indices where resolved[index].serviceTier == nil {
            let directory = resolved[index].cwd ?? ""
            if !attemptedDirectories.contains(directory) {
                attemptedDirectories.insert(directory)
                var params: JSONObject = ["includeLayers": false]
                if !directory.isEmpty {
                    params["cwd"] = directory
                }
                if let result = try? await client.request(
                    method: "config/read",
                    params: params
                ), let tier = CodexStatusPayloadParser.parseEffectiveServiceTier(result) {
                    tierByDirectory[directory] = tier
                }
            }

            if let tier = tierByDirectory[directory] {
                resolved[index].serviceTier = tier
                resolved[index].serviceTierSource = .effectiveConfig
            }
        }
        return resolved
    }
}
