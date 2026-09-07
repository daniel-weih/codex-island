import AppKit
import SwiftUI

@MainActor
enum CodexPreviewRenderer {
    static func render(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let previewResetExpirations = [14, 21, 28, 35, 42].map { days in
            Date().addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
        }
        let previewAvatarData = ProcessInfo.processInfo.environment[
            "CODEX_ISLAND_PREVIEW_AVATAR_PATH"
        ].flatMap { path in
            try? Data(contentsOf: URL(fileURLWithPath: path))
        }

        var snapshot = CodexSnapshot(
            connection: .connected,
            account: AccountSummary(authType: "chatgpt", planType: "pro", requiresOpenAIAuth: true),
            rateLimit: RateLimitBucket(
                id: "codex",
                name: "Codex",
                planType: "pro",
                primary: RateLimitWindow(
                    usedPercent: 90,
                    windowDurationMinutes: 10_080,
                    resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60)
                ),
                secondary: nil,
                reachedType: nil
            ),
            resetCredits: ResetCreditSummary(
                availableCount: 5,
                earliestExpiration: previewResetExpirations.first,
                expirationDates: previewResetExpirations
            ),
            usage: UsageSummary(
                lifetimeTokens: 8_435_323_666,
                peakDailyTokens: 338_060_020,
                longestRunningTurnSeconds: 10_022,
                currentStreakDays: 156,
                longestStreakDays: 156,
                dailyUsageBuckets: previewDailyUsageBuckets()
            ),
            profileIdentity: ProfileIdentitySummary(
                displayName: "Daniel",
                avatarData: previewAvatarData
            ),
            recentThreads: [
                ThreadSummary(
                    id: "preview-1",
                    title: "Create hatch pet",
                    status: "notLoaded",
                    clientSource: .app,
                    model: "gpt-5.6-sol",
                    reasoningEffort: "ultra",
                    serviceTier: "default",
                    serviceTierSource: .recorded,
                    tokenUsage: ThreadTokenUsage(
                        inputTokens: 2_929_630,
                        cachedInputTokens: 2_806_528,
                        outputTokens: 19_878,
                        reasoningOutputTokens: 2_428,
                        totalTokens: 2_949_508,
                        contextTokensUsed: 94_000,
                        contextWindowTokens: 258_400
                    ),
                    executionState: .idle,
                    cwd: nil,
                    rolloutPath: nil,
                    updatedAt: Date()
                ),
                ThreadSummary(
                    id: "preview-2",
                    title: "修复 OpenClaw OAuth 授权失败",
                    status: "notLoaded",
                    clientSource: .tui,
                    model: "gpt-5.5",
                    reasoningEffort: "high",
                    serviceTier: "priority",
                    serviceTierSource: .effectiveConfig,
                    tokenUsage: ThreadTokenUsage(
                        inputTokens: 152_424_863,
                        cachedInputTokens: 145_716_480,
                        outputTokens: 502_748,
                        reasoningOutputTokens: 240_625,
                        totalTokens: 152_927_611,
                        contextTokensUsed: 188_432,
                        contextWindowTokens: 258_400
                    ),
                    executionState: .running,
                    cwd: nil,
                    rolloutPath: nil,
                    updatedAt: Date().addingTimeInterval(-4 * 60)
                ),
                ThreadSummary(
                    id: "preview-3",
                    title: "微调本地模型的计算能力",
                    status: "notLoaded",
                    clientSource: .app,
                    model: "o3",
                    reasoningEffort: "medium",
                    serviceTier: nil,
                    serviceTierSource: nil,
                    tokenUsage: ThreadTokenUsage(
                        inputTokens: 235_151,
                        cachedInputTokens: 202_752,
                        outputTokens: 6_625,
                        reasoningOutputTokens: 4_288,
                        totalTokens: 241_776,
                        contextTokensUsed: 18_600,
                        contextWindowTokens: 200_000
                    ),
                    executionState: .interrupted,
                    cwd: nil,
                    rolloutPath: nil,
                    updatedAt: Date().addingTimeInterval(-18 * 60)
                ),
                ThreadSummary(
                    id: "preview-4",
                    title: "升级本地 OpenClaw",
                    status: "notLoaded",
                    clientSource: .tui,
                    model: "gpt-5.6-sol",
                    reasoningEffort: "high",
                    serviceTier: "priority",
                    serviceTierSource: .recorded,
                    tokenUsage: ThreadTokenUsage(
                        inputTokens: 30_870_277,
                        cachedInputTokens: 30_249_472,
                        outputTokens: 131_261,
                        reasoningOutputTokens: 36_596,
                        totalTokens: 31_001_538,
                        contextTokensUsed: 231_000,
                        contextWindowTokens: 258_400
                    ),
                    executionState: .failed,
                    cwd: nil,
                    rolloutPath: nil,
                    updatedAt: Date().addingTimeInterval(-31 * 60)
                ),
                ThreadSummary(
                    id: "preview-5",
                    title: "分析 Codex 会话文件",
                    status: "notLoaded",
                    clientSource: nil,
                    model: "gpt-5.5",
                    reasoningEffort: "medium",
                    serviceTier: "default",
                    serviceTierSource: .recorded,
                    tokenUsage: nil,
                    executionState: .unknown,
                    cwd: nil,
                    rolloutPath: nil,
                    updatedAt: Date().addingTimeInterval(-47 * 60)
                )
            ],
            todayThreadTokens: 84_350_271,
            hourlyThreadTokens: previewHourlyUsageBuckets(),
            dailyThreadTokens: previewDailyUsageBuckets(),
            billedTodayThreadTokens: 146_220_407,
            billedHourlyThreadTokens: previewBilledHourlyUsageBuckets(),
            billedDailyThreadTokens: previewBilledDailyUsageBuckets(),
            remainingTokenEstimate: CodexRemainingTokenEstimate(
                tokens: 36_500_000,
                windowDurationMinutes: 10_080,
                resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60),
                sampleCount: 240,
                observedQuotaPercent: 30,
                pricedTokenCoverage: 1
            ),
            hasRunningSession: true,
            activeModel: ModelSummary(
                id: "gpt-5.6-sol",
                displayName: "GPT-5.6 Sol",
                isDefault: true
            ),
            lastUpdated: Date(),
            warning: nil
        )

        for index in snapshot.recentThreads.indices {
            let thread = snapshot.recentThreads[index]
            if let usage = thread.tokenUsage,
               let credits = CodexCreditRateCard.credits(
                model: thread.model, serviceTier: thread.serviceTier,
                inputTokens: usage.inputTokens, cachedInputTokens: usage.cachedInputTokens,
                outputTokens: usage.outputTokens
               ) {
                snapshot.recentThreads[index].tokenUsage?.creditEstimate = CodexThreadCreditEstimate(credits: credits)
            }
        }

        let compactURL = directory.appendingPathComponent("codex-island-compact.png")
        let compactConsumingURL = directory.appendingPathComponent(
            "codex-island-compact-token-consuming.png"
        )
        let compactBoundaryURL = directory.appendingPathComponent(
            "codex-island-compact-token-boundary.png"
        )
        let compactConsuming1xURL = directory.appendingPathComponent(
            "codex-island-compact-token-consuming-1x.png"
        )
        let expandedURL = directory.appendingPathComponent("codex-island-expanded.png")
        let expandedHourlyURL = directory.appendingPathComponent(
            "codex-island-expanded-hourly.png"
        )
        let expandedSmallFastDeltaURL = directory.appendingPathComponent(
            "codex-island-expanded-small-fast-delta.png"
        )
        let expandedTsinghuaURL = directory.appendingPathComponent(
            "codex-island-expanded-tsinghua.png"
        )
        let companyThemePreviews: [(theme: IslandColorTheme, url: URL)] = [
            (.meituan, directory.appendingPathComponent("codex-island-expanded-meituan.png")),
            (.bytedance, directory.appendingPathComponent("codex-island-expanded-bytedance.png")),
            (.alibaba, directory.appendingPathComponent("codex-island-expanded-alibaba.png")),
            (.tencent, directory.appendingPathComponent("codex-island-expanded-tencent.png"))
        ]
        let settingsURL = directory.appendingPathComponent(
            "codex-island-expanded-settings.png"
        )
        let expandedEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-english.png"
        )
        let settingsEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-settings-english.png"
        )
        let settingsDisplayMenuURL = directory.appendingPathComponent(
            "codex-island-expanded-settings-display-menu.png"
        )
        let settingsDisplayMenuEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-settings-display-menu-english.png"
        )
        let resetHoverEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-reset-hover-english.png"
        )
        let headerQuitHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-header-quit-hover.png"
        )
        let headerIslandSettingsHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-header-island-settings-hover.png"
        )
        let headerScreenshotHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-header-screenshot-hover.png"
        )
        let headerCodexSettingsHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-header-codex-settings-hover.png"
        )
        let hoverTopURL = directory.appendingPathComponent(
            "codex-island-expanded-token-hover-top.png"
        )
        let hoverTopEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-token-hover-top-english.png"
        )
        let hoverBottomURL = directory.appendingPathComponent(
            "codex-island-expanded-token-hover-bottom.png"
        )
        let contextHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-context-hover.png"
        )
        let contextHoverEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-context-hover-english.png"
        )
        let resetHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-reset-hover.png"
        )
        let chartLegendHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-chart-legend-hover.png"
        )
        let chartLegendHoverEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-chart-legend-hover-english.png"
        )
        var outputURLs = [
            compactURL,
            compactConsumingURL,
            compactBoundaryURL,
            compactConsuming1xURL,
            expandedURL,
            expandedHourlyURL,
            expandedSmallFastDeltaURL,
            expandedTsinghuaURL,
            settingsURL,
            expandedEnglishURL,
            settingsEnglishURL,
            settingsDisplayMenuURL,
            settingsDisplayMenuEnglishURL,
            resetHoverEnglishURL,
            headerIslandSettingsHoverURL,
            headerScreenshotHoverURL,
            headerCodexSettingsHoverURL,
            headerQuitHoverURL,
            hoverTopURL,
            hoverTopEnglishURL,
            hoverBottomURL,
            contextHoverURL,
            contextHoverEnglishURL,
            resetHoverURL,
            chartLegendHoverURL,
            chartLegendHoverEnglishURL
        ]
        outputURLs.append(contentsOf: companyThemePreviews.map(\.url))
        var englishSnapshot = snapshot
        let englishThreadTitles = [
            "Create hatch pet",
            "Fix OpenClaw OAuth authentication",
            "Improve local model arithmetic",
            "Upgrade local OpenClaw",
            "Analyze Codex session files"
        ]
        englishSnapshot.recentThreads = zip(
            snapshot.recentThreads,
            englishThreadTitles
        ).map { thread, title in
            var localizedThread = thread
            localizedThread.title = title
            return localizedThread
        }
        let geometry = IslandDisplayGeometry(
            hasNotch: true,
            notchWidth: 185,
            topRegionHeight: 32
        )
        for bucket in snapshot.dailyThreadTokens {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: bucket.startDate) {
                snapshot.chartCreditTotals[date] = CodexChartCreditTotal(
                    tokens: Double(bucket.tokens), credits: Double(bucket.tokens) * 0.000068
                )
            }
        }
        if let todayTokens = snapshot.todayThreadTokens {
            snapshot.chartCreditTotals[Calendar.autoupdatingCurrent.startOfDay(for: Date())] =
                CodexChartCreditTotal(tokens: Double(todayTokens),
                                      credits: Double(todayTokens) * 0.000068)
        }
        // Today's daily and hourly previews use separate synthetic timelines.
        var hourlyCreditSnapshot = snapshot
        hourlyCreditSnapshot.chartCreditTotals = Dictionary(uniqueKeysWithValues:
            snapshot.hourlyThreadTokens.map { bucket in
                (bucket.hourStart, CodexChartCreditTotal(
                    tokens: Double(bucket.tokens), credits: Double(bucket.tokens) * 0.000068
                ))
            }
        )
        for hour in Array(snapshot.chartCreditTotals.keys) {
            snapshot.chartCreditTotals[hour]?.standardCredits /= 1.5
        }
        for hour in Array(hourlyCreditSnapshot.chartCreditTotals.keys) {
            hourlyCreditSnapshot.chartCreditTotals[hour]?.standardCredits /= 1.5
        }
        // Localized previews must use the same fully initialized chart data.
        englishSnapshot.chartCreditTotals = snapshot.chartCreditTotals
        let expandedSize = CGSize(
            width: IslandLayout.expandedWidth,
            height: IslandLayout.expandedBodyHeight + geometry.topRegionHeight
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: false,
            size: CGSize(
                width: IslandLayout.compactWidth(forNotchWidth: 185),
                height: IslandLayout.compactHeight(forTopRegionHeight: 32)
            ),
            to: compactURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: false,
            initialTokenConsumptionPhase: 0.46,
            size: CGSize(
                width: IslandLayout.compactWidth(forNotchWidth: 185),
                height: IslandLayout.compactHeight(forTopRegionHeight: 32)
            ),
            to: compactConsumingURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: false,
            initialTokenConsumptionPhase: 0.46,
            size: CGSize(
                width: IslandLayout.compactWidth(forNotchWidth: 185),
                height: IslandLayout.compactHeight(forTopRegionHeight: 32)
            ),
            scale: 1,
            to: compactConsuming1xURL
        )
        var compactBoundarySnapshot = snapshot
        compactBoundarySnapshot.todayThreadTokens = 9_999_999
        try render(
            snapshot: compactBoundarySnapshot,
            displayGeometry: geometry,
            expanded: false,
            initialTokenConsumptionPhase: 0.46,
            size: CGSize(
                width: IslandLayout.compactWidth(forNotchWidth: 185),
                height: IslandLayout.compactHeight(forTopRegionHeight: 32)
            ),
            to: compactBoundaryURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            size: expandedSize,
            to: expandedURL
        )
        var smallFastDeltaSnapshot = snapshot
        smallFastDeltaSnapshot.billedDailyThreadTokens = snapshot.dailyThreadTokens.map {
            DailyUsageBucket(
                startDate: $0.startDate,
                tokens: Int64((Double($0.tokens) * 1.02).rounded())
            )
        }
        smallFastDeltaSnapshot.billedTodayThreadTokens = Int64(
            (Double(snapshot.todayThreadTokens ?? 0) * 1.02).rounded()
        )
        try render(
            snapshot: smallFastDeltaSnapshot,
            displayGeometry: geometry,
            expanded: true,
            size: expandedSize,
            to: expandedSmallFastDeltaURL
        )
        try render(
            snapshot: hourlyCreditSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialTokenChartRange: .hours48,
            size: expandedSize,
            to: expandedHourlyURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            previewColorTheme: .tsinghua,
            size: expandedSize,
            to: expandedTsinghuaURL
        )
        for preview in companyThemePreviews {
            try render(
                snapshot: snapshot,
                displayGeometry: geometry,
                expanded: true,
                previewColorTheme: preview.theme,
                size: expandedSize,
                to: preview.url
            )
        }
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialIslandSettingsPresented: true,
            size: expandedSize,
            to: settingsURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            previewLanguagePreference: .english,
            size: expandedSize,
            to: expandedEnglishURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialIslandSettingsPresented: true,
            previewLanguagePreference: .english,
            size: expandedSize,
            to: settingsEnglishURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialIslandSettingsPresented: true,
            previewDisplayPickerPresentation: true,
            size: expandedSize,
            to: settingsDisplayMenuURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialIslandSettingsPresented: true,
            previewDisplayPickerPresentation: true,
            previewLanguagePreference: .english,
            size: expandedSize,
            to: settingsDisplayMenuEnglishURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialResetSummaryHover: true,
            previewLanguagePreference: .english,
            size: expandedSize,
            to: resetHoverEnglishURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredHeaderAction: .islandSettings,
            previewLanguagePreference: .chinese,
            size: expandedSize,
            to: headerIslandSettingsHoverURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredHeaderAction: .screenshot,
            previewLanguagePreference: .chinese,
            size: expandedSize,
            to: headerScreenshotHoverURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredHeaderAction: .codexSettings,
            previewLanguagePreference: .chinese,
            size: expandedSize,
            to: headerCodexSettingsHoverURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredHeaderAction: .quit,
            previewLanguagePreference: .chinese,
            size: expandedSize,
            to: headerQuitHoverURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredContextThreadID: "preview-2",
            size: expandedSize,
            to: contextHoverURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredContextThreadID: "preview-2",
            previewLanguagePreference: .english,
            size: expandedSize,
            to: contextHoverEnglishURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredTokenThreadID: "preview-2",
            size: expandedSize,
            to: hoverTopURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .english,
            size: expandedSize,
            to: hoverTopEnglishURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredTokenThreadID: "preview-3",
            size: expandedSize,
            to: hoverBottomURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialResetSummaryHover: true,
            previewLanguagePreference: .chinese,
            size: expandedSize,
            to: resetHoverURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredChartLegend: .modeEquivalent,
            previewLanguagePreference: .chinese,
            size: expandedSize,
            to: chartLegendHoverURL
        )
        try render(
            snapshot: englishSnapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredChartLegend: .modeEquivalent,
            previewLanguagePreference: .english,
            size: expandedSize,
            to: chartLegendHoverEnglishURL
        )

        func renderMatrixPreview(
            named fileName: String,
            snapshot previewSnapshot: CodexSnapshot,
            geometry previewGeometry: IslandDisplayGeometry = geometry,
            expanded: Bool = true,
            width: CGFloat = IslandLayout.expandedWidth,
            height: CGFloat? = nil,
            scale: CGFloat = 2,
            initialHoveredTokenThreadID: String? = nil,
            initialHoveredContextThreadID: String? = nil,
            initialResetSummaryHover: Bool = false,
            initialIslandSettingsPresented: Bool = false,
            previewLanguagePreference: IslandLanguagePreference? = nil,
            previewColorTheme: IslandColorTheme = .ocean
        ) throws {
            let url = directory.appendingPathComponent(fileName)
            let defaultHeight = expanded
                ? IslandLayout.expandedBodyHeight
                    + IslandLayout.expandedHeaderHeight(
                        forTopRegionHeight: previewGeometry.topRegionHeight
                    )
                : IslandLayout.compactHeight(
                    forTopRegionHeight: previewGeometry.topRegionHeight
                )
            try render(
                snapshot: previewSnapshot,
                displayGeometry: previewGeometry,
                expanded: expanded,
                initialHoveredTokenThreadID: initialHoveredTokenThreadID,
                initialHoveredContextThreadID: initialHoveredContextThreadID,
                initialResetSummaryHover: initialResetSummaryHover,
                initialIslandSettingsPresented: initialIslandSettingsPresented,
                previewLanguagePreference: previewLanguagePreference,
                previewColorTheme: previewColorTheme,
                size: CGSize(width: width, height: height ?? defaultHeight),
                scale: scale,
                to: url
            )
            outputURLs.append(url)
        }

        func snapshotWithThreadCount(_ count: Int) -> CodexSnapshot {
            var previewSnapshot = snapshot
            previewSnapshot.recentThreads = Array(snapshot.recentThreads.prefix(count))
            previewSnapshot.hasRunningSession = previewSnapshot.recentThreads.contains {
                $0.executionState == .running
            }
            return previewSnapshot
        }

        let noNotchGeometry = IslandDisplayGeometry(
            hasNotch: false,
            notchWidth: 0,
            topRegionHeight: 31
        )
        try renderMatrixPreview(
            named: "matrix-expanded-no-notch-threads-5-scale-2x.png",
            snapshot: snapshot,
            geometry: noNotchGeometry
        )
        try renderMatrixPreview(
            named: "matrix-compact-no-notch-scale-2x.png",
            snapshot: snapshot,
            geometry: noNotchGeometry,
            expanded: false,
            width: IslandLayout.compactFallbackWidth
        )

        for threadCount in [0, 1, 4, 5] {
            try renderMatrixPreview(
                named: "matrix-expanded-notch-threads-\(threadCount)-scale-2x.png",
                snapshot: snapshotWithThreadCount(threadCount)
            )
        }

        var noResetSnapshot = snapshot
        noResetSnapshot.resetCredits = nil
        try renderMatrixPreview(
            named: "matrix-expanded-notch-reset-none-scale-2x.png",
            snapshot: noResetSnapshot
        )

        var partialHistorySnapshot = snapshot
        if let todayTokens = snapshot.todayThreadTokens {
            partialHistorySnapshot.chartCreditTotals = [
                Calendar.autoupdatingCurrent.startOfDay(for: Date()):
                    CodexChartCreditTotal(tokens: Double(todayTokens / 2), credits: 1234.567)
            ]
        }
        try renderMatrixPreview(
            named: "matrix-expanded-chart-credits-partial-history.png",
            snapshot: partialHistorySnapshot
        )

        var noEstimateSnapshot = snapshot
        noEstimateSnapshot.remainingTokenEstimate = nil
        try renderMatrixPreview(
            named: "matrix-expanded-token-estimate-unavailable.png",
            snapshot: noEstimateSnapshot
        )
        var exhaustedQuotaSnapshot = snapshot
        exhaustedQuotaSnapshot.rateLimit?.primary?.usedPercent = 100
        exhaustedQuotaSnapshot.remainingTokenEstimate?.tokens = 0
        try renderMatrixPreview(
            named: "matrix-expanded-token-estimate-zero.png",
            snapshot: exhaustedQuotaSnapshot,
            previewLanguagePreference: .english
        )

        var lightReasoningSnapshot = snapshot
        lightReasoningSnapshot.recentThreads[0].reasoningEffort = "low"
        try renderMatrixPreview(
            named: "matrix-expanded-notch-reasoning-light-scale-2x.png",
            snapshot: lightReasoningSnapshot
        )

        var maxReasoningSnapshot = snapshot
        for index in maxReasoningSnapshot.recentThreads.indices {
            maxReasoningSnapshot.recentThreads[index].reasoningEffort = "max"
        }
        try renderMatrixPreview(
            named: "matrix-expanded-notch-reasoning-max-scale-2x.png",
            snapshot: maxReasoningSnapshot
        )

        var longIdentitySnapshot = snapshot
        longIdentitySnapshot.profileIdentity.displayName =
            "Codex Island · Visual Design Review"
        longIdentitySnapshot.account.planType = "enterprise-unlimited-organization"
        longIdentitySnapshot.rateLimit?.planType = "enterprise-unlimited-organization"
        try renderMatrixPreview(
            named: "matrix-expanded-notch-long-nickname-plan-scale-2x.png",
            snapshot: longIdentitySnapshot
        )

        try renderMatrixPreview(
            named: "matrix-expanded-notch-narrow-460pt-scale-2x.png",
            snapshot: snapshot,
            width: 460
        )
        try renderMatrixPreview(
            named: "matrix-expanded-notch-narrow-380pt-scale-2x.png",
            snapshot: snapshot,
            width: 380
        )

        var manyResetsSnapshot = snapshot
        manyResetsSnapshot.resetCredits = ResetCreditSummary(
            availableCount: 20,
            earliestExpiration: Date().addingTimeInterval(24 * 60 * 60),
            expirationDates: (1 ... 20).map { day in
                Date().addingTimeInterval(TimeInterval(day * 24 * 60 * 60))
            }
        )
        try renderMatrixPreview(
            named: "matrix-expanded-notch-reset-20-hover-scale-2x.png",
            snapshot: manyResetsSnapshot,
            initialResetSummaryHover: true
        )

        var hugeTokenSnapshot = snapshot
        hugeTokenSnapshot.todayThreadTokens = 1_234_567_890_123
        hugeTokenSnapshot.usage.lifetimeTokens = 9_876_543_210_987_654
        try renderMatrixPreview(
            named: "matrix-expanded-notch-token-units-large-scale-2x.png",
            snapshot: hugeTokenSnapshot
        )
        try renderMatrixPreview(
            named: "matrix-compact-notch-token-units-large-scale-2x.png",
            snapshot: hugeTokenSnapshot,
            expanded: false,
            width: IslandLayout.compactWidth(forNotchWidth: geometry.notchWidth)
        )

        var largeSessionTokenSnapshot = englishSnapshot
        largeSessionTokenSnapshot.recentThreads[1].tokenUsage = ThreadTokenUsage(
            inputTokens: 1_433_505_694,
            cachedInputTokens: 1_409_567_616,
            outputTokens: 3_051_868,
            reasoningOutputTokens: 1_077_695,
            totalTokens: 1_436_557_562,
            contextTokensUsed: 188_432,
            contextWindowTokens: 258_400,
            creditEstimate: CodexThreadCreditEstimate(credits: 57_251.889875)
        )
        try renderMatrixPreview(
            named: "matrix-expanded-notch-token-popover-large-english-scale-2x.png",
            snapshot: largeSessionTokenSnapshot,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .english
        )
        try renderMatrixPreview(
            named: "matrix-expanded-notch-token-popover-large-chinese-scale-2x.png",
            snapshot: largeSessionTokenSnapshot,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .chinese
        )

        var creditScreenshotSnapshot = englishSnapshot
        creditScreenshotSnapshot.recentThreads[1].model = "gpt-6-astra"
        creditScreenshotSnapshot.recentThreads[1].serviceTier = "default"
        creditScreenshotSnapshot.recentThreads[1].serviceTierSource = .recorded
        creditScreenshotSnapshot.recentThreads[1].tokenUsage = ThreadTokenUsage(
            inputTokens: 1_266_278, cachedInputTokens: 1_199_104,
            outputTokens: 6_717, reasoningOutputTokens: 1_835, totalTokens: 1_272_995,
            creditEstimate: CodexThreadCreditEstimate(credits: 55.16735)
        )
        try renderMatrixPreview(
            named: "matrix-expanded-token-credits-screenshot-english-scale-2x.png",
            snapshot: creditScreenshotSnapshot,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .english
        )
        try renderMatrixPreview(
            named: "matrix-expanded-token-credits-screenshot-chinese-scale-2x.png",
            snapshot: creditScreenshotSnapshot,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .chinese
        )
        try renderMatrixPreview(
            named: "matrix-expanded-token-credits-tsinghua-scale-2x.png",
            snapshot: creditScreenshotSnapshot,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .chinese,
            previewColorTheme: .tsinghua
        )
        creditScreenshotSnapshot.recentThreads[1].tokenUsage?.creditEstimate = nil
        try renderMatrixPreview(
            named: "matrix-expanded-token-credits-unavailable-scale-2x.png",
            snapshot: creditScreenshotSnapshot,
            initialHoveredTokenThreadID: "preview-2",
            previewLanguagePreference: .english
        )

        var headerWidthBoundarySnapshot = englishSnapshot
        headerWidthBoundarySnapshot.todayThreadTokens = 17_200_000
        headerWidthBoundarySnapshot.usage.lifetimeTokens = 14_100_000_000
        try renderMatrixPreview(
            named: "matrix-expanded-notch-header-width-english-scale-2x.png",
            snapshot: headerWidthBoundarySnapshot,
            initialIslandSettingsPresented: true,
            previewLanguagePreference: .english
        )
        try renderMatrixPreview(
            named: "matrix-expanded-notch-header-width-chinese-scale-2x.png",
            snapshot: headerWidthBoundarySnapshot,
            initialIslandSettingsPresented: true,
            previewLanguagePreference: .chinese
        )

        try renderMatrixPreview(
            named: "matrix-expanded-notch-threads-5-scale-1x.png",
            snapshot: snapshot,
            scale: 1
        )
        try renderMatrixPreview(
            named: "matrix-expanded-notch-threads-5-english-scale-1x.png",
            snapshot: englishSnapshot,
            scale: 1,
            previewLanguagePreference: .english
        )
        try renderMatrixPreview(
            named: "matrix-compact-notch-scale-1x.png",
            snapshot: snapshot,
            expanded: false,
            width: IslandLayout.compactWidth(forNotchWidth: geometry.notchWidth),
            scale: 1
        )
        try renderMatrixPreview(
            named: "matrix-compact-notch-scale-2x.png",
            snapshot: snapshot,
            expanded: false,
            width: IslandLayout.compactWidth(forNotchWidth: geometry.notchWidth)
        )

        return outputURLs
    }

    private static func previewDailyUsageBuckets(now: Date = Date()) -> [DailyUsageBucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let values: [Int64] = [
            8, 23, 17, 41, 72, 38, 93, 61, 0, 27,
            49, 82, 34, 56, 18, 104, 76, 44, 121, 88,
            32, 67, 145, 91, 53, 116, 74, 158, 126, 97
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return values.enumerated().compactMap { index, value in
            guard let date = calendar.date(
                byAdding: .day,
                value: index - values.count,
                to: today
            ) else {
                return nil
            }
            return DailyUsageBucket(
                startDate: formatter.string(from: date),
                tokens: value * 1_000_000
            )
        }
    }

    private static func previewHourlyUsageBuckets(
        now: Date = Date()
    ) -> [HourlyUsageBucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        guard let currentHour = calendar.dateInterval(of: .hour, for: now)?.start else {
            return []
        }
        let values: [Int64] = [
            3, 0, 7, 11, 5, 0, 18, 26, 14, 9, 4, 0,
            2, 6, 13, 21, 34, 19, 8, 0, 5, 12, 25, 41,
            28, 17, 6, 0, 9, 15, 31, 46, 23, 12, 7, 3,
            0, 8, 20, 37, 52, 29, 16, 10, 4, 13, 32, 24
        ]
        return values.enumerated().compactMap { index, value in
            calendar.date(
                byAdding: .hour,
                value: index - (values.count - 1),
                to: currentHour
            ).map {
                HourlyUsageBucket(
                    hourStart: $0,
                    tokens: value * 1_000_000
                )
            }
        }
    }

    private static func previewBilledDailyUsageBuckets(
        now: Date = Date()
    ) -> [DailyUsageBucket] {
        previewDailyUsageBuckets(now: now).enumerated().map { index, bucket in
            let multiplier = index.isMultiple(of: 3) ? 2.5 : 1.45
            return DailyUsageBucket(
                startDate: bucket.startDate,
                tokens: Int64((Double(bucket.tokens) * multiplier).rounded())
            )
        }
    }

    private static func previewBilledHourlyUsageBuckets(
        now: Date = Date()
    ) -> [HourlyUsageBucket] {
        previewHourlyUsageBuckets(now: now).enumerated().map { index, bucket in
            let multiplier = index.isMultiple(of: 4) ? 2.5 : 1.35
            return HourlyUsageBucket(
                hourStart: bucket.hourStart,
                tokens: Int64((Double(bucket.tokens) * multiplier).rounded())
            )
        }
    }

    private static func render(
        snapshot: CodexSnapshot,
        displayGeometry: IslandDisplayGeometry,
        expanded: Bool,
        initialHoveredTokenThreadID: String? = nil,
        initialHoveredContextThreadID: String? = nil,
        initialResetSummaryHover: Bool = false,
        initialHoveredChartLegend: TokenChartLegendKind? = nil,
        initialIslandSettingsPresented: Bool = false,
        previewDisplayPickerPresentation: Bool? = nil,
        initialHoveredHeaderAction: IslandHeaderAction? = nil,
        initialTokenConsumptionPhase: Double? = nil,
        initialTokenChartRange: TokenChartRange = .days30,
        previewLanguagePreference: IslandLanguagePreference? = nil,
        previewColorTheme: IslandColorTheme = .ocean,
        size: CGSize,
        scale: CGFloat = 2,
        to url: URL
    ) throws {
        let viewModel = CodexStatusViewModel(initialSnapshot: snapshot)
        viewModel.isExpanded = expanded
        let displaySelection = IslandDisplaySelectionModel(
            initialPreference: .automatic,
            previewDisplays: [
                IslandDisplayDescriptor(
                    identifier: "preview-built-in",
                    name: "Built-in Retina Display",
                    isBuiltIn: true,
                    sortIndex: 0
                ),
                IslandDisplayDescriptor(
                    identifier: "preview-external",
                    name: "HP Z27s",
                    isBuiltIn: false,
                    sortIndex: 1
                )
            ]
        )
        let view = IslandView(
            viewModel: viewModel,
            displayGeometry: displayGeometry,
            displaySelection: displaySelection,
            initialHoveredTokenThreadID: initialHoveredTokenThreadID,
            initialHoveredContextThreadID: initialHoveredContextThreadID,
            initialResetSummaryHover: initialResetSummaryHover,
            initialHoveredChartLegend: initialHoveredChartLegend,
            initialIslandSettingsPresented: initialIslandSettingsPresented,
            previewDisplayPickerPresentation: previewDisplayPickerPresentation,
            initialHoveredHeaderAction: initialHoveredHeaderAction,
            initialTokenConsumptionPhase: initialTokenConsumptionPhase,
            initialTokenChartRange: initialTokenChartRange,
            previewLanguagePreference: previewLanguagePreference,
            previewColorTheme: previewColorTheme,
            launchAtLoginBackend: .previewDisabled,
            usesTimelineUpdates: false
        )
            .frame(width: size.width, height: size.height)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.renderFailed
        }
        try png.write(to: url, options: .atomic)
    }

    private enum PreviewError: LocalizedError {
        case renderFailed

        var errorDescription: String? {
            "无法渲染 Codex Island 预览图"
        }
    }
}
