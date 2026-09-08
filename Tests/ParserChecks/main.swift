import Darwin
import Foundation

@main
struct ParserChecks {
    private static var failures = 0

    static func main() {
        for (account, quota, expected) in [
            ("plus", "plus", 2_750.0),
            ("pro", "prolite", 13_750.0),
            ("prolite", "prolite", 13_750.0),
            ("pro", "pro", 55_000.0)
        ] {
            let label = CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: account, rateLimitPlanType: quota
            )
            expect(CodexDisplayPolicy.remainingCredits(planLabel: label, remainingPercent: 100) == expected,
                   "account and quota plan types resolve the correct credits allowance: \(account)/\(quota)")
        }
        expect(CodexDisplayPolicy.remainingCredits(planLabel: "PLUS", remainingPercent: 100) == 2750,
               "Plus credits use the requested 2750 baseline")
        expect(CodexDisplayPolicy.remainingCredits(planLabel: "PRO5X", remainingPercent: 50) == 6875,
               "5X credits scale the baseline and remaining percentage")
        expect(CodexDisplayPolicy.remainingCredits(planLabel: "PRO 20X", remainingPercent: 99) == 54450,
               "20X credits scale the baseline and remaining percentage")
        expect(CodexDisplayPolicy.remainingCredits(planLabel: "PRO", remainingPercent: 99) == nil,
               "unknown Pro tier does not guess a credits allowance")
        expect(CodexDisplayPolicy.remainingCredits(planLabel: "PLUS", remainingPercent: nil) == nil,
               "missing quota cannot show a credits balance")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346, unpricedCalls: 1)
            .displayText(matching: 100) == "≥12.3 credits",
               "unknown historical calls preserve the priced subtotal rounded down")
        expect(CodexChartCreditTotal().displayText(matching: 100) == "— credits",
               "account-only historical tokens cannot invent credits")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346)
            .displayText(matching: 100) == "12.3 credits",
               "complete historical costs keep their normal rounded total")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346)
            .displayText(matching: 1000) == "12.3 credits",
               "other computers do not mark complete local credits as partial")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346)
            .displayText(matching: 50) == "12.3 credits",
               "delayed account totals do not hide complete local credits")
        expect(CodexThreadCreditEstimate(credits: 0).displayText == "0 credits",
               "zero credits omit the decimal fraction")
        expect(CodexThreadCreditEstimate(credits: 1).displayText == "1.0 credits",
               "nonzero credits retain one decimal place")
        let partialCredits = CodexChartCreditTotal(
            tokens: 100, credits: 1.26, standardCredits: 0.56, unpricedCalls: 1
        )
        expect(partialCredits.chartDisplayText(matching: 100, showsStandard: true, showsActual: true)
            == "≥0.5 / ≥1.2", "both credit series show conservative, separately labeled lower bounds")
        expect(partialCredits.chartDisplayText(matching: 100, showsStandard: false, showsActual: true)
            == "≥1.2", "actual-only credits do not round a lower bound upward")
        expect(partialCredits.chartDisplayText(matching: 100, showsStandard: true, showsActual: false)
            == "≥0.5", "standard-only credits do not round a lower bound upward")
        expect(partialCredits.displayText(matching: 100) == "≥1.2 credits",
               "token mode uses the same conservative lower bound")
        expect(CodexChartCreditTotal(tokens: 100, credits: 1.26, standardCredits: 0.56)
            .chartDisplayText(matching: 100, showsStandard: true, showsActual: true) == "0.6 / 1.3",
               "fully priced credit totals retain normal rounding")
        expect(CodexChartCreditTotal(tokens: 100, credits: 0.04, unpricedCalls: 1)
            .chartDisplayText(matching: 100, showsStandard: false, showsActual: true) == "—",
               "tiny incomplete costs do not claim a positive lower bound")
        expect(CodexChartCreditTotal().chartDisplayText(matching: 100, showsStandard: true, showsActual: true)
            == "—", "credit mode does not invent costs for account-only history")
        checkRateLimitsAndResetCredits()
        checkResetCreditExpiryWarning()
        checkCodexBucketPreference()
        checkTokenConsumptionPolicy()
        checkQuotaConsumptionPace()
        checkQuotaRemainingLevels()
        checkEstimatedRemainingTokens()
        checkTokenEstimateRollouts()
        checkFastModeUsageMultipliers()
        checkDisplayModelNames()
        checkReasoningEffortLabels()
        checkHeaderTokenCounts()
        checkTaskCompletionTransitions()
        checkVisibleThreadPriority()
        checkAccountUsageThreadAndModel()
        checkPlanBadgeLabels()
        checkLanguageResolution()
        checkDisplayTargetResolution()
        checkLaunchAtLoginSetting()
        checkThreadDeepLinks()
        checkUsageTimeline()
        checkRecentThreads()
        checkEffectiveServiceTier()
        checkThreadRuntimeSettings()
        checkThreadActivityStates()
        checkThreadCreditUsage()
        checkDailyTokenUsage()

        guard failures == 0 else {
            fputs("\(failures) parser check(s) failed\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("All parser checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }

    private static func checkVisibleThreadPriority() {
        func thread(_ id: String, _ state: ThreadExecutionState) -> ThreadSummary {
            ThreadSummary(
                id: id,
                title: id,
                status: "notLoaded",
                clientSource: .app,
                model: nil,
                reasoningEffort: nil,
                serviceTier: nil,
                serviceTierSource: nil,
                tokenUsage: nil,
                executionState: state,
                cwd: nil,
                rolloutPath: nil,
                updatedAt: nil
            )
        }

        let visible = CodexDisplayPolicy.visibleRecentThreads(
            from: [
                thread("recent-1", .idle),
                thread("active-1", .running),
                thread("recent-2", .failed),
                thread("active-2", .running),
                thread("recent-3", .unknown)
            ]
        )
        expect(visible.count == 3, "dashboard displays exactly three recent tasks")
        expect(
            visible.map(\.id) == ["active-1", "active-2", "recent-1"],
            "running tasks are shown first while preserving recency within groups"
        )
        expect(
            CodexDisplayPolicy.recentThreadFetchLimit
                > CodexDisplayPolicy.recentThreadLimit,
            "thread query keeps a wider candidate set than the visible dashboard"
        )
    }

    private static func checkTaskCompletionTransitions() {
        func thread(_ id: String, _ state: ThreadExecutionState) -> ThreadSummary {
            ThreadSummary(
                id: id,
                title: id,
                status: "notLoaded",
                clientSource: .app,
                model: nil,
                reasoningEffort: nil,
                serviceTier: nil,
                serviceTierSource: nil,
                tokenUsage: nil,
                executionState: state,
                cwd: nil,
                rolloutPath: nil,
                updatedAt: nil
            )
        }

        let previous: [String: ThreadExecutionState] = [
            "completed": .running,
            "interrupted": .running,
            "failed": .running,
            "already-idle": .idle,
            "removed": .running
        ]
        let completed = CodexDisplayPolicy.completedThreadIDs(
            previousStates: previous,
            currentThreads: [
                thread("completed", .idle),
                thread("interrupted", .interrupted),
                thread("failed", .failed),
                thread("already-idle", .idle),
                thread("new-history", .idle)
            ]
        )
        expect(
            completed == ["completed"],
            "completion sound only observes a running-to-idle transition"
        )

        let inputRequested = CodexDisplayPolicy.inputRequestedThreadIDs(
            previousStates: ["waiting": .running, "already-waiting": .waitingForInput],
            currentThreads: [
                thread("waiting", .waitingForInput),
                thread("already-waiting", .waitingForInput),
                thread("running", .running)
            ]
        )
        expect(
            inputRequested == ["waiting"],
            "approval sound only observes a transition into waiting for input"
        )
    }

    private static func checkPlanBadgeLabels() {
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: "prolite"
            ) == "PRO5X",
            "Pro Lite quota bucket displays 5X"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: "pro"
            ) == "PRO 20X",
            "Pro quota bucket displays 20X"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: nil
            ) == "PRO",
            "missing Pro subtype stays generic"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: nil,
                rateLimitPlanType: " PROLITE "
            ) == "PRO5X",
            "quota bucket can supply plan while account data is unavailable"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "plus",
                rateLimitPlanType: "prolite"
            ) == "PLUS",
            "account plan wins for non-Pro accounts"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: nil,
                rateLimitPlanType: nil
            ) == nil,
            "missing plan stays hidden"
        )
    }

    private static func checkLanguageResolution() {
        expect(
            IslandLanguagePreference.stored(nil) == .automatic,
            "missing language preference defaults to automatic"
        )
        expect(
            IslandLanguagePreference.stored("unsupported") == .automatic,
            "invalid stored language preference defaults to automatic"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .automatic,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .chinese,
            "automatic language selects Chinese for zh-Hans"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .automatic,
                preferredLanguages: ["en-US"]
            ) == .english,
            "automatic language selects English for en-US"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .automatic,
                preferredLanguages: ["ja-JP", "zh-Hans-CN"]
            ) == .english,
            "automatic language falls back to English when the primary OS language is unsupported"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .chinese,
                preferredLanguages: ["en-US"]
            ) == .chinese,
            "manual Chinese overrides the OS language"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .english,
            "manual English overrides the OS language"
        )
    }

    private static func checkDisplayTargetResolution() {
        let builtIn = IslandDisplayDescriptor(
            identifier: "built-in-uuid",
            name: "Built-in Retina Display",
            isBuiltIn: true,
            sortIndex: 0
        )
        let externalLeft = IslandDisplayDescriptor(
            identifier: "external-left-uuid",
            name: "HP Z27s",
            isBuiltIn: false,
            sortIndex: 1
        )
        let externalRight = IslandDisplayDescriptor(
            identifier: "external-right-uuid",
            name: "HP Z27s",
            isBuiltIn: false,
            sortIndex: 2
        )
        let displays = [builtIn, externalLeft, externalRight]

        expect(
            IslandDisplayTargetPreference.stored(nil) == .automatic,
            "missing display preference defaults to automatic"
        )
        expect(
            IslandDisplayTargetPreference.stored("unsupported") == .automatic,
            "invalid display preference defaults to automatic"
        )
        expect(
            IslandDisplayTargetPreference.stored("external:external-left-uuid")
                == .external(identifier: "external-left-uuid"),
            "external display preference round-trips its stable identifier"
        )
        expect(
            IslandDisplayTargetPreference.builtIn.storedValue == "built-in",
            "built-in display preference has a stable persisted value"
        )
        expect(
            IslandDisplayTargetPreference
                .external(identifier: externalRight.identifier)
                .storedValue == "external:external-right-uuid",
            "external display preference persists the stable display identifier"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .automatic,
                displays: displays,
                automaticIdentifier: builtIn.identifier
            ) == builtIn.identifier,
            "automatic display selection preserves the existing resolver result"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .builtIn,
                displays: displays,
                automaticIdentifier: externalLeft.identifier
            ) == builtIn.identifier,
            "built-in preference overrides the automatic external display"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .external(identifier: externalRight.identifier),
                displays: displays,
                automaticIdentifier: builtIn.identifier
            ) == externalRight.identifier,
            "named external display resolves by stable identifier"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .external(identifier: externalRight.identifier),
                displays: [builtIn, externalLeft],
                automaticIdentifier: builtIn.identifier
            ) == builtIn.identifier,
            "disconnected external display temporarily falls back to automatic"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .external(identifier: externalRight.identifier),
                displays: displays,
                automaticIdentifier: builtIn.identifier
            ) == externalRight.identifier,
            "reconnected external display restores the saved target"
        )

        let choices = IslandDisplayChoiceBuilder.makeChoices(
            displays: displays,
            selection: .external(identifier: externalRight.identifier)
        )
        expect(
            choices.map(\.target) == [
                .automatic,
                .builtIn,
                .external(identifier: externalLeft.identifier),
                .external(identifier: externalRight.identifier)
            ],
            "display choices include automatic, built-in, and every external display"
        )
        expect(
            choices.compactMap(\.duplicateIndex) == [1, 2],
            "same-name external displays receive deterministic disambiguation indexes"
        )

        let disconnectedChoices = IslandDisplayChoiceBuilder.makeChoices(
            displays: [builtIn, externalLeft],
            selection: .external(identifier: externalRight.identifier)
        )
        expect(
            disconnectedChoices.last == IslandDisplayChoice(
                target: .external(identifier: externalRight.identifier),
                display: nil,
                duplicateIndex: nil,
                isAvailable: false
            ),
            "a disconnected saved display remains visible without losing the preference"
        )
    }

    private static func checkLaunchAtLoginSetting() {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("codex-island-launch-agent-\(UUID().uuidString)")
        let plistURL = directory
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("com.codexisland.app.login-item.plist")
        let appBundleURL = URL(
            fileURLWithPath: "/Applications/Codex Island.app",
            isDirectory: true
        )
        let appExecutableURL = appBundleURL
            .appendingPathComponent("Contents/MacOS/Codex Island")
        let bundleIdentifier = "com.codexisland.app"
        defer { try? fileManager.removeItem(at: directory) }

        let productionBackend = LaunchAtLoginBackend.launchAgent(
            plistURL: plistURL,
            appBundleURL: appBundleURL,
            appExecutableURL: appExecutableURL,
            bundleIdentifier: bundleIdentifier,
            fileManager: fileManager
        )
        var productionSetting = LaunchAtLoginSettingModel(
            backend: productionBackend
        )
        expect(productionSetting.state == .disabled, "missing launch agent defaults off")
        expect(!fileManager.fileExists(atPath: plistURL.path), "initialization never creates launch agent")
        productionSetting.refresh()
        expect(!fileManager.fileExists(atPath: plistURL.path), "refresh never creates launch agent")

        productionSetting.setEnabled(true)
        expect(productionSetting.state == .enabled, "valid launch agent enables login launch")
        expect(fileManager.fileExists(atPath: plistURL.path), "enable writes the launch agent plist")

        do {
            let data = try Data(contentsOf: plistURL)
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
            expect(
                propertyList?["Label"] as? String
                    == "\(bundleIdentifier).login-item",
                "launch agent uses the dedicated label"
            )
            expect(propertyList?["RunAtLoad"] as? Bool == true, "launch agent runs when loaded")
            expect(
                propertyList?["ProgramArguments"] as? [String]
                    == [appExecutableURL.path],
                "launch agent directly executes the branded app binary"
            )
            expect(
                propertyList?["AssociatedBundleIdentifiers"] as? [String]
                    == [bundleIdentifier],
                "launch agent is associated with the Codex Island bundle"
            )
            expect(propertyList?["KeepAlive"] == nil, "launch agent never keeps or relaunches the app")
            expect(
                !String(decoding: data, as: UTF8.self).contains("/usr/bin/open"),
                "launch agent never exposes the generic open executable"
            )

            let attributes = try fileManager.attributesOfItem(atPath: plistURL.path)
            expect(
                attributes[.posixPermissions] as? Int == 0o644,
                "launch agent plist has user-writable standard permissions"
            )

            let plutil = Process()
            plutil.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            plutil.arguments = ["-lint", plistURL.path]
            plutil.standardOutput = FileHandle.nullDevice
            plutil.standardError = FileHandle.nullDevice
            try plutil.run()
            plutil.waitUntilExit()
            expect(plutil.terminationStatus == 0, "launch agent plist passes plutil lint")
        } catch {
            expect(false, "launch agent plist inspection: \(error.localizedDescription)")
        }

        productionSetting.setEnabled(true)
        expect(productionSetting.state == .enabled, "repeated enable remains idempotent")
        productionSetting.setEnabled(false)
        expect(productionSetting.state == .disabled, "disable removes login launch")
        expect(!fileManager.fileExists(atPath: plistURL.path), "disable removes only the launch agent plist")
        productionSetting.setEnabled(false)
        expect(productionSetting.state == .disabled, "repeated disable remains idempotent")

        do {
            try fileManager.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let legacyData = try PropertyListSerialization.data(
                fromPropertyList: [
                    "Label": "\(bundleIdentifier).login-item",
                    "ProgramArguments": [
                        "/usr/bin/open",
                        "-g",
                        appBundleURL.path
                    ],
                    "RunAtLoad": true
                ],
                format: .xml,
                options: 0
            )
            try legacyData.write(to: plistURL, options: .atomic)

            let migratedSetting = LaunchAtLoginSettingModel(
                backend: productionBackend
            )
            expect(
                migratedSetting.state == .enabled,
                "legacy open registration migrates without disabling login launch"
            )

            let migratedData = try Data(contentsOf: plistURL)
            let migratedPropertyList = try PropertyListSerialization.propertyList(
                from: migratedData,
                options: [],
                format: nil
            ) as? [String: Any]
            expect(
                migratedPropertyList?["ProgramArguments"] as? [String]
                    == [appExecutableURL.path],
                "legacy registration is rewritten to the branded executable"
            )
            expect(
                migratedPropertyList?["AssociatedBundleIdentifiers"] as? [String]
                    == [bundleIdentifier],
                "legacy migration adds app attribution"
            )
        } catch {
            expect(false, "legacy launch agent migration: \(error.localizedDescription)")
        }

        var migratedSetting = LaunchAtLoginSettingModel(backend: productionBackend)
        migratedSetting.setEnabled(false)
        expect(!fileManager.fileExists(atPath: plistURL.path), "migrated registration remains removable")

        let previousPlistURL = plistURL.deletingLastPathComponent()
            .appendingPathComponent("legacy.codex-island.login-item.plist")
        do {
            let previousData = try PropertyListSerialization.data(
                fromPropertyList: [
                    "AssociatedBundleIdentifiers": ["legacy.codex-island"],
                    "Label": "legacy.codex-island.login-item",
                    "ProgramArguments": [appExecutableURL.path],
                    "RunAtLoad": true
                ],
                format: .xml,
                options: 0
            )
            try previousData.write(to: previousPlistURL, options: .atomic)

            let renamedBackend = LaunchAtLoginBackend.launchAgent(
                plistURL: plistURL,
                legacyPlistURLs: [previousPlistURL],
                appBundleURL: appBundleURL,
                appExecutableURL: appExecutableURL,
                bundleIdentifier: bundleIdentifier,
                fileManager: fileManager
            )
            let renamedSetting = LaunchAtLoginSettingModel(
                backend: renamedBackend
            )
            expect(
                renamedSetting.state == .enabled,
                "renamed bundle registration migrates without disabling login launch"
            )
            expect(
                fileManager.fileExists(atPath: plistURL.path),
                "renamed bundle migration writes the current launch agent"
            )
            expect(
                !fileManager.fileExists(atPath: previousPlistURL.path),
                "renamed bundle migration removes the previous launch agent"
            )

            var removableSetting = renamedSetting
            removableSetting.setEnabled(false)
            expect(
                !fileManager.fileExists(atPath: plistURL.path),
                "renamed bundle migration remains removable"
            )
        } catch {
            expect(false, "renamed launch agent migration: \(error.localizedDescription)")
        }

        let initialService = FakeLaunchAtLoginService(status: .notRegistered)
        var initialSetting = LaunchAtLoginSettingModel(
            backend: initialService.backend
        )
        expect(initialSetting.state == .disabled, "launch at login defaults off")
        expect(initialService.registerCallCount == 0, "initialization never registers login item")
        initialSetting.refresh()
        expect(initialService.registerCallCount == 0, "refresh never registers login item")

        let enabledService = FakeLaunchAtLoginService(status: .notRegistered)
        enabledService.statusAfterRegister = .enabled
        enabledService.statusAfterUnregister = .notRegistered
        var enabledSetting = LaunchAtLoginSettingModel(
            backend: enabledService.backend
        )
        enabledSetting.setEnabled(true)
        expect(enabledSetting.state == .enabled, "successful registration enables login item")
        expect(enabledService.registerCallCount == 1, "enable registers exactly once")
        enabledSetting.setEnabled(true)
        expect(enabledService.registerCallCount == 1, "already enabled login item is idempotent")
        enabledSetting.setEnabled(false)
        expect(enabledSetting.state == .disabled, "successful unregistration disables login item")
        expect(enabledService.unregisterCallCount == 1, "disable unregisters exactly once")
        enabledSetting.setEnabled(false)
        expect(enabledService.unregisterCallCount == 1, "already disabled login item is idempotent")

        let failedEnableService = FakeLaunchAtLoginService(status: .notRegistered)
        failedEnableService.registerError = LaunchAtLoginTestError.operationFailed
        var failedEnableSetting = LaunchAtLoginSettingModel(
            backend: failedEnableService.backend
        )
        let readsBeforeEnable = failedEnableService.statusReadCount
        failedEnableSetting.setEnabled(true)
        expect(
            failedEnableSetting.state == .updateFailed(isEnabled: false),
            "failed registration preserves actual disabled state"
        )
        expect(
            failedEnableService.statusReadCount > readsBeforeEnable,
            "failed registration rereads system state"
        )

        let failedDisableService = FakeLaunchAtLoginService(status: .enabled)
        failedDisableService.unregisterError = LaunchAtLoginTestError.operationFailed
        var failedDisableSetting = LaunchAtLoginSettingModel(
            backend: failedDisableService.backend
        )
        failedDisableSetting.setEnabled(false)
        expect(
            failedDisableSetting.state == .updateFailed(isEnabled: true),
            "failed unregistration preserves actual enabled state"
        )

        let migrationService = FakeLaunchAtLoginService(status: .legacyRegistered)
        migrationService.statusAfterRegister = .enabled
        let migrationSetting = LaunchAtLoginSettingModel(
            backend: migrationService.backend
        )
        expect(migrationSetting.state == .enabled, "successful legacy migration stays enabled")
        expect(migrationService.registerCallCount == 1, "legacy migration rewrites exactly once")

        let failedMigrationService = FakeLaunchAtLoginService(status: .legacyRegistered)
        failedMigrationService.registerError = LaunchAtLoginTestError.operationFailed
        let failedMigrationSetting = LaunchAtLoginSettingModel(
            backend: failedMigrationService.backend
        )
        expect(
            failedMigrationSetting.state == .updateFailed(isEnabled: true),
            "failed legacy migration preserves the actual enabled state"
        )
        expect(
            failedMigrationService.statusReadCount >= 2,
            "failed legacy migration rereads disk-backed state"
        )
    }

    private static func checkTokenConsumptionPolicy() {
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: nil,
                current: 100
            ),
            "initial token load does not animate"
        )
        expect(
            CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: 101
            ),
            "positive token growth animates"
        )
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: 100
            ),
            "unchanged token usage does not animate"
        )
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: 90
            ),
            "token reset does not animate"
        )
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: nil
            ),
            "missing token usage does not animate"
        )

        var highWater = CodexDisplayPolicy.updatedTokenConsumptionHighWater(
            previous: nil,
            current: 100
        )
        expect(highWater == 100, "initial token value establishes the high-water mark")
        highWater = CodexDisplayPolicy.updatedTokenConsumptionHighWater(
            previous: highWater,
            current: 90
        )
        expect(highWater == 100, "temporary token drop preserves the high-water mark")
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: highWater,
                current: 100
            ),
            "recovering from a temporary drop does not animate"
        )
        expect(
            CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: highWater,
                current: 101
            ),
            "surpassing the high-water mark animates"
        )
    }

    private static func checkQuotaConsumptionPace() {
        let lastReset = Date(timeIntervalSince1970: 2_000_000_000)
        let nextReset = lastReset.addingTimeInterval(100 * 60)
        let halfway = lastReset.addingTimeInterval(50 * 60)

        func assessment(usedPercent: Double) -> QuotaConsumptionPaceAssessment? {
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: usedPercent,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: halfway
            )
        }

        expect(
            assessment(usedPercent: 40)?.pace == .slow,
            "pace is slow only when the projected unused capacity is meaningful"
        )
        expect(
            assessment(usedPercent: 50)?.pace == .normal,
            "quota use close to the elapsed cycle is normal"
        )
        expect(
            assessment(usedPercent: 57.5)?.pace == .normal,
            "ample remaining capacity does not warn for a modestly fast pace"
        )
        expect(
            assessment(usedPercent: 70)?.pace == .warning,
            "low remaining capacity with insufficient runway warns"
        )
        expect(
            assessment(usedPercent: 85)?.pace == .critical,
            "very low remaining capacity with insufficient runway is critical"
        )
        expect(
            assessment(usedPercent: 57.5)?.elapsedPercent == 50,
            "pace assessment derives the last reset from duration and next reset"
        )
        expect(
            abs(
                (assessment(usedPercent: 57.5)?.relativeDifferencePercent ?? 0)
                    - 15
            ) < 0.000_001,
            "pace assessment reports the difference relative to expected use"
        )
        let shortlyAfterReset = lastReset.addingTimeInterval(1 * 60)
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 6,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: shortlyAfterReset
            )?.pace == .normal,
            "a fresh-cycle burst stays normal while 94 percent remains"
        )
        let nearReset = lastReset.addingTimeInterval(95 * 60)
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 90,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: nearReset
            )?.pace == .normal,
            "low capacity is not urgent when projected runway reaches reset"
        )
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 50,
                    windowDurationMinutes: nil,
                    resetsAt: nextReset
                ),
                now: halfway
            ) == nil,
            "pace hint stays hidden when the reset window duration is unavailable"
        )
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 50,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: nextReset
            ) == nil,
            "stale quota windows do not show a pace hint"
        )
    }

    private static func checkQuotaRemainingLevels() {
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 30.01) == .healthy,
            "remaining quota above 30 percent stays green"
        )
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 30) == .warning,
            "30 percent remaining is yellow"
        )
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 10.01) == .warning,
            "remaining quota above 10 percent stays yellow"
        )
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 10) == .critical,
            "10 percent remaining is red"
        )
    }

    private static func checkEstimatedRemainingTokens() {
        // The official example has 20K uncached + 80K cached + 5K output.
        // Rollouts express the first two together as input_tokens = 100K.
        let credits = CodexCreditRateCard.credits(
            model: "gpt-5.5", serviceTier: "default",
            inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
        )
        expect(credits == 7.25, "official credit example excludes cached input from the full input rate")
        expect(
            CodexCreditRateCard.credits(
                model: "gpt-5.5", serviceTier: "priority",
                inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
            ) == 18.125,
            "Fast multiplies all three token rates"
        )
        expect(CodexCreditRateCard.rate(for: "openai/gpt-6-astra-2026-09-01")?.input == 250,
               "dated model IDs resolve the exact documented model")
        expect(CodexCreditRateCard.rate(for: "gpt-5.3-codex-spark") == nil,
               "Spark is never assigned the Codex rate or shared quota")
        expect(CodexCreditRateCard.rate(for: "gpt-5.4-mini")?.input == 18.75,
               "mini uses its own documented rate")
        expect(CodexCreditRateCard.rate(for: "gpt-6-astra-unknown") == nil,
               "undocumented variants stay unpriced")
        expect(CodexCreditRateCard.credits(
            model: "gpt-5.5", serviceTier: "default",
            inputTokens: 100, cachedInputTokens: 101, outputTokens: 0
        ) == nil, "invalid cache counts cannot become negative credit cost")

        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let reset = now.addingTimeInterval(4 * 60 * 60)
        func quota(_ used: Double, resetAt: Date = reset) -> RateLimitBucket {
            RateLimitBucket(
                id: "codex", name: nil, planType: "pro",
                primary: RateLimitWindow(usedPercent: used, windowDurationMinutes: 300, resetsAt: resetAt),
                secondary: nil, reachedType: nil
            )
        }
        // A known 100M-token allowance: twelve 1M-token calls use 12%.
        // Calendar-day activity has no part in deriving that capacity.
        var samples: [CodexTokenCostSample] = []
        for index in 0...12 {
            let timestamp = now.addingTimeInterval(Double(index - 60))
            let count: Int64 = index == 0 ? 0 : 1_000_000
            let cost: Double? = index == 0 ? nil : 100.0
            let observed = quota(Double(index), resetAt: reset)
            let sample = CodexTokenCostSample(
                timestamp: timestamp, tokens: count, credits: cost, quota: observed
            )
            samples.append(sample)
        }
        let estimate = CodexTokenEstimator.estimate(quota: quota(12), samples: samples, now: now)
        expect(abs((estimate?.tokens ?? 0) - 88_000_000) <= 1,
               "observed quota changes recover a known capacity independently of calendar-day volume")
        expect(estimate?.sampleCount == 12 && estimate?.observedQuotaPercent == 10,
               "estimate requires multiple meaningful quota intervals")
        let pausedSamples = samples.map { sample -> CodexTokenCostSample in
            var result = sample
            result.timestamp = result.timestamp.addingTimeInterval(-1_000)
            return result
        }
        expect(abs((CodexTokenEstimator.estimate(quota: quota(12), samples: pausedSamples, now: now)?.tokens ?? 0) - 88_000_000) <= 1,
               "idle time does not reduce inferred allowance capacity")
        let fastSamples = samples.map { sample -> CodexTokenCostSample in
            var result = sample
            result.credits = sample.credits.map { $0 * 2.5 }
            return result
        }
        expect(abs((CodexTokenEstimator.estimate(quota: quota(12), samples: fastSamples, now: now)?.tokens ?? 0) - 88_000_000) <= 1,
               "continuing the observed Fast mix does not manufacture extra remaining tokens")
        expect(CodexTokenEstimator.estimate(quota: quota(12), samples: Array(samples.prefix(5)), now: now) == nil,
               "small percentage changes do not define the whole allowance")
        let unknown = samples.map { sample -> CodexTokenCostSample in
            var result = sample
            result.credits = nil
            return result
        }
        expect(CodexTokenEstimator.estimate(quota: quota(12), samples: unknown, now: now) == nil,
               "unknown model costs do not receive a guessed price")
        let newReset = reset.addingTimeInterval(300)
        let resetEstimate = CodexTokenEstimator.estimate(
            quota: quota(0, resetAt: newReset), samples: samples, now: now
        )
        expect(abs((resetEstimate?.tokens ?? 0) - 100_000_000) <= 1
               && resetEstimate?.usesHistoricalCalibration == true,
               "a reset can reuse recent calibrated capacity without carrying over old consumption")
        expect(CodexTokenEstimator.estimate(
            quota: quota(0, resetAt: newReset), samples: samples, now: now,
            historyNotBefore: now
        ) == nil, "an account change prevents borrowing the previous account's history")
        var changedCapacity = samples
        for index in 0...12 {
            changedCapacity.append(CodexTokenCostSample(
                timestamp: now.addingTimeInterval(Double(index - 30)),
                tokens: index == 0 ? 0 : 1_000_000,
                credits: index == 0 ? nil : 100.0,
                quota: quota(Double(index * 2), resetAt: newReset)
            ))
        }
        let recalibrated = CodexTokenEstimator.estimate(
            quota: quota(24, resetAt: newReset), samples: changedCapacity, now: now
        )
        expect(abs((recalibrated?.tokens ?? 0) - 38_000_000) <= 1
               && recalibrated?.usesHistoricalCalibration == false,
               "enough current-cycle data replaces older capacity without cross-reset percentage deltas")
        var otherPlan = quota(12)
        otherPlan.planType = "plus"
        expect(CodexTokenEstimator.estimate(quota: otherPlan, samples: samples, now: now) == nil,
               "plan changes invalidate the observed capacity")
        expect(CodexTokenEstimator.estimate(quota: quota(12, resetAt: now), samples: samples, now: now) == nil,
               "expired windows cannot display an estimate")
        var blocked = quota(12)
        blocked.secondary = RateLimitWindow(usedPercent: 100, windowDurationMinutes: 10_080, resetsAt: reset)
        expect(CodexTokenEstimator.estimate(quota: blocked, samples: samples, now: now)?.tokens == 0,
               "an exhausted secondary quota overrides a healthy primary quota")
        blocked.secondary?.usedPercent = 50
        expect(CodexTokenEstimator.estimate(quota: blocked, samples: samples, now: now) == nil,
               "an uncalibrated secondary constraint is not ignored")
        let constrainedSamples = samples.map { sample -> CodexTokenCostSample in
            var result = sample
            result.quota.secondary = RateLimitWindow(
                usedPercent: sample.quota.primary!.usedPercent * 2,
                windowDurationMinutes: 10_080, resetsAt: reset
            )
            return result
        }
        blocked.secondary?.usedPercent = 24
        expect(abs((CodexTokenEstimator.estimate(quota: blocked, samples: constrainedSamples, now: now)?.tokens ?? 0) - 38_000_000) <= 1,
               "the smaller calibrated allowance determines remaining tokens")
        expect(CodexTokenEstimator.estimate(quota: quota(100), samples: [], now: now)?.tokens == 0,
               "exhausted included quota reports zero even without history")
        expect(CodexTokenEstimator.estimate(quota: nil, samples: samples, now: now) == nil,
               "missing quota metadata stays unavailable")
    }

    private static func checkTokenEstimateRollouts() {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = now.addingTimeInterval(-3_600)
        let reset = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 14_400)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-priced-usage-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            CodexDailyTokenUsageReader.resetCacheForTesting()
        }
        func line(_ type: String, _ payload: JSONObject, _ date: Date = start) throws -> String {
            let object: JSONObject = [
                "type": type, "timestamp": formatter.string(from: date), "payload": payload
            ]
            return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        }
        func quota(_ used: Double) -> RateLimitBucket {
            RateLimitBucket(
                id: "codex", name: nil, planType: "pro",
                primary: RateLimitWindow(usedPercent: used, windowDurationMinutes: 300, resetsAt: reset),
                secondary: nil, reachedType: nil
            )
        }
        func token(total: Int64, last: Int64, used: Double, at date: Date) throws -> String {
            let lastUsage: JSONObject = [
                "total_tokens": last,
                "input_tokens": last * 9 / 10,
                "cached_input_tokens": last * 8 / 10,
                "output_tokens": last / 10,
                "reasoning_output_tokens": last / 20
            ]
            return try line("event_msg", [
                "type": "token_count",
                "info": [
                    "total_token_usage": ["total_tokens": total],
                    "last_token_usage": lastUsage
                ],
                "rate_limits": [
                    "limit_id": "codex", "plan_type": "pro",
                    "primary": [
                        "used_percent": used, "window_minutes": 300,
                        "resets_at": reset.timeIntervalSince1970
                    ]
                ]
            ], date)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let meta = try line("session_meta", ["source": "cli", "model_provider": "openai"])
            let settings = try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": "default"])
            var lines = [[meta, settings], [meta, settings]]
            var totals: [Int64] = [0, 0]
            for index in 0...12 {
                let slot = index % 2
                let delta: Int64 = index == 0 ? 0 : 1_000_000
                totals[slot] += delta
                let event = try token(total: totals[slot], last: delta, used: Double(index),
                                      at: start.addingTimeInterval(Double(index * 60)))
                lines[slot].append(contentsOf: [event, event])
            }
            let urls = (0...1).map { directory.appendingPathComponent("usage-\($0).jsonl") }
            for index in 0...1 {
                try Data((lines[index].joined(separator: "\n") + "\n").utf8).write(to: urls[index])
            }
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let usage = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path), now: now, calendar: calendar, quota: quota(12)
            )
            expect(abs(usage.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 816) < 0.000001,
                   "chart credits sum concurrent calls without charging duplicate notifications")
            expect(usage.chartCreditTotals.values.allSatisfy { $0.unpricedCalls == 0 },
                   "complete token breakdowns produce fully priced chart buckets")
            expect(usage.remainingTokenEstimate?.sampleCount == 12,
                   "priced usage excludes repeated token_count notifications")
            expect(abs((usage.remainingTokenEstimate?.tokens ?? 0) - 88_000_000) <= 1,
                   "concurrent rollouts combine their costs before calibrating account quota")

            let customURL = directory.appendingPathComponent("custom-provider.jsonl")
            let customMeta = try line("session_meta", ["source": "cli", "model_provider": "custom"])
            let customCall = try token(total: 100_000_000, last: 100_000_000, used: 12,
                                       at: start.addingTimeInterval(800))
            try Data(([customMeta, settings, customCall].joined(separator: "\n") + "\n").utf8).write(to: customURL)
            let customUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path) + [customURL.path], now: now.addingTimeInterval(31),
                calendar: calendar, quota: quota(12)
            )
            expect(abs((customUsage.remainingTokenEstimate?.tokens ?? 0) - 88_000_000) <= 1,
                   "third-party providers do not inflate ChatGPT allowance estimates")

            lines[0].append(try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": "priority"], start.addingTimeInterval(900)))
            totals[0] += 1_000_000
            lines[0].append(try token(total: totals[0], last: 1_000_000, used: 14.5, at: start.addingTimeInterval(901)))
            lines[0].append(try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": NSNull()], start.addingTimeInterval(960)))
            totals[0] += 1_000_000
            lines[0].append(try token(total: totals[0], last: 1_000_000, used: 15.5, at: start.addingTimeInterval(961)))
            let handle = try FileHandle(forWritingTo: urls[0])
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((lines[0].suffix(4).joined(separator: "\n") + "\n").utf8))
            try handle.close()
            let resumed = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path), now: now.addingTimeInterval(32), calendar: calendar,
                quota: quota(15.5)
            )
            expect(resumed.billedDailyBuckets.reduce(Int64(0)) { $0 + $1.tokens } == 15_500_000,
                   "explicit null service tier clears a previously recorded Fast setting")
            expect(abs(resumed.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 1054) < 0.000001,
                   "incremental chart credits retain Standard calls and apply Fast only to new calls")
            expect(abs(resumed.chartCreditTotals.values.reduce(0) { $0 + $1.standardCredits } - 952) < 0.000001,
                   "credit chart Standard prices every call without its Fast multiplier")
            expect(abs(resumed.chartCreditTotals.values.reduce(0) { $0 + $1.wastedCredits } - 102) < 0.000001,
                   "credit chart Wasted includes only the extra Fast cost")
            expect(resumed.remainingTokenEstimate?.sampleCount == 14,
                   "incremental scans retain history and price each new call once")
            expect((resumed.remainingTokenEstimate?.tokens ?? Int64.max) < 84_500_000,
                   "recent Fast usage increases future cost instead of assuming every session becomes Standard")
            let apiUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path), now: now.addingTimeInterval(33), calendar: calendar,
                usesChatGPTCredits: false, quota: quota(15.5)
            )
            expect(apiUsage.chartCreditTotals.values.contains { $0.unpricedCalls > 0 },
                   "non-ChatGPT chart usage cannot silently display zero credits")
            expect(apiUsage.remainingTokenEstimate == nil,
                   "API-key usage cannot calibrate ChatGPT included allowance")
            let historyURL = directory.appendingPathComponent("chart-history.jsonl")
            let old = start.addingTimeInterval(-10 * 86_400)
            let oldSettings = try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": "default"], old)
            let first = try token(total: 1_000_000, last: 1_000_000, used: 1, at: old)
            let newSettings = try line("turn_context", ["model": "gpt-6-astra", "service_tier": "priority"])
            let second = try token(total: 2_000_000, last: 1_000_000, used: 2, at: start)
            let oldMeta = try line("session_meta", ["source": "cli", "model_provider": "openai"], old)
            try Data(([oldMeta, oldSettings, first, newSettings, second].joined(separator: "\n") + "\n").utf8).write(to: historyURL)
            let history = try CodexDailyTokenUsageReader.readRecentHours(
                from: [historyURL.path], now: now, calendar: calendar
            )
            let oldHour = calendar.dateInterval(of: .hour, for: old)!.start
            let newHour = calendar.dateInterval(of: .hour, for: start)!.start
            expect(history.chartCreditTotals[oldHour]?.credits == 68,
                   "30-day chart retains priced calls older than estimator history")
            expect(history.chartCreditTotals[newHour]?.standardCredits == 170
                   && history.chartCreditTotals[newHour]?.wastedCredits == 255,
                   "Astra Fast splits into Standard 170 plus extra 255 credits")
            expect(history.chartCreditTotals[newHour]?.credits == 425,
                   "switching models in one rollout prices each hour with its recorded model")
            expect(history.chartCreditTotals[newHour]?.displayText(matching: 1_000_001) == "425.0 credits",
                   "historical credits use local logs even when account history includes another computer")

        } catch {
            expect(false, "priced rollout estimates: \(error.localizedDescription)")
        }
    }

    private static func checkFastModeUsageMultipliers() {
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-5.4") == 2.0,
            "GPT-5.4 Fast usage counts as 2x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: " openai/GPT-5.4-codex ") == 2.0,
            "GPT-5.4 family matching handles provider prefixes, suffixes, and case"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-5.5") == 2.5,
            "GPT-5.5 Fast usage counts as 2.5x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-5.6-sol") == 2.5,
            "GPT-5.6 variants count as 2.5x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-6-astra") == 2.5,
            "GPT-6 Astra Fast usage counts as 2.5x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: " openai/GPT-6-ASTRA ") == 2.5,
            "GPT-6 Astra matching handles provider prefixes, whitespace, and case"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-6-astra2") == nil,
            "Astra support does not match unrelated model names"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-6-future") == nil,
            "Astra support does not assign a multiplier to every GPT-6 model"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "future-model") == nil,
            "models outside the official Fast support list are not guessed"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: nil) == nil,
            "missing models are not assigned a guessed multiplier"
        )
    }

    private static func checkDisplayModelNames() {
        expect(
            CodexDisplayPolicy.displayModelName("openai/gpt-5.6-sol") == "5.6-Sol",
            "model display removes provider and GPT prefixes"
        )
        expect(
            CodexDisplayPolicy.displayModelName("GPT-5.5") == "5.5",
            "model display removes the GPT prefix case-insensitively"
        )
        expect(
            CodexDisplayPolicy.displayModelName("o3") == "O3",
            "non-GPT model names preserve their compact family name"
        )
        expect(
            CodexDisplayPolicy.displayModelName(" gpt ") == "gpt",
            "a bare GPT family name remains non-empty after trimming"
        )
    }

    private static func checkReasoningEffortLabels() {
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("low") == "low",
            "low reasoning uses the lowercase low label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("minimal") == "low",
            "legacy minimal reasoning is folded into low"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("medium") == "medium",
            "medium reasoning keeps its full label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("high") == "high",
            "high reasoning keeps its full label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("extra high") == "xhigh",
            "Extra High is the only abbreviated effort label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("xhigh") == "xhigh",
            "the runtime xhigh value uses the Codex App spelling"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("max") == "max",
            "max reasoning keeps its full label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("ultra") == "ultra",
            "ultra reasoning keeps its full label"
        )
    }

    private static func checkHeaderTokenCounts() {
        expect(
            CodexDisplayPolicy.headerTokenCount(51_850) == "51.9K",
            "expanded header keeps one decimal for two-digit thousands"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(123_456) == "123K",
            "expanded header omits decimals for three-digit thousands"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(14_123_000_000) == "14.1B",
            "expanded header keeps one decimal for two-digit billions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(123_456_789) == "123M",
            "expanded header omits decimals for three-digit millions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(987_654_321_000) == "988B",
            "expanded header omits decimals for three-digit billions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(123_456_789_012_345) == "123T",
            "expanded header omits decimals for three-digit trillions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(99_960_000) == "100M",
            "expanded header avoids rendering a rounded three-digit million with a decimal"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(999_500_000) == "1.0B",
            "expanded header promotes three-digit millions that round into billions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(999_950) == "1.0M",
            "expanded header promotes values that round into the next unit"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(999) == "999",
            "expanded header keeps unscaled values exact"
        )
    }

    private static func checkThreadDeepLinks() {
        let threadID = "019f1234-5678-7abc-8def-0123456789ab"
        expect(
            CodexLauncher.settingsURL?.absoluteString == "codex://settings",
            "settings deep link uses Codex's canonical route"
        )
        expect(
            CodexLauncher.threadURL(threadID: threadID)?.absoluteString
                == "codex://threads/\(threadID)",
            "thread deep link uses Codex's canonical local-task route"
        )
        expect(
            CodexLauncher.threadURL(threadID: "  \n") == nil,
            "blank thread IDs do not produce deep links"
        )
        expect(
            CodexLauncher.threadURL(threadID: "fallback-0123456789abcdef") == nil,
            "synthetic UI identities do not produce invalid Codex deep links"
        )
    }

    private static func checkRateLimitsAndResetCredits() {
        let result: JSONObject = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 24.5,
                    "windowDurationMins": 300,
                    "resetsAt": 2_000_000_000
                ],
                "secondary": [
                    "usedPercent": 41,
                    "windowDurationMins": 10_080,
                    "resetsAt": 2_000_100_000
                ]
            ],
            "rateLimitResetCredits": [
                "availableCount": 3,
                "credits": [
                    [
                        "status": "available",
                        "expiresAt": 2_000_200_000
                    ],
                    [
                        "status": "available",
                        "expiresAt": 2_000_150_000
                    ],
                    [
                        "status": "used",
                        "expiresAt": 2_000_100_000
                    ]
                ]
            ]
        ]

        let parsed = CodexStatusPayloadParser.parseRateLimits(result)
        expect(parsed.bucket?.primary?.usedPercent == 24.5, "primary used percent")
        expect(parsed.bucket?.primary?.remainingPercent == 75.5, "primary remaining percent")
        expect(parsed.bucket?.secondary?.windowDurationMinutes == 10_080, "secondary window")
        expect(parsed.resetCredits?.availableCount == 3, "authoritative reset count")
        expect(
            parsed.resetCredits?.earliestExpiration?.timeIntervalSince1970 == 2_000_150_000,
            "earliest reset expiration"
        )
        expect(
            parsed.resetCredits?.expirationDates.map(\.timeIntervalSince1970)
                == [2_000_150_000, 2_000_200_000],
            "available reset expirations are filtered and sorted"
        )

        let legacyCredits = CodexStatusPayloadParser.parseRateLimits([
            "rateLimitResetCredits": [
                "credits": [
                    ["status": " AVAILABLE ", "expiresAt": 2_000_300_000],
                    ["status": "used", "expiresAt": 2_000_100_000],
                    ["expiresAt": 2_000_250_000],
                    ["status": "available"],
                    ["status": "unknown", "expiresAt": 2_000_050_000]
                ]
            ]
        ]).resetCredits
        expect(legacyCredits?.availableCount == 3, "legacy reset count includes only available rows")
        expect(
            legacyCredits?.expirationDates.map(\.timeIntervalSince1970)
                == [2_000_250_000, 2_000_300_000],
            "reset parser normalizes status and retains rows with missing expiry"
        )

        let invalidCount = CodexStatusPayloadParser.parseRateLimits([
            "rateLimitResetCredits": ["availableCount": -4, "credits": []]
        ]).resetCredits
        expect(invalidCount?.availableCount == 0, "negative reset count is clamped to zero")
    }

    private static func checkResetCreditExpiryWarning() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let week = CodexDisplayPolicy.resetCreditExpiryWarningInterval

        func summary(
            availableCount: Int = 1,
            expirations: [TimeInterval]
        ) -> ResetCreditSummary {
            ResetCreditSummary(
                availableCount: availableCount,
                earliestExpiration: expirations.min().map {
                    Date(timeIntervalSince1970: $0)
                },
                expirationDates: expirations.map {
                    Date(timeIntervalSince1970: $0)
                }
            )
        }

        expect(
            CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970 + week]),
                now: now
            ),
            "reset credit expiring exactly seven days out warns"
        )
        expect(
            CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970]),
                now: now
            ),
            "reset credit expiring now warns"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970 + week + 1]),
                now: now
            ),
            "reset credit beyond seven days stays normal"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970 - 1]),
                now: now
            ),
            "expired reset credit does not warn"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(availableCount: 0, expirations: [now.timeIntervalSince1970 + 60]),
                now: now
            ),
            "zero available reset credits do not warn"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: []),
                now: now
            ),
            "missing reset expiration dates stay normal"
        )
    }

    private static func checkCodexBucketPreference() {
        let result: JSONObject = [
            "rateLimits": ["primary": ["usedPercent": 90]],
            "rateLimitsByLimitId": [
                "other": ["primary": ["usedPercent": 10]],
                "codex": ["primary": ["usedPercent": 35]]
            ]
        ]

        let parsed = CodexStatusPayloadParser.parseRateLimits(result)
        expect(parsed.bucket?.primary?.usedPercent == 35, "prefer the codex rate-limit bucket")
    }

    private static func checkAccountUsageThreadAndModel() {
        let account = CodexStatusPayloadParser.parseAccount([
            "account": ["type": "chatgpt", "email": "hello@example.com", "planType": "pro"]
        ])
        let usage = CodexStatusPayloadParser.parseUsage([
            "summary": ["lifetimeTokens": 1_234_567, "currentStreakDays": 7],
            "dailyUsageBuckets": [
                ["startDate": "2026-07-14", "tokens": 42],
                ["tokens": 99],
                ["startDate": "2026-07-12", "tokens": 12],
                ["startDate": "2026-07-13", "tokens": -5]
            ]
        ])
        let usageWithoutSummary = CodexStatusPayloadParser.parseUsage([
            "dailyUsageBuckets": [["startDate": "2026-07-14", "tokens": 7]]
        ])
        let thread = CodexStatusPayloadParser.parseLatestThread([
            "data": [[
                "id": "thread-1",
                "name": "实现顶部状态岛",
                "status": ["type": "notLoaded"],
                "path": "/Users/test/.codex/sessions/rollout-thread-1.jsonl",
                "updatedAt": 2_000_000_000
            ]]
        ])
        let model = CodexStatusPayloadParser.parseDefaultModel([
            "data": [["id": "gpt-5.6-sol", "displayName": "GPT-5.6 Sol", "isDefault": true]]
        ])

        expect(account.planType == "pro", "account plan")
        expect(usage.lifetimeTokens == 1_234_567, "lifetime tokens")
        expect(usage.currentStreakDays == 7, "usage streak")
        expect(
            usage.dailyUsageBuckets.map(\.startDate)
                == ["2026-07-12", "2026-07-13", "2026-07-14"],
            "daily usage buckets are validated and sorted"
        )
        expect(usage.dailyUsageBuckets[1].tokens == 0, "negative daily usage is clamped")
        expect(
            usageWithoutSummary.dailyUsageBuckets.first?.tokens == 7,
            "daily usage survives a missing summary"
        )
        expect(thread?.title == "实现顶部状态岛", "thread title")
        expect(thread?.status == "notLoaded", "thread status")
        expect(thread?.rolloutPath?.hasSuffix("rollout-thread-1.jsonl") == true, "thread rollout path")
        expect(model?.id == "gpt-5.6-sol", "default model")
    }

    private static func checkUsageTimeline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
        )!
        let timeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [
                DailyUsageBucket(startDate: "2026-07-15", tokens: 5),
                DailyUsageBucket(startDate: "2026-07-14", tokens: 140),
                DailyUsageBucket(startDate: "2026-07-12", tokens: 120),
                DailyUsageBucket(startDate: "2026-07-12", tokens: 3)
            ],
            todayTokens: 150,
            localDailyBuckets: [
                DailyUsageBucket(startDate: "2026-07-14", tokens: 150),
                DailyUsageBucket(startDate: "2026-07-13", tokens: 80)
            ],
            count: 5,
            now: now,
            calendar: calendar
        )

        expect(timeline.count == 5, "usage timeline has one entry per calendar day")
        expect(timeline.first?.startDate == "2026-07-11", "usage timeline starts four days ago")
        expect(timeline.last?.startDate == "2026-07-15", "usage timeline ends today")
        expect(
            timeline[2].tokens == 80,
            "local daily history fills an account date that is missing"
        )
        expect(timeline[1].tokens == 123, "duplicate usage dates are combined")
        expect(
            timeline[3].tokens == 150,
            "local hourly usage keeps yesterday visible while account data lags"
        )
        expect(
            timeline.last?.tokens == 150,
            "local real-time usage replaces a delayed account bucket for today"
        )

        let accountAheadTimeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [DailyUsageBucket(startDate: "2026-07-14", tokens: 175)],
            localDailyBuckets: [
                DailyUsageBucket(startDate: "2026-07-14", tokens: 150)
            ],
            count: 2,
            now: now,
            calendar: calendar
        )
        expect(
            accountAheadTimeline.first?.tokens == 175,
            "yesterday uses the larger account total without double counting"
        )

        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let newYearNow = shanghaiCalendar.date(
            from: DateComponents(year: 2026, month: 1, day: 2, hour: 12)
        )!
        let newYearTimeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [],
            count: 3,
            now: newYearNow,
            calendar: shanghaiCalendar
        )
        expect(
            newYearTimeline.map(\.startDate)
                == ["2025-12-31", "2026-01-01", "2026-01-02"],
            "usage timeline crosses month and year boundaries"
        )

        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let daylightSavingNow = losAngelesCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)
        )!
        let daylightSavingTimeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [],
            count: 5,
            now: daylightSavingNow,
            calendar: losAngelesCalendar
        )
        expect(
            daylightSavingTimeline.map(\.startDate)
                == ["2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"],
            "usage timeline keeps calendar-day continuity across daylight saving time"
        )
    }

    private static func checkThreadRuntimeSettings() {
        let threadID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(threadID).jsonl")
        let older = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.5","reasoning_effort":"high","service_tier":"priority"}}}"#
        let newer = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-sol","reasoning_effort":"ultra","service_tier":"default"}}}"#
        let context = #"{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"ultra"}}"#
        let filler = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "x", count: 70_000))\"}}"

        do {
            try ([older, newer, context, filler].joined(separator: "\n") + "\n")
                .data(using: .utf8)?
                .write(to: url)
            let settings = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
            expect(settings?.model == "gpt-5.6-sol", "thread model from latest settings event")
            expect(settings?.reasoningEffort == "ultra", "thread reasoning effort")
            expect(settings?.serviceTier == "default", "thread service tier")

            let appended = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.7","reasoning_effort":"high","service_tier":"priority"}}}"# + "\n"
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(appended.utf8))
            try handle.close()

            let refreshed = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
            expect(refreshed?.model == "gpt-5.7", "thread settings cache refreshes after append")
            expect(refreshed?.reasoningEffort == "high", "refreshed reasoning effort")
            expect(refreshed?.serviceTier == "priority", "refreshed fast service tier")

            let largeAppend = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "y", count: 70_000))\"}}\n"
            let largeAppendHandle = try FileHandle(forWritingTo: url)
            try largeAppendHandle.seekToEnd()
            try largeAppendHandle.write(contentsOf: Data(largeAppend.utf8))
            try largeAppendHandle.close()
            _ = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )

            let contextOnly = #"{"type":"turn_context","payload":{"model":"gpt-5.7","effort":"max"}}"# + "\n"
            let contextHandle = try FileHandle(forWritingTo: url)
            try contextHandle.seekToEnd()
            try contextHandle.write(contentsOf: Data(contextOnly.utf8))
            try contextHandle.close()

            let contextRefreshed = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
            expect(contextRefreshed?.reasoningEffort == "max", "new turn context updates effort")
            expect(
                contextRefreshed?.serviceTier == "priority",
                "turn context append preserves recorded Fast tier"
            )
        } catch {
            expect(false, "thread settings reader: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: url)

        let tuiThreadID = UUID().uuidString
        let tuiURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(tuiThreadID).jsonl")
        let tuiContext = #"{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"max"}}"#
        do {
            try (tuiContext + "\n").data(using: .utf8)?.write(to: tuiURL)
            let settings = try CodexThreadSettingsReader.readLatest(
                from: tuiURL.path,
                threadID: tuiThreadID,
                validatePath: false
            )
            expect(settings?.model == "gpt-5.6-sol", "TUI fallback model")
            expect(settings?.reasoningEffort == "max", "TUI fallback reasoning effort")
            expect(settings?.serviceTier == nil, "missing TUI service tier stays unknown")
        } catch {
            expect(false, "TUI settings fallback: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: tuiURL)
    }

    private static func checkEffectiveServiceTier() {
        let fast = CodexStatusPayloadParser.parseEffectiveServiceTier([
            "config": ["service_tier": "priority"]
        ])
        expect(fast == "priority", "effective Fast service tier")

        let standard = CodexStatusPayloadParser.parseEffectiveServiceTier([
            "config": [:]
        ])
        expect(standard == "default", "missing service tier means Standard")

        let featureDisabled = CodexStatusPayloadParser.parseEffectiveServiceTier([
            "config": [
                "service_tier": "priority",
                "features": ["fast_mode": false]
            ]
        ])
        expect(featureDisabled == "default", "disabled Fast feature means Standard")
        expect(
            CodexStatusPayloadParser.parseEffectiveServiceTier([:]) == nil,
            "invalid config response stays unknown"
        )
    }

    private static func checkThreadActivityStates() {
        let threadID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(threadID).jsonl")

        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }

        func snapshot() throws -> ThreadActivitySnapshot {
            try CodexThreadActivityReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
        }

        func state() throws -> ThreadExecutionState {
            try snapshot().executionState
        }

        func expectState(_ expected: ThreadExecutionState, _ message: String) throws {
            let actual = try state()
            expect(actual == expected, message)
        }

        do {
            try Data().write(to: url)
            try expectState(.unknown, "empty rollout activity is unknown")

            let start1 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"# + "\n"
            try append(start1)
            try expectState(.running, "task_started becomes running")

            let inputRequest = #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"input-1"}}"# + "\n"
            try append(inputRequest)
            try expectState(.waitingForInput, "request_user_input waits for input")

            let waitingAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let waitingModifiedAt = waitingAttributes[.modificationDate] as? Date ?? Date()
            let longPendingApproval = try CodexThreadActivityReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false,
                now: waitingModifiedAt.addingTimeInterval(24 * 60 * 60),
                staleInterval: 30 * 60
            )
            expect(
                longPendingApproval.executionState == .waitingForInput,
                "waiting for input does not expire while approval is pending"
            )

            let inputResponse = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"input-1","output":"ok"}}"# + "\n"
            try append(inputResponse)
            try expectState(.running, "request_user_input response resumes running")

            let token1 = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2929630,"cached_input_tokens":2806528,"output_tokens":19878,"reasoning_output_tokens":2428,"total_tokens":2949508},"last_token_usage":{"input_tokens":93600,"cached_input_tokens":90000,"output_tokens":1400,"reasoning_output_tokens":300,"total_tokens":95000},"model_context_window":258400}}}"# + "\n"
            try append(token1)
            let usage1 = try snapshot().tokenUsage
            expect(usage1?.inputTokens == 2_929_630, "cumulative input token count")
            expect(usage1?.cachedInputTokens == 2_806_528, "cumulative cached token count")
            expect(usage1?.outputTokens == 19_878, "cumulative output token count")
            expect(usage1?.reasoningOutputTokens == 2_428, "cumulative reasoning token count")
            expect(usage1?.totalTokens == 2_949_508, "cumulative total token count")
            expect(usage1?.contextTokensUsed == 95_000, "current context token count")
            expect(usage1?.contextWindowTokens == 258_400, "model context window")

            let filler = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "x", count: 70_000))\"}}\n"
            try append(filler)
            try expectState(.running, "large unrelated append preserves running")

            let complete1 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#
            let splitIndex = complete1.index(complete1.startIndex, offsetBy: complete1.count / 2)
            try append(String(complete1[..<splitIndex]))
            try expectState(.running, "partial lifecycle line keeps prior state")
            try append(String(complete1[splitIndex...]) + "\n")
            try expectState(.idle, "completed partial line becomes idle")

            let token2 = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000000,"cached_input_tokens":2850000,"output_tokens":25000,"reasoning_output_tokens":3000,"total_tokens":3025000}}}}"# + "\n"
            try append(token2)
            let usage2 = try snapshot().tokenUsage
            expect(
                usage2?.totalTokens == 3_025_000,
                "appended token_count refreshes cumulative total"
            )

            let start2 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"# + "\n"
            let abort2 = #"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-2","reason":"interrupted"}}"# + "\n"
            try append(start2 + abort2)
            try expectState(.interrupted, "turn_aborted becomes interrupted")

            let start3 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-3"}}"# + "\n"
            let failure = #"{"type":"event_msg","payload":{"type":"error","codex_error_info":"unauthorized"}}"# + "\n"
            let complete3 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-3"}}"# + "\n"
            try append(start3 + failure + complete3)
            try expectState(.failed, "fatal turn error survives task_complete")

            let start4 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-4"}}"# + "\n"
            let delayedOldComplete = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-old"}}"# + "\n"
            try append(start4 + delayedOldComplete)
            try expectState(.running, "old turn completion does not stop active turn")

            let complete4 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-4"}}"# + "\n"
            try append(complete4)
            try expectState(.idle, "matching completion stops active turn")

            let start5 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-5"}}"# + "\n"
            try append(start5)
            try expectState(.running, "large partial terminal fixture starts running")

            let hugeCompletePrefix =
                #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-5","details":""#
                + String(repeating: "q", count: 140_000)
            try append(hugeCompletePrefix)
            try expectState(.running, "incomplete terminal record keeps prior state")
            try append(#""}}"# + "\n")
            try expectState(
                .idle,
                "terminal record split across polls by more than 64 KiB is not lost"
            )
        } catch {
            expect(false, "thread activity reader: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: url)

        let initialThreadID = UUID().uuidString
        let initialURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(initialThreadID).jsonl")
        let oldOrphan = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"old-orphan"}}"#
        let previousTokenCount = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120000,"cached_input_tokens":100000,"output_tokens":4000,"reasoning_output_tokens":1000,"total_tokens":124000}}}}"#
        let latestStart = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"latest"}}"#
        let oldCompletion = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"old-orphan"}}"#
        let largeTail = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "z", count: 140_000))\"}}"
        do {
            try ([oldOrphan, previousTokenCount, latestStart, oldCompletion, largeTail].joined(separator: "\n") + "\n")
                .data(using: .utf8)?
                .write(to: initialURL)
            let initial = try CodexThreadActivityReader.readLatest(
                from: initialURL.path,
                threadID: initialThreadID,
                validatePath: false
            )
            expect(
                initial.executionState == .running,
                "initial backwards scan ignores delayed completion for older turn"
            )
            expect(
                initial.tokenUsage?.totalTokens == 124_000,
                "initial backwards scan recovers latest cumulative tokens before a new turn"
            )
        } catch {
            expect(false, "initial thread activity scan: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: initialURL)

        let staleThreadID = UUID().uuidString
        let staleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(staleThreadID).jsonl")
        let startedAt = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: startedAt)
        let staleStart =
            #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"stale-turn"}}"#
            + "\n"
        do {
            try Data(staleStart.utf8).write(to: staleURL)
            try FileManager.default.setAttributes(
                [.modificationDate: startedAt.addingTimeInterval(-3_600)],
                ofItemAtPath: staleURL.path
            )

            let fresh = try CodexThreadActivityReader.readLatest(
                from: staleURL.path,
                threadID: staleThreadID,
                validatePath: false,
                now: startedAt.addingTimeInterval(20 * 60),
                staleInterval: 30 * 60
            )
            expect(
                fresh.executionState == .running,
                "fresh lifecycle timestamp keeps an unmatched start running"
            )

            let stale = try CodexThreadActivityReader.readLatest(
                from: staleURL.path,
                threadID: staleThreadID,
                validatePath: false,
                now: startedAt.addingTimeInterval(31 * 60),
                staleInterval: 30 * 60
            )
            expect(
                stale.executionState == .unknown,
                "cached unmatched start ages from running to unknown"
            )
        } catch {
            expect(false, "stale thread activity guard: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: staleURL)
    }

    private static func checkThreadCreditUsage() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-credit-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        func line(_ object: JSONObject) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
        }
        func settings(_ model: String, tier: Any? = "default") throws -> String {
            var payload: JSONObject = ["model": model]
            if let tier { payload["service_tier"] = tier }
            return try line(["type": "turn_context", "payload": payload])
        }
        func count(input: Int64, cache: Int64, output: Int64) -> JSONObject {
            ["input_tokens": input, "cached_input_tokens": cache,
             "output_tokens": output, "reasoning_output_tokens": output / 2,
             "total_tokens": input + output]
        }
        let officialCounts = count(input: 100_000, cache: 80_000, output: 5_000)
        func token(_ total: JSONObject, last: JSONObject?) throws -> String {
            var info: JSONObject = ["total_token_usage": total]
            if let last { info["last_token_usage"] = last }
            return try line(["type": "event_msg", "payload": ["type": "token_count", "info": info]])
        }
        func write(_ content: String, to url: URL) throws {
            try Data(content.utf8).write(to: url, options: .atomic)
        }
        func append(_ content: String, to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(content.utf8))
        }
        func estimate(_ url: URL) throws -> CodexThreadCreditEstimate? {
            guard let usage = try CodexThreadActivityReader.readLatest(
                from: url.path, validatePath: false
            ).tokenUsage else { return nil }
            return try CodexThreadCreditUsageReader.estimate(
                from: url.path, matching: usage, validatePath: false
            )
        }
        func expectCredits(_ value: CodexThreadCreditEstimate?, _ expected: Double, _ message: String) {
            expect(value.map { abs($0.credits - expected) < 0.000_001 } == true, message)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("mixed.jsonl")
            let official = try token(officialCounts, last: officialCounts)
            try write(settings("gpt-5.5") + official, to: url)
            expectCredits(try estimate(url), 7.25, "thread credits match the official 7.25 example without charging reasoning twice")
            try append(official, to: url)
            expectCredits(try estimate(url), 7.25, "duplicate token notifications do not increase credits")

            let astraCall = count(input: 10_000, cache: 8_000, output: 1_000)
            let afterAstra = count(input: 110_000, cache: 88_000, output: 6_000)
            try append(settings("gpt-6-astra", tier: "priority") + token(afterAstra, last: astraCall), to: url)
            expectCredits(try estimate(url), 12.125, "model changes and Fast apply only to their own calls")
            let afterSol = count(input: 120_000, cache: 96_000, output: 7_000)
            try append(settings("gpt-5.6-sol", tier: NSNull()) + token(afterSol, last: astraCall), to: url)
            expectCredits(try estimate(url), 12.905, "explicit null returns to Standard without repricing past Fast calls")

            let hugeResponse = try line(["type": "response_item", "payload": ["text": String(repeating: "x", count: 1_100_000)]])
            let afterAnotherSol = count(input: 130_000, cache: 104_000, output: 8_000)
            let next = try token(afterAnotherSol, last: astraCall)
            try append(hugeResponse + String(next.prefix(next.count / 2)), to: url)
            expectCredits(try estimate(url), 12.905, "large tool output and an incomplete token line preserve prior credits")
            try append(String(next.dropFirst(next.count / 2)), to: url)
            expectCredits(try estimate(url), 13.685, "completed appended token lines are charged once")

            let afterUnknown = count(input: 140_000, cache: 112_000, output: 9_000)
            try append(settings("unknown-model") + token(afterUnknown, last: astraCall), to: url)
            let unknownEstimate = try estimate(url)
            expect(unknownEstimate == nil, "unknown model cost is not shown as a complete total")
            try append(settings("gpt-5.5") + official, to: url)
            expectCredits(try estimate(url), 7.25, "counter resets keep credits aligned with the displayed token total")

            try write(settings("gpt-5.5", tier: "priority") + official, to: url)
            expectCredits(try estimate(url), 18.125, "file replacement invalidates the credit cache")
            let standardURL = directory.appendingPathComponent("standard.jsonl")
            try write(settings("gpt-5.5", tier: nil) + official, to: standardURL)
            let standard = try estimate(standardURL)
            expectCredits(standard, 7.25, "separate sessions retain independent Fast settings")
            expect(standard?.assumesStandardTier == true, "missing tier is disclosed as a Standard assumption")

            let jumpURL = directory.appendingPathComponent("jump.jsonl")
            try write(settings("gpt-5.5") + token(afterAstra, last: astraCall), to: jumpURL)
            let jumpEstimate = try estimate(jumpURL)
            expect(jumpEstimate == nil, "unattributed inherited usage is not priced using the latest model")
            try write(settings("gpt-5.5") + token(officialCounts, last: nil), to: jumpURL)
            let missingEstimate = try estimate(jumpURL)
            expect(missingEstimate == nil, "missing per-call details do not fabricate historical pricing")
            let customMeta = try line(["type": "session_meta", "payload": ["model_provider": "custom"]])
            try write(customMeta + settings("gpt-5.5") + official, to: jumpURL)
            let customEstimate = try estimate(jumpURL)
            expect(customEstimate == nil, "custom provider does not inherit OpenAI credit prices")
            try write(settings("gpt-5.5", tier: "flex") + official, to: jumpURL)
            let flexEstimate = try estimate(jumpURL)
            expect(flexEstimate == nil, "unlisted service tiers do not inherit Standard pricing")

            let screenshotURL = directory.appendingPathComponent("screenshot.jsonl")
            let screenshotCounts = count(input: 1_266_278, cache: 1_199_104, output: 6_717)
            try write(settings("gpt-6-astra") + token(screenshotCounts, last: screenshotCounts), to: screenshotURL)
            let screenshot = try estimate(screenshotURL)
            expectCredits(screenshot, 55.16735, "user screenshot tokens cost 55.16735 Astra Standard credits")
            expect(screenshot?.displayText == "55.2 credits", "credit label rounds only the final sum")
            let mismatched = ThreadTokenUsage(inputTokens: 1, cachedInputTokens: 0, outputTokens: 0,
                                             reasoningOutputTokens: 0, totalTokens: 1)
            let stale = try CodexThreadCreditUsageReader.estimate(
                from: screenshotURL.path, matching: mismatched, validatePath: false
            )
            expect(stale == nil, "credits from a newer scan cannot be paired with an older token snapshot")
            expect(CodexThreadCreditEstimate(credits: 0.001).displayText == "<0.1 credits", "small positive costs do not round to zero")
        } catch {
            expect(false, "thread credit usage: \(error.localizedDescription)")
        }
    }

    private static func checkDailyTokenUsage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let dayStart = calendar.startOfDay(for: Date())
        let now = calendar.date(byAdding: .hour, value: 12, to: dayStart)!
        let beforeMidnight = calendar.date(byAdding: .minute, value: -1, to: dayStart)!
        let afterMidnight = calendar.date(byAdding: .minute, value: 1, to: dayStart)!
        let laterToday = calendar.date(byAdding: .minute, value: 2, to: dayStart)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-daily-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        func sessionMeta(
            forked: Bool = false,
            startedAt: Date? = nil,
            subagent: Bool = false,
            modelProvider: String? = "openai"
        ) -> String {
            let forkField = forked ? ",\"forked_from_id\":\"parent\"" : ""
            let providerField = modelProvider.map {
                ",\"model_provider\":\"\($0)\""
            } ?? ""
            let sourceFields = subagent
                ? "\"source\":{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"parent\"}}},\"thread_source\":\"subagent\""
                : "\"source\":\"cli\",\"thread_source\":\"user\""
            return "{\"timestamp\":\"\(formatter.string(from: startedAt ?? afterMidnight))\",\"type\":\"session_meta\",\"payload\":{\"id\":\"test\",\(sourceFields)\(providerField)\(forkField)}}"
        }

        func token(_ date: Date, total: Int64, last: Int64?) -> String {
            let lastField = last.map {
                ",\"last_token_usage\":{\"total_tokens\":\($0)}"
            } ?? ""
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)}\(lastField)}}}"
        }

        func runtimeFields(
            model: String?,
            modelProviderID: String? = nil,
            serviceTier: String?
        ) -> String {
            [
                model.map { "\"model\":\"\($0)\"" },
                modelProviderID.map { "\"model_provider_id\":\"\($0)\"" },
                serviceTier.map { "\"service_tier\":\"\($0)\"" }
            ]
            .compactMap { $0 }
            .joined(separator: ",")
        }

        func threadSettings(
            _ date: Date,
            model: String? = nil,
            modelProviderID: String? = nil,
            serviceTier: String? = nil
        ) -> String {
            let fields = runtimeFields(
                model: model,
                modelProviderID: modelProviderID,
                serviceTier: serviceTier
            )
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"thread_settings_applied\",\"thread_settings\":{\(fields)}}}"
        }

        func turnContext(
            _ date: Date,
            model: String? = nil,
            serviceTier: String? = nil
        ) -> String {
            let fields = runtimeFields(model: model, serviceTier: serviceTier)
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"turn_context\",\"payload\":{\(fields)}}"
        }

        func serviceTier(_ date: Date, _ value: String) -> String {
            threadSettings(date, serviceTier: value)
        }

        func subagentBoundary(_ date: Date) -> String {
            "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"inter_agent_communication_metadata\",\"payload\":{}}"
        }

        func write(_ lines: [String], name: String) -> URL {
            let url = directory.appendingPathComponent(name)
            try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
            try? FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: url.path
            )
            return url
        }

        func appendLines(_ lines: [String], to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(
                contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8)
            )
        }

        func hourlyTokens(
            _ buckets: [HourlyUsageBucket],
            containing date: Date
        ) -> Int64? {
            guard let hourStart = calendar.dateInterval(
                of: .hour,
                for: date
            )?.start else {
                return nil
            }
            return buckets.first { $0.hourStart == hourStart }?.tokens
        }

        func dailyTokens(
            _ buckets: [DailyUsageBucket],
            containing date: Date
        ) -> Int64? {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.calendar = calendar
            dateFormatter.timeZone = calendar.timeZone
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateLabel = dateFormatter.string(from: date)
            return buckets.first { $0.startDate == dateLabel }?.tokens
        }

        do {
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let normal = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 100, last: 100),
                    token(laterToday, total: 160, last: 60),
                    token(laterToday.addingTimeInterval(1), total: 160, last: 12),
                    token(laterToday.addingTimeInterval(2), total: 220, last: 60)
                ],
                name: "normal.jsonl"
            )
            let value = try CodexDailyTokenUsageReader.readToday(
                from: [normal.path],
                now: now,
                calendar: calendar
            )
            expect(value == 220, "daily tokens count each new message and ignore replayed last usage")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let weighted = write(
                [
                    sessionMeta(),
                    serviceTier(afterMidnight, "default"),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100),
                    serviceTier(afterMidnight.addingTimeInterval(2), "priority"),
                    token(afterMidnight.addingTimeInterval(3), total: 200, last: 100),
                    token(afterMidnight.addingTimeInterval(4), total: 200, last: 100),
                    serviceTier(afterMidnight.addingTimeInterval(5), "default"),
                    token(afterMidnight.addingTimeInterval(6), total: 260, last: 60)
                ],
                name: "weighted.jsonl"
            )
            let weightedValue = try CodexDailyTokenUsageReader.readToday(
                from: [weighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                weightedValue == 260,
                "actual Token usage is not multiplied by Fast billing"
            )
            let weightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [weighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                weightedSnapshot.billedTodayTokens == 260,
                "Fast messages without model metadata remain unweighted"
            )
            expect(
                weightedSnapshot.hourlyBuckets.reduce(Int64(0)) {
                    $0 + $1.tokens
                } == 260
                    && weightedSnapshot.billedHourlyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 260,
                "hourly charts do not guess an unsupported Fast multiplier"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let modelWeighted = write(
                [
                    sessionMeta(),
                    threadSettings(
                        afterMidnight,
                        model: "gpt-5.4",
                        serviceTier: "priority"
                    ),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(2),
                        model: "gpt-5.5"
                    ),
                    token(afterMidnight.addingTimeInterval(3), total: 200, last: 100),
                    threadSettings(
                        afterMidnight.addingTimeInterval(4),
                        model: "gpt-5.6-sol"
                    ),
                    token(afterMidnight.addingTimeInterval(5), total: 300, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(6),
                        model: "gpt-6-astra",
                        serviceTier: "fast"
                    ),
                    token(afterMidnight.addingTimeInterval(7), total: 400, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(8),
                        model: "future-model"
                    ),
                    token(afterMidnight.addingTimeInterval(9), total: 500, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(10),
                        model: "gpt-6-astra",
                        serviceTier: "default"
                    ),
                    token(afterMidnight.addingTimeInterval(11), total: 600, last: 100)
                ],
                name: "model-weighted.jsonl"
            )
            let modelWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                modelWeightedSnapshot.todayTokens == 600,
                "model-specific Fast weighting does not change actual Tokens"
            )
            expect(
                modelWeightedSnapshot.billedTodayTokens == 1_150,
                "supported Fast models use official multipliers; Standard and unknown models stay 1x"
            )
            expect(
                hourlyTokens(modelWeightedSnapshot.hourlyBuckets, containing: afterMidnight) == 600
                    && dailyTokens(modelWeightedSnapshot.dailyBuckets, containing: afterMidnight) == 600,
                "Astra Fast weighting leaves actual hourly and daily chart Tokens unchanged"
            )
            expect(
                hourlyTokens(modelWeightedSnapshot.billedHourlyBuckets, containing: afterMidnight) == 1_150
                    && dailyTokens(modelWeightedSnapshot.billedDailyBuckets, containing: afterMidnight) == 1_150,
                "hourly and daily equivalent usage include Astra's 2.5x Fast multiplier"
            )

            let modelWeightedHandle = try FileHandle(forWritingTo: modelWeighted)
            try modelWeightedHandle.seekToEnd()
            try modelWeightedHandle.write(contentsOf: Data(([
                threadSettings(
                    afterMidnight.addingTimeInterval(12),
                    serviceTier: "priority"
                ),
                token(afterMidnight.addingTimeInterval(13), total: 700, last: 100)
            ].joined(separator: "\n") + "\n").utf8))
            try modelWeightedHandle.close()
            let appendedModelWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                appendedModelWeightedSnapshot.billedTodayTokens == 1_400,
                "incremental scans retain Astra and apply 2.5x when the tier changes to priority"
            )

            let nonChatGPTSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: false
            )
            expect(
                nonChatGPTSnapshot.todayTokens == 700
                    && nonChatGPTSnapshot.billedTodayTokens == 700,
                "non-ChatGPT authentication does not apply ChatGPT Fast multipliers"
            )
            let reenabledChatGPTSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: true
            )
            expect(
                reenabledChatGPTSnapshot.billedTodayTokens == 1_400,
                "changing the ChatGPT-credit mode safely invalidates cached weighting"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let providerWeighted = write(
                [
                    sessionMeta(modelProvider: "openai"),
                    threadSettings(
                        afterMidnight,
                        model: "gpt-6-astra",
                        modelProviderID: "custom-provider",
                        serviceTier: "priority"
                    ),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100),
                    threadSettings(
                        afterMidnight.addingTimeInterval(2),
                        modelProviderID: "openai"
                    ),
                    token(afterMidnight.addingTimeInterval(3), total: 200, last: 100)
                ],
                name: "provider-weighted.jsonl"
            )
            let providerWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [providerWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                providerWeightedSnapshot.todayTokens == 200
                    && providerWeightedSnapshot.billedTodayTokens == 350,
                "only the OpenAI provider receives ChatGPT Fast weighting"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let customSessionProvider = write(
                [
                    sessionMeta(modelProvider: "custom-provider"),
                    threadSettings(
                        afterMidnight,
                        model: "gpt-5.4",
                        serviceTier: "priority"
                    ),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100)
                ],
                name: "custom-session-provider.jsonl"
            )
            let customSessionProviderSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [customSessionProvider.path],
                now: now,
                calendar: calendar
            )
            expect(
                customSessionProviderSnapshot.billedTodayTokens == 100,
                "session metadata prevents weighting custom model providers"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let dailyRangeStart = calendar.date(
                byAdding: .day,
                value: -(CodexDailyTokenUsageReader.recentDayCount - 1),
                to: dayStart
            )!
            let baselineWeighted = write(
                [
                    sessionMeta(
                        startedAt: calendar.date(
                            byAdding: .day,
                            value: -40,
                            to: dayStart
                        )
                    ),
                    threadSettings(
                        dailyRangeStart.addingTimeInterval(-180),
                        serviceTier: "priority"
                    ),
                    turnContext(
                        dailyRangeStart.addingTimeInterval(-120),
                        model: "gpt-5.4"
                    ),
                    token(
                        dailyRangeStart.addingTimeInterval(-60),
                        total: 100,
                        last: 100
                    ),
                    token(afterMidnight, total: 200, last: 100)
                ],
                name: "baseline-model-weighted.jsonl"
            )
            let baselineWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [baselineWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                baselineWeightedSnapshot.billedTodayTokens == 200,
                "pre-range model and Fast tier remain active for the first counted call"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let absorbedChildCounter = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 100, last: 100),
                    token(laterToday, total: 1_000, last: 100)
                ],
                name: "absorbed-child-counter.jsonl"
            )
            let absorbedChildValue = try CodexDailyTokenUsageReader.readToday(
                from: [absorbedChildCounter.path],
                now: now,
                calendar: calendar
            )
            expect(
                absorbedChildValue == 200,
                "message-level usage ignores cumulative jumps absorbed from child tasks"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let crossMidnight = write(
                [
                    sessionMeta(),
                    token(beforeMidnight, total: 1_000, last: 1_000),
                    token(afterMidnight, total: 1_200, last: 200),
                    token(laterToday, total: 50, last: 50)
                ],
                name: "cross-midnight.jsonl"
            )
            let crossValue = try CodexDailyTokenUsageReader.readToday(
                from: [crossMidnight.path],
                now: now,
                calendar: calendar
            )
            expect(crossValue == 250, "daily tokens keep midnight baseline and handle epoch resets")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let firstToday = write(
                [sessionMeta(), token(afterMidnight, total: 1_000, last: 100)],
                name: "first-today.jsonl"
            )
            let firstValue = try CodexDailyTokenUsageReader.readToday(
                from: [firstToday.path],
                now: now,
                calendar: calendar
            )
            expect(firstValue == 100, "first daily absolute counter uses last usage as its baseline")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let currentHourStart = calendar.dateInterval(of: .hour, for: now)!.start
            let firstHourlyStart = calendar.date(
                byAdding: .hour,
                value: -(CodexDailyTokenUsageReader.recentHourCount - 1),
                to: currentHourStart
            )!
            let historicalDay = calendar.date(
                byAdding: .day,
                value: -10,
                to: dayStart
            )!
            let hourlyWindow = write(
                [
                    sessionMeta(
                        startedAt: calendar.date(
                            byAdding: .day,
                            value: -15,
                            to: now
                        )
                    ),
                    token(
                        historicalDay.addingTimeInterval(60),
                        total: 40,
                        last: 40
                    ),
                    token(firstHourlyStart.addingTimeInterval(-60), total: 100, last: 100),
                    token(firstHourlyStart.addingTimeInterval(60), total: 160, last: 60),
                    token(currentHourStart.addingTimeInterval(60), total: 220, last: 60)
                ],
                name: "hourly-window.jsonl"
            )
            let hourlyValue = try CodexDailyTokenUsageReader.readRecentHours(
                from: [hourlyWindow.path],
                now: now,
                calendar: calendar
            )
            expect(
                hourlyValue.hourlyBuckets.count
                    == CodexDailyTokenUsageReader.recentHourCount,
                "hourly timeline always contains exactly 48 clock-hour buckets"
            )
            expect(
                hourlyValue.hourlyBuckets.first?.tokens == 60,
                "hourly timeline uses the event before its window as a cumulative baseline"
            )
            expect(
                hourlyValue.hourlyBuckets.last?.tokens == 60,
                "hourly timeline includes the current partial hour"
            )
            expect(
                hourlyValue.hourlyBuckets.reduce(Int64(0)) { $0 + $1.tokens } == 120,
                "hourly timeline excludes activity older than 48 clock hours"
            )
            let dailyFormatter = DateFormatter()
            dailyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dailyFormatter.calendar = calendar
            dailyFormatter.timeZone = calendar.timeZone
            dailyFormatter.dateFormat = "yyyy-MM-dd"
            expect(
                hourlyValue.dailyBuckets.first {
                    $0.startDate == dailyFormatter.string(from: historicalDay)
                }?.tokens == 40,
                "local daily timeline retains message-level history for 30 days"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let rolloverHourStart = calendar.date(
                byAdding: .hour,
                value: 10,
                to: dayStart
            )!
            let rolloverEvent = rolloverHourStart.addingTimeInterval(30 * 60)
            let hourRollover = write(
                [
                    sessionMeta(
                        startedAt: rolloverHourStart.addingTimeInterval(-60)
                    ),
                    token(rolloverEvent, total: 80, last: 80)
                ],
                name: "hour-rollover.jsonl"
            )
            let beforeHourRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [hourRollover.path],
                now: rolloverHourStart.addingTimeInterval(59 * 60),
                calendar: calendar
            )
            let beforeHourDiagnostics = CodexDailyTokenUsageReader
                .cacheDiagnosticsForTesting()
            let afterHourRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [hourRollover.path],
                now: rolloverHourStart.addingTimeInterval(61 * 60),
                calendar: calendar
            )
            let afterHourDiagnostics = CodexDailyTokenUsageReader
                .cacheDiagnosticsForTesting()
            expect(
                beforeHourRollover.hourlyBuckets.last?.tokens == 80,
                "cached hourly usage starts in the current partial hour"
            )
            expect(
                hourlyTokens(
                    afterHourRollover.hourlyBuckets,
                    containing: rolloverEvent
                ) == 80
                    && afterHourRollover.hourlyBuckets.last?.tokens == 0
                    && afterHourRollover.todayTokens == 80,
                "the same cache rolls across an hour boundary without losing usage"
            )
            expect(
                hourlyTokens(
                    afterHourRollover.billedHourlyBuckets,
                    containing: rolloverEvent
                ) == 80,
                "billed hourly usage rolls across an hour boundary with actual usage"
            )
            expect(
                beforeHourDiagnostics.baselineScanCount == 1
                    && afterHourDiagnostics == beforeHourDiagnostics,
                "hour rollover reuses the reducer without another baseline scan"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let futureHourStart = calendar.date(
                byAdding: .hour,
                value: 14,
                to: dayStart
            )!
            let futureHourEvent = futureHourStart.addingTimeInterval(0.25)
            let prewrittenFutureHour = write(
                [
                    sessionMeta(
                        startedAt: futureHourStart.addingTimeInterval(-120)
                    ),
                    token(futureHourEvent, total: 42, last: 42)
                ],
                name: "prewritten-future-hour.jsonl"
            )
            try FileManager.default.setAttributes(
                [.modificationDate: futureHourEvent],
                ofItemAtPath: prewrittenFutureHour.path
            )
            let beforeFutureHour = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureHour.path],
                now: futureHourStart.addingTimeInterval(-1),
                calendar: calendar
            )
            let afterFutureHour = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureHour.path],
                now: futureHourStart.addingTimeInterval(1),
                calendar: calendar
            )
            expect(
                beforeFutureHour.hourlyBuckets.last?.tokens == 0
                    && afterFutureHour.hourlyBuckets.last?.tokens == 42,
                "a prewritten next-hour event appears after rollover without another append"
            )
            expect(
                CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                    .baselineScanCount == 1,
                "a prewritten next-hour event does not require a cold rescan"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let midnightRollover = write(
                [
                    sessionMeta(
                        startedAt: beforeMidnight.addingTimeInterval(-60)
                    ),
                    token(beforeMidnight, total: 75, last: 75)
                ],
                name: "midnight-rollover.jsonl"
            )
            let beforeMidnightRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [midnightRollover.path],
                now: beforeMidnight.addingTimeInterval(30),
                calendar: calendar
            )
            expect(
                beforeMidnightRollover.todayTokens == 75,
                "usage immediately before midnight belongs to the old day"
            )
            try appendLines(
                [token(afterMidnight, total: 105, last: 30)],
                to: midnightRollover
            )
            let afterMidnightRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [midnightRollover.path],
                now: afterMidnight.addingTimeInterval(30),
                calendar: calendar
            )
            expect(
                afterMidnightRollover.todayTokens == 30
                    && dailyTokens(
                        afterMidnightRollover.dailyBuckets,
                        containing: beforeMidnight
                    ) == 75
                    && dailyTokens(
                        afterMidnightRollover.dailyBuckets,
                        containing: afterMidnight
                    ) == 30,
                "the same cache rolls across midnight and separates both days"
            )
            expect(
                afterMidnightRollover.hourlyBuckets.reduce(Int64(0)) {
                    $0 + $1.tokens
                } == 105
                    && afterMidnightRollover.billedDailyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 105,
                "hourly and billed histories remain intact across midnight"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let prewrittenFutureDay = write(
                [
                    sessionMeta(
                        startedAt: beforeMidnight.addingTimeInterval(-60)
                    ),
                    token(afterMidnight, total: 30, last: 30)
                ],
                name: "prewritten-future-day.jsonl"
            )
            let beforeFutureDay = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureDay.path],
                now: dayStart.addingTimeInterval(-1),
                calendar: calendar
            )
            let afterFutureDay = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureDay.path],
                now: afterMidnight.addingTimeInterval(60),
                calendar: calendar
            )
            expect(
                beforeFutureDay.todayTokens == 0
                    && afterFutureDay.todayTokens == 30
                    && dailyTokens(
                        afterFutureDay.dailyBuckets,
                        containing: afterMidnight
                    ) == 30,
                "a prewritten next-day event enters today's totals after midnight"
            )
            expect(
                CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                    .baselineScanCount == 1,
                "midnight rollover promotes a future daily bucket without rescanning"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let jumpEvent = calendar.date(
                byAdding: .minute,
                value: 70,
                to: dayStart
            )!
            let jumpInitialNow = calendar.date(
                byAdding: .minute,
                value: 90,
                to: dayStart
            )!
            let jumpRollover = write(
                [
                    sessionMeta(startedAt: dayStart),
                    token(jumpEvent, total: 55, last: 55)
                ],
                name: "multi-window-rollover.jsonl"
            )
            let jumpInitial = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow,
                calendar: calendar
            )
            expect(
                jumpInitial.todayTokens == 55
                    && hourlyTokens(
                        jumpInitial.hourlyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "forward-jump fixture starts inside the hourly and daily windows"
            )
            let afterSixHourJump = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow.addingTimeInterval(6 * 60 * 60),
                calendar: calendar
            )
            expect(
                afterSixHourJump.todayTokens == 55
                    && hourlyTokens(
                        afterSixHourJump.hourlyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "the same cache handles a multi-hour forward jump"
            )
            let afterThreeDayJump = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow.addingTimeInterval(3 * 24 * 60 * 60),
                calendar: calendar
            )
            expect(
                afterThreeDayJump.todayTokens == 0
                    && afterThreeDayJump.hourlyBuckets.allSatisfy {
                        $0.tokens == 0
                    }
                    && dailyTokens(
                        afterThreeDayJump.dailyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "a multi-day jump expires hourly usage while retaining 30-day history"
            )
            let afterThirtyFiveDayJump = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow.addingTimeInterval(35 * 24 * 60 * 60),
                calendar: calendar
            )
            expect(
                afterThirtyFiveDayJump.todayTokens == 0
                    && afterThirtyFiveDayJump.hourlyBuckets.count
                        == CodexDailyTokenUsageReader.recentHourCount
                    && afterThirtyFiveDayJump.hourlyBuckets.allSatisfy {
                        $0.tokens == 0
                    }
                    && afterThirtyFiveDayJump.dailyBuckets.count
                        == CodexDailyTokenUsageReader.recentDayCount
                    && afterThirtyFiveDayJump.dailyBuckets.allSatisfy {
                        $0.tokens == 0
                    },
                "a large forward jump expires usage outside both rolling windows"
            )
            let beforeClockRewindDiagnostics = CodexDailyTokenUsageReader
                .cacheDiagnosticsForTesting()
            let afterClockRewind = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow,
                calendar: calendar
            )
            expect(
                afterClockRewind.todayTokens == 55
                    && hourlyTokens(
                        afterClockRewind.hourlyBuckets,
                        containing: jumpEvent
                    ) == 55
                    && dailyTokens(
                        afterClockRewind.dailyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "moving the clock backward rebuilds the cached windows correctly"
            )
            expect(
                beforeClockRewindDiagnostics.baselineScanCount == 1
                    && CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                        .baselineScanCount == 2,
                "clock rewind intentionally performs one new baseline scan"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let appendHourStart = calendar.date(
                byAdding: .hour,
                value: 8,
                to: dayStart
            )!
            let firstAppendEvent = appendHourStart.addingTimeInterval(50 * 60)
            let appendAfterRollover = write(
                [
                    sessionMeta(
                        startedAt: appendHourStart.addingTimeInterval(-60)
                    ),
                    token(firstAppendEvent, total: 100, last: 100)
                ],
                name: "append-after-window-rollover.jsonl"
            )
            _ = try CodexDailyTokenUsageReader.readRecentHours(
                from: [appendAfterRollover.path],
                now: appendHourStart.addingTimeInterval(55 * 60),
                calendar: calendar
            )
            let appendRolledNow = appendHourStart.addingTimeInterval(65 * 60)
            let beforeRolloverAppend = try CodexDailyTokenUsageReader.readRecentHours(
                from: [appendAfterRollover.path],
                now: appendRolledNow,
                calendar: calendar
            )
            expect(
                beforeRolloverAppend.hourlyBuckets.last?.tokens == 0
                    && hourlyTokens(
                        beforeRolloverAppend.hourlyBuckets,
                        containing: firstAppendEvent
                    ) == 100,
                "the cache rolls before a new token is appended"
            )
            let secondAppendEvent = appendHourStart.addingTimeInterval(66 * 60)
            try appendLines(
                [token(secondAppendEvent, total: 160, last: 60)],
                to: appendAfterRollover
            )
            let afterRolloverAppend = try CodexDailyTokenUsageReader.readRecentHours(
                from: [appendAfterRollover.path],
                now: appendHourStart.addingTimeInterval(67 * 60),
                calendar: calendar
            )
            let repeatedAfterRolloverAppend = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: [appendAfterRollover.path],
                    now: appendHourStart.addingTimeInterval(67 * 60),
                    calendar: calendar
                )
            expect(
                afterRolloverAppend.todayTokens == 160
                    && hourlyTokens(
                        afterRolloverAppend.hourlyBuckets,
                        containing: firstAppendEvent
                    ) == 100
                    && hourlyTokens(
                        afterRolloverAppend.hourlyBuckets,
                        containing: secondAppendEvent
                    ) == 60
                    && afterRolloverAppend.hourlyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 160,
                "a token appended after window rollover is added to the new hour"
            )
            expect(
                repeatedAfterRolloverAppend == afterRolloverAppend,
                "an appended token remains counted exactly once after window rollover"
            )
            expect(
                CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                    .baselineScanCount == 1,
                "an append after rollover uses the incremental cursor"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let forked = write(
                [
                    sessionMeta(forked: true, startedAt: laterToday),
                    token(laterToday.addingTimeInterval(0.5), total: 9_900, last: 9_900),
                    threadSettings(
                        laterToday.addingTimeInterval(0.75),
                        model: "gpt-5.6-sol",
                        modelProviderID: "openai",
                        serviceTier: "priority"
                    ),
                    sessionMeta(
                        forked: true,
                        startedAt: laterToday.addingTimeInterval(1)
                    ),
                    token(laterToday.addingTimeInterval(2), total: 9_999, last: 99)
                ],
                name: "forked.jsonl"
            )
            let forkValue = try CodexDailyTokenUsageReader.readToday(
                from: [forked.path],
                now: now,
                calendar: calendar
            )
            expect(
                forkValue == 99,
                "forked rollout counts new model calls but skips copied history"
            )
            let forkUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [forked.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: true
            )
            expect(
                forkUsage.billedTodayTokens == 248,
                "forked usage inherits the pre-boundary Fast baseline"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let pendingFork = write(
                [
                    sessionMeta(forked: true, startedAt: laterToday),
                    token(laterToday.addingTimeInterval(0.5), total: 9_000, last: 9_000)
                ],
                name: "pending-fork.jsonl"
            )
            let pendingForkValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingFork.path],
                now: now,
                calendar: calendar
            )
            expect(
                pendingForkValue == 0,
                "fork replay stays hidden until the fork's own first turn starts"
            )
            let pendingForkHandle = try FileHandle(forWritingTo: pendingFork)
            try pendingForkHandle.seekToEnd()
            try pendingForkHandle.write(contentsOf: Data(([
                sessionMeta(
                    forked: true,
                    startedAt: laterToday.addingTimeInterval(1)
                ),
                token(laterToday.addingTimeInterval(2), total: 9_080, last: 80)
            ].joined(separator: "\n") + "\n").utf8))
            try pendingForkHandle.close()
            let readyForkValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingFork.path],
                now: now,
                calendar: calendar
            )
            expect(
                readyForkValue == 80,
                "fork cache rebuilds when its real activity boundary is appended"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let subagent = write(
                [
                    sessionMeta(startedAt: laterToday, subagent: true),
                    threadSettings(
                        laterToday,
                        model: "gpt-5.6-sol",
                        modelProviderID: "openai",
                        serviceTier: "priority"
                    ),
                    token(laterToday, total: 500, last: 500),
                    token(laterToday, total: 570, last: 70),
                    #"{"type":"response_item","payload":{"text":"inter_agent_communication_metadata"}}"#,
                    subagentBoundary(laterToday.addingTimeInterval(1)),
                    token(laterToday.addingTimeInterval(2), total: 640, last: 70)
                ],
                name: "subagent.jsonl"
            )
            let subagentValue = try CodexDailyTokenUsageReader.readToday(
                from: [subagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                subagentValue == 70,
                "subagent rollout treats timestamp-rewritten parent history as a baseline"
            )
            let subagentHourlyValue = try CodexDailyTokenUsageReader.readRecentHours(
                from: [subagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                subagentHourlyValue.hourlyBuckets.reduce(Int64(0)) {
                    $0 + $1.tokens
                } == 70
                    && subagentHourlyValue.billedHourlyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 175,
                "subagent usage inherits the pre-boundary Fast baseline without counting replayed Tokens"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let pendingSubagent = write(
                [
                    sessionMeta(startedAt: laterToday, subagent: true),
                    threadSettings(
                        laterToday,
                        model: "gpt-5.6-sol",
                        modelProviderID: "openai",
                        serviceTier: "priority"
                    ),
                    token(laterToday, total: 9_000, last: 9_000)
                ],
                name: "pending-subagent.jsonl"
            )
            let pendingValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingSubagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                pendingValue == 0,
                "subagent history stays hidden until its activity boundary is committed"
            )

            let pendingHandle = try FileHandle(forWritingTo: pendingSubagent)
            try pendingHandle.seekToEnd()
            try pendingHandle.write(contentsOf: Data(([
                subagentBoundary(laterToday.addingTimeInterval(1)),
                token(laterToday.addingTimeInterval(2), total: 9_080, last: 80)
            ].joined(separator: "\n") + "\n").utf8))
            try pendingHandle.close()
            let readyValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingSubagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                readyValue == 80,
                "subagent cache rebuilds when the activity boundary is appended"
            )
            let readyUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [pendingSubagent.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: true
            )
            expect(
                readyUsage.billedTodayTokens == 200,
                "appended subagent activity restores the inherited Fast baseline"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let partial = directory.appendingPathComponent("partial.jsonl")
            let second = token(laterToday, total: 160, last: 60)
            let split = second.index(second.startIndex, offsetBy: second.count / 2)
            let initial = [
                sessionMeta(),
                token(afterMidnight, total: 100, last: 100),
                String(second[..<split])
            ].joined(separator: "\n")
            try Data(initial.utf8).write(to: partial)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: partial.path)
            let partialValue = try CodexDailyTokenUsageReader.readToday(
                from: [partial.path],
                now: now,
                calendar: calendar
            )
            expect(partialValue == 100, "unterminated token record is not counted early")

            let handle = try FileHandle(forWritingTo: partial)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((String(second[split...]) + "\n").utf8))
            try handle.close()
            let completedValue = try CodexDailyTokenUsageReader.readToday(
                from: [partial.path],
                now: now,
                calendar: calendar
            )
            expect(completedValue == 160, "completed appended token record is counted exactly once")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let completeWithoutNewline = directory.appendingPathComponent(
                "complete-without-newline.jsonl"
            )
            let uncommitted = sessionMeta() + "\n"
                + token(afterMidnight, total: 100, last: 100)
            try Data(uncommitted.utf8).write(to: completeWithoutNewline)
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: completeWithoutNewline.path
            )
            let uncommittedValue = try CodexDailyTokenUsageReader.readToday(
                from: [completeWithoutNewline.path],
                now: now,
                calendar: calendar
            )
            expect(uncommittedValue == 0, "valid JSONL tail waits for its newline delimiter")

            let delimiterHandle = try FileHandle(forWritingTo: completeWithoutNewline)
            try delimiterHandle.seekToEnd()
            try delimiterHandle.write(contentsOf: Data("\n".utf8))
            try delimiterHandle.close()
            let committedValue = try CodexDailyTokenUsageReader.readToday(
                from: [completeWithoutNewline.path],
                now: now,
                calendar: calendar
            )
            expect(committedValue == 100, "newline commits a previously complete JSONL tail")

            let replacement = sessionMeta() + "\n"
                + token(afterMidnight, total: 40, last: 40) + "\n"
            try Data(replacement.utf8).write(to: completeWithoutNewline)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(1)],
                ofItemAtPath: completeWithoutNewline.path
            )
            let replacementValue = try CodexDailyTokenUsageReader.readToday(
                from: [completeWithoutNewline.path],
                now: now,
                calendar: calendar
            )
            expect(replacementValue == 40, "truncated rollout rebuilds its daily cache")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let largeUnrelated = write(
                [
                    sessionMeta(),
                    token(beforeMidnight, total: 100, last: 100),
                    "{\"type\":\"response_item\",\"payload\":{\"text\":\""
                        + String(repeating: "x", count: 140_000)
                        + "\"}}",
                    token(afterMidnight, total: 160, last: 60)
                ],
                name: "large-unrelated.jsonl"
            )
            let largeValue = try CodexDailyTokenUsageReader.readToday(
                from: [largeUnrelated.path],
                now: now,
                calendar: calendar
            )
            expect(largeValue == 60, "oversized unrelated rollout rows do not break daily scanning")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let coldHistory = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 10, last: 10)
                ],
                name: "cold-history.jsonl"
            )
            let liveHistory = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 20, last: 20)
                ],
                name: "live-history.jsonl"
            )
            let inactiveModifiedAt = now.addingTimeInterval(-2 * 60 * 60)
            try FileManager.default.setAttributes(
                [.modificationDate: inactiveModifiedAt],
                ofItemAtPath: coldHistory.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: inactiveModifiedAt],
                ofItemAtPath: liveHistory.path
            )
            let splitPaths = [coldHistory.path, liveHistory.path]
            let initialSplitUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: splitPaths,
                now: now,
                calendar: calendar,
                priorityRolloutPaths: [liveHistory.path]
            )
            let initialPerformance = CodexDailyTokenUsageReader
                .performanceDiagnosticsForTesting()
            let repeatedSplitUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: splitPaths,
                now: now.addingTimeInterval(1),
                calendar: calendar,
                priorityRolloutPaths: [liveHistory.path]
            )
            let repeatedPerformance = CodexDailyTokenUsageReader
                .performanceDiagnosticsForTesting()
            expect(
                initialSplitUsage.todayTokens == 30
                    && repeatedSplitUsage == initialSplitUsage,
                "hot and cold rollout polling preserves the aggregated usage"
            )
            expect(
                initialPerformance.metadataCheckCount == 2
                    && repeatedPerformance.metadataCheckCount == 3,
                "one-second polling skips metadata checks for inactive history"
            )

            try appendLines(
                [token(laterToday, total: 15, last: 5)],
                to: coldHistory
            )
            let beforeHistoricalRefresh = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: splitPaths,
                    now: now.addingTimeInterval(2),
                    calendar: calendar,
                    priorityRolloutPaths: [liveHistory.path]
                )
            let afterHistoricalRefresh = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: splitPaths,
                    now: now.addingTimeInterval(31),
                    calendar: calendar,
                    priorityRolloutPaths: [liveHistory.path]
                )
            let refreshedPerformance = CodexDailyTokenUsageReader
                .performanceDiagnosticsForTesting()
            expect(
                beforeHistoricalRefresh.todayTokens == 30
                    && afterHistoricalRefresh.todayTokens == 35,
                "inactive history refreshes within the bounded 30-second interval"
            )
            expect(
                refreshedPerformance.metadataCheckCount == 6
                    && refreshedPerformance.aggregateRebuildCount == 0,
                "changed files update cached aggregates by delta"
            )
            let afterColdPathRemoval = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: [liveHistory.path],
                    now: now.addingTimeInterval(32),
                    calendar: calendar,
                    priorityRolloutPaths: [liveHistory.path]
                )
            expect(
                afterColdPathRemoval.todayTokens == 20,
                "removing a rollout path subtracts its cached aggregate"
            )

            let codexHome = directory.appendingPathComponent("codex-home")
            let sessions = codexHome
                .appendingPathComponent("sessions")
                .appendingPathComponent("2026/07/15")
            try FileManager.default.createDirectory(
                at: sessions,
                withIntermediateDirectories: true
            )
            let rootRollout = sessions.appendingPathComponent("root.jsonl")
            let forkRollout = sessions.appendingPathComponent("fork.jsonl")
            let subagentRollout = sessions.appendingPathComponent("subagent.jsonl")
            try Data((sessionMeta() + "\n").utf8).write(to: rootRollout)
            try Data((sessionMeta(forked: true) + "\n").utf8).write(to: forkRollout)
            try Data((sessionMeta(subagent: true) + "\n").utf8).write(to: subagentRollout)
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: rootRollout.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: forkRollout.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: subagentRollout.path
            )

            let originalCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            setenv("CODEX_HOME", codexHome.path, 1)
            let discovered = try CodexDailyTokenUsageReader
                .discoverLocalUsageRollouts(now: now, calendar: calendar)
            if let originalCodexHome {
                setenv("CODEX_HOME", originalCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
            expect(
                discovered == [
                    forkRollout.path,
                    rootRollout.path,
                    subagentRollout.path
                ].sorted(),
                "local rollout discovery includes roots, forks, and subagents"
            )
        } catch {
            expect(false, "daily token usage reader: \(error.localizedDescription)")
        }
    }

    private static func checkRecentThreads() {
        let rows: [JSONObject] = (1...6).map { index in
            [
                "id": "thread-\(index)",
                "name": "会话 \(index)",
                "source": index.isMultiple(of: 2) ? "vscode" : "cli",
                "status": ["type": "notLoaded"],
                "updatedAt": 2_000_000_000 - index
            ]
        }
        let threads = CodexStatusPayloadParser.parseRecentThreads(["data": rows])
        expect(threads.count == 5, "recent thread limit")
        expect(
            threads.map(\.id) == ["thread-1", "thread-2", "thread-3", "thread-4", "thread-5"],
            "recent thread order"
        )
        expect(
            threads.map(\.clientSource) == [.tui, .app, .tui, .app, .tui],
            "CLI and Desktop thread sources map to TUI and APP"
        )

        let sourceVariants = CodexStatusPayloadParser.parseRecentThreads([
            "data": [
                ["id": "trimmed-cli", "source": "  CLI \n"],
                ["id": "uppercase-vscode", "source": "VSCODE"],
                ["id": "exec", "source": "exec"],
                ["id": "app-server", "source": "appServer"],
                ["id": "custom", "source": ["custom": "example"]]
            ]
        ])
        expect(
            sourceVariants.map(\.clientSource) == [.tui, .app, nil, nil, nil],
            "only cli and vscode receive visible source labels"
        )

        let missingIDRows: [JSONObject] = [
            [
                "name": "无 ID 会话 A",
                "path": "/Users/test/.codex/sessions/rollout-fallback-a.jsonl",
                "status": ["type": "notLoaded"],
                "updatedAt": 2_000_000_100
            ],
            [
                "name": "无 ID 会话 B",
                "path": "/Users/test/.codex/sessions/rollout-fallback-b.jsonl",
                "status": ["type": "active"],
                "updatedAt": 2_000_000_200
            ],
            ["id": "  \n", "name": "空白 ID 旧会话"],
            ["name": "完全相同的旧 payload"],
            ["name": "完全相同的旧 payload"]
        ]
        let firstParse = CodexStatusPayloadParser.parseRecentThreads([
            "data": missingIDRows
        ])
        let secondParse = CodexStatusPayloadParser.parseRecentThreads([
            "data": missingIDRows
        ])
        expect(
            firstParse.allSatisfy { !$0.id.isEmpty },
            "missing thread IDs receive non-empty fallbacks"
        )
        expect(
            Set(firstParse.map(\.id)).count == missingIDRows.count,
            "multiple missing thread IDs remain unique, including duplicate payloads"
        )
        expect(
            firstParse.map(\.id) == secondParse.map(\.id),
            "fallback thread IDs are reproducible for the same payload"
        )

        let changedMetadata: [JSONObject] = [[
            "name": "重命名后的会话",
            "path": "/Users/test/.codex/sessions/rollout-fallback-a.jsonl",
            "status": ["type": "active"],
            "updatedAt": 2_000_999_999
        ]]
        expect(
            CodexStatusPayloadParser.parseRecentThreads(["data": changedMetadata]).first?.id
                == firstParse.first?.id,
            "rollout path keeps a fallback identity stable across mutable metadata changes"
        )

        let alternateID = CodexStatusPayloadParser.parseRecentThreads([
            "data": [["threadId": "legacy-thread-id", "name": "旧字段会话"]]
        ]).first
        expect(
            alternateID?.id == "legacy-thread-id",
            "legacy stable thread ID fields are preferred over synthetic fallbacks"
        )
    }
}

private enum LaunchAtLoginTestError: Error {
    case operationFailed
}

private final class FakeLaunchAtLoginService {
    var status: LaunchAtLoginServiceStatus
    var statusAfterRegister: LaunchAtLoginServiceStatus?
    var statusAfterUnregister: LaunchAtLoginServiceStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var statusReadCount = 0
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    var backend: LaunchAtLoginBackend {
        LaunchAtLoginBackend(
            readStatus: { [self] in
                statusReadCount += 1
                return status
            },
            register: { [self] in
                registerCallCount += 1
                if let registerError { throw registerError }
                if let statusAfterRegister { status = statusAfterRegister }
            },
            unregister: { [self] in
                unregisterCallCount += 1
                if let unregisterError { throw unregisterError }
                if let statusAfterUnregister { status = statusAfterUnregister }
            }
        )
    }
}
