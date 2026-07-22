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

        let snapshot = CodexSnapshot(
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
                avatarData: nil
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
                        totalTokens: 2_949_508
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
                        totalTokens: 152_927_611
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
                        totalTokens: 241_776
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
                        totalTokens: 31_001_538
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
            hasRunningSession: true,
            activeModel: ModelSummary(
                id: "gpt-5.6-sol",
                displayName: "GPT-5.6 Sol",
                isDefault: true
            ),
            lastUpdated: Date(),
            warning: nil
        )

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
        let settingsURL = directory.appendingPathComponent(
            "codex-island-expanded-settings.png"
        )
        let expandedEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-english.png"
        )
        let settingsEnglishURL = directory.appendingPathComponent(
            "codex-island-expanded-settings-english.png"
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
        let headerCodexSettingsHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-header-codex-settings-hover.png"
        )
        let hoverTopURL = directory.appendingPathComponent(
            "codex-island-expanded-token-hover-top.png"
        )
        let hoverBottomURL = directory.appendingPathComponent(
            "codex-island-expanded-token-hover-bottom.png"
        )
        let resetHoverURL = directory.appendingPathComponent(
            "codex-island-expanded-reset-hover.png"
        )
        var outputURLs = [
            compactURL,
            compactConsumingURL,
            compactBoundaryURL,
            compactConsuming1xURL,
            expandedURL,
            settingsURL,
            expandedEnglishURL,
            settingsEnglishURL,
            resetHoverEnglishURL,
            headerIslandSettingsHoverURL,
            headerCodexSettingsHoverURL,
            headerQuitHoverURL,
            hoverTopURL,
            hoverBottomURL,
            resetHoverURL
        ]
        let geometry = IslandDisplayGeometry(
            hasNotch: true,
            notchWidth: 185,
            topRegionHeight: 32
        )
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
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialIslandSettingsPresented: true,
            size: expandedSize,
            to: settingsURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            previewLanguagePreference: .english,
            size: expandedSize,
            to: expandedEnglishURL
        )
        try render(
            snapshot: snapshot,
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
            initialHoveredTokenThreadID: "preview-1",
            size: expandedSize,
            to: hoverTopURL
        )
        try render(
            snapshot: snapshot,
            displayGeometry: geometry,
            expanded: true,
            initialHoveredTokenThreadID: "preview-4",
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

        func renderMatrixPreview(
            named fileName: String,
            snapshot previewSnapshot: CodexSnapshot,
            geometry previewGeometry: IslandDisplayGeometry = geometry,
            expanded: Bool = true,
            width: CGFloat = IslandLayout.expandedWidth,
            height: CGFloat? = nil,
            scale: CGFloat = 2,
            initialHoveredTokenThreadID: String? = nil,
            initialResetSummaryHover: Bool = false,
            initialIslandSettingsPresented: Bool = false,
            previewLanguagePreference: IslandLanguagePreference? = nil
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
                initialResetSummaryHover: initialResetSummaryHover,
                initialIslandSettingsPresented: initialIslandSettingsPresented,
                previewLanguagePreference: previewLanguagePreference,
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

        var minimalReasoningSnapshot = snapshot
        minimalReasoningSnapshot.recentThreads[0].reasoningEffort = "minimal"
        try renderMatrixPreview(
            named: "matrix-expanded-notch-reasoning-minimal-scale-2x.png",
            snapshot: minimalReasoningSnapshot
        )

        var longIdentitySnapshot = snapshot
        longIdentitySnapshot.profileIdentity.displayName =
            "Codex Island · Codex Visual Design Review"
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

        try renderMatrixPreview(
            named: "matrix-expanded-notch-threads-5-scale-1x.png",
            snapshot: snapshot,
            scale: 1
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

    private static func render(
        snapshot: CodexSnapshot,
        displayGeometry: IslandDisplayGeometry,
        expanded: Bool,
        initialHoveredTokenThreadID: String? = nil,
        initialResetSummaryHover: Bool = false,
        initialIslandSettingsPresented: Bool = false,
        initialHoveredHeaderAction: IslandHeaderAction? = nil,
        initialTokenConsumptionPhase: Double? = nil,
        previewLanguagePreference: IslandLanguagePreference? = nil,
        size: CGSize,
        scale: CGFloat = 2,
        to url: URL
    ) throws {
        let viewModel = CodexStatusViewModel(initialSnapshot: snapshot)
        viewModel.isExpanded = expanded
        let view = IslandView(
            viewModel: viewModel,
            displayGeometry: displayGeometry,
            initialHoveredTokenThreadID: initialHoveredTokenThreadID,
            initialResetSummaryHover: initialResetSummaryHover,
            initialIslandSettingsPresented: initialIslandSettingsPresented,
            initialHoveredHeaderAction: initialHoveredHeaderAction,
            initialTokenConsumptionPhase: initialTokenConsumptionPhase,
            previewLanguagePreference: previewLanguagePreference,
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
