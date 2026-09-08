import AppKit
import SwiftUI

private let creditsGold = Color(red: 1, green: 215.0 / 255, blue: 0)

private func localizedCredits(_ text: String, language: IslandInterfaceLanguage) -> String {
    text.replacingOccurrences(of: "credits", with: language.text("额度点", "credits"))
}

enum IslandLayout {
    static let compactMinimumWidth: CGFloat = 300
    static let compactExtraWidth: CGFloat = 115
    static let compactFallbackWidth: CGFloat = 160
    static let compactFallbackHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 500
    static let contentHorizontalInset: CGFloat = 14
    static let metricCenterGutter: CGFloat = 10
    static let conversationRowHeight: CGFloat = 28
    static let activityChartBarSpacing: CGFloat = 2
    static let hourlyActivityChartBarSpacing: CGFloat = 1.5
    static let activityIndicatorSlotWidth: CGFloat = 10
    static let threadSourceColumnWidth: CGFloat = 28
    static let threadTrailingColumnWidth: CGFloat = 70
    static let compactThreadTrailingColumnWidth: CGFloat = 46
    static let compactTokenEffectWidth: CGFloat = 9.5
    static let headerActionButtonSize: CGFloat = 28
    static let headerActionSpacing: CGFloat = 4
    static let headerTooltipCursorGap: CGFloat = 4
    static let headerTooltipTopGap: CGFloat = 2
    static let recentConversationsHeight = conversationRowHeight
        * CGFloat(CodexDisplayPolicy.recentThreadLimit)
    static let expandedMetricsHeight: CGFloat = 210
    static let expandedSeparatorHeight: CGFloat = 1
    static let expandedBottomPadding: CGFloat = 14
    static let expandedBodyHeight: CGFloat = expandedMetricsHeight
        + recentConversationsHeight
        + expandedSeparatorHeight * 2
        + expandedBottomPadding

    static func compactWidth(forNotchWidth notchWidth: CGFloat) -> CGFloat {
        max(compactMinimumWidth, notchWidth + compactExtraWidth)
    }

    static func compactHeight(forTopRegionHeight topRegionHeight: CGFloat) -> CGFloat {
        topRegionHeight > 0 ? topRegionHeight : compactFallbackHeight
    }

    static func expandedHeaderHeight(forTopRegionHeight topRegionHeight: CGFloat) -> CGFloat {
        topRegionHeight > 0 ? topRegionHeight : compactFallbackHeight
    }
}

private func quotaRemainingColor(
    _ remainingPercent: Double?,
    unavailableColor: Color
) -> Color {
    guard let remainingPercent else { return unavailableColor }
    switch CodexDisplayPolicy.quotaRemainingLevel(for: remainingPercent) {
    case .healthy: return .green
    case .warning: return .yellow
    case .critical: return .red
    }
}

private enum IslandTypography {
    /// The former task-title size is now the readability floor for UI copy.
    static let body: CGFloat = 11.5
    static let emphasized: CGFloat = 12.5
    static let profileName: CGFloat = 15.5
    static let display: CGFloat = 24
    static let settingBadge: CGFloat = 10
}

private enum IslandCoordinateSpace {
    static let name = "codex-island"
}

enum IslandHeaderAction: Sendable {
    case islandSettings
    case screenshot
    case codexSettings
    case quit
}

enum TokenChartLegendKind: String, Equatable, Sendable {
    case actual
    case modeEquivalent

    func title(for language: IslandInterfaceLanguage, credits: Bool = false) -> String {
        if credits {
            return self == .actual ? language.text("标准", "Standard")
                : language.text("⚡实际", "⚡ Actual")
        }
        switch self {
        case .actual:
            return language.text("实际", "Actual")
        case .modeEquivalent:
            return language.text("⚡等效", "⚡ Equivalent")
        }
    }

    func explanation(for language: IslandInterfaceLanguage, credits: Bool = false) -> String {
        if credits {
            return self == .actual
                ? language.text("标准是在不开启 Fast 模式时，相同本机用量按各次调用模型费率计算的额度点。实际 − 标准代表开启 Fast 浪费的额度。",
                                "Standard is the credit cost of the same local usage with Fast off. Actual minus Standard is the extra credit cost of enabling Fast.")
                : language.text("实际是按本机各次调用的模型和 Fast 模式计算的总消耗，包含标准用量。实际 − 标准代表开启 Fast 浪费的额度。两项同时显示时，实心为标准，空心轮廓为实际总量。",
                                "Actual is the total local credit cost, including Standard and Fast surcharges. Actual minus Standard is the extra cost of enabling Fast. The solid bar shows Standard; the outline shows the Actual total.")
        }
        switch self {
        case .actual:
            return language.text(
                "模型的实际词元用量，开启或关闭 Fast 模式都相同。",
                "The number of tokens processed by the model. Fast mode does not change this value."
            )
        case .modeEquivalent:
            return language.text(
                "开启 Fast 不会改变词元用量，但是额度消耗会变快。该数据通过对应模型开启 Fast 时的消耗倍率，估算关闭 Fast 模式时理论上等效可以用多少词元（简单说，等效 − 实际就是开启 Fast 大概浪费了多少本来可以用的词元）。",
                "Fast mode does not change token usage, but it makes usage limits drain faster. Using each model's Fast consumption multiplier, this value estimates how many tokens could theoretically be used with Fast mode off—in simple terms, roughly how many otherwise usable tokens were given up by enabling Fast."
            )
        }
    }
}

private func activityIndicatorOffset(
    rowWidth: CGFloat,
    bucketCount: Int
) -> CGFloat {
    guard bucketCount > 0 else { return -2 }
    let spacing = bucketCount > 30
        ? IslandLayout.hourlyActivityChartBarSpacing
        : IslandLayout.activityChartBarSpacing
    let totalSpacing = spacing
        * CGFloat(max(0, bucketCount - 1))
    let barWidth = max(0, (rowWidth - totalSpacing) / CGFloat(bucketCount))
    return barWidth / 2 - IslandLayout.activityIndicatorSlotWidth / 2
}

private struct IslandStatusAnimationsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct IslandTokenConsumptionEffectEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct IslandInterfaceLanguageKey: EnvironmentKey {
    static let defaultValue = IslandInterfaceLanguage.english
}

private struct IslandColorThemeKey: EnvironmentKey {
    static let defaultValue = IslandColorTheme.ocean
}

private extension EnvironmentValues {
    var islandStatusAnimationsEnabled: Bool {
        get { self[IslandStatusAnimationsEnabledKey.self] }
        set { self[IslandStatusAnimationsEnabledKey.self] = newValue }
    }

    var islandTokenConsumptionEffectEnabled: Bool {
        get { self[IslandTokenConsumptionEffectEnabledKey.self] }
        set { self[IslandTokenConsumptionEffectEnabledKey.self] = newValue }
    }

    var islandInterfaceLanguage: IslandInterfaceLanguage {
        get { self[IslandInterfaceLanguageKey.self] }
        set { self[IslandInterfaceLanguageKey.self] = newValue }
    }

    var islandColorTheme: IslandColorTheme {
        get { self[IslandColorThemeKey.self] }
        set { self[IslandColorThemeKey.self] = newValue }
    }
}

private struct IslandPopoverPlacement {
    let center: CGPoint
    let scale: CGFloat
}

private enum IslandPopoverContent: Equatable {
    case token(threadID: String, rank: Int, usage: ThreadTokenUsage)
    case context(threadID: String, rank: Int, usage: ThreadTokenUsage?)
    case reset(ResetCreditSummary)
    case chartLegend(TokenChartLegendKind)

    var identity: String {
        switch self {
        case .token(let threadID, _, _): return "token-\(threadID)"
        case .context(let threadID, _, _): return "context-\(threadID)"
        case .reset: return "reset"
        case .chartLegend(let kind): return "chart-legend-\(kind.rawValue)"
        }
    }

    func size(for language: IslandInterfaceLanguage) -> CGSize {
        switch self {
        case .token(_, _, let usage):
            return TokenUsageDetailPopover.size(
                for: usage,
                language: language
            )
        case .context: return ContextWindowPopover.size
        case .reset(let summary):
            return ResetExpirationPopover.size(
                for: summary,
                language: language
            )
        case .chartLegend(let kind):
            return TokenChartLegendPopover.size(for: kind, language: language)
        }
    }
}

private struct IslandPopoverPresentation: Equatable {
    let content: IslandPopoverContent
    var pointer: CGPoint?
}

private func islandPopoverPlacement(
    pointer: CGPoint,
    popoverSize: CGSize,
    canvasSize: CGSize,
    displayScale: CGFloat,
    margin: CGFloat = 7,
    pointerGap: CGFloat = 8
) -> IslandPopoverPlacement {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
        return IslandPopoverPlacement(center: pointer, scale: 1)
    }

    let availableWidth = max(1, canvasSize.width - margin * 2)
    let availableHeight = max(1, canvasSize.height - margin * 2)
    let fittedScale = min(
        1,
        availableWidth / max(1, popoverSize.width),
        availableHeight / max(1, popoverSize.height)
    )
    let scaledWidth = popoverSize.width * fittedScale
    let scaledHeight = popoverSize.height * fittedScale

    let leftCenter = pointer.x - pointerGap - scaledWidth / 2
    let rightCenter = pointer.x + pointerGap + scaledWidth / 2
    let prefersLeft = leftCenter - scaledWidth / 2 >= margin
    let desiredX = prefersLeft ? leftCenter : rightCenter
    let desiredY = pointer.y

    func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(upper, max(lower, value))
    }

    let center = CGPoint(
        x: clamp(
            desiredX,
            lower: margin + scaledWidth / 2,
            upper: canvasSize.width - margin - scaledWidth / 2
        ),
        y: clamp(
            desiredY,
            lower: margin + scaledHeight / 2,
            upper: canvasSize.height - margin - scaledHeight / 2
        )
    )
    let scale = max(1, displayScale)
    return IslandPopoverPlacement(
        center: CGPoint(
            x: (center.x * scale).rounded() / scale,
            y: (center.y * scale).rounded() / scale
        ),
        scale: fittedScale
    )
}

private func islandCursorTooltipPlacement(
    pointer: CGPoint,
    tooltipSize: CGSize,
    canvasSize: CGSize,
    displayScale: CGFloat,
    margin: CGFloat = 7,
    cursorGap: CGFloat,
    minimumTop: CGFloat
) -> IslandPopoverPlacement {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
        return IslandPopoverPlacement(center: pointer, scale: 1)
    }

    let availableWidth = max(1, canvasSize.width - margin * 2)
    let availableHeight = max(1, canvasSize.height - margin * 2)
    let fittedScale = min(
        1,
        availableWidth / max(1, tooltipSize.width),
        availableHeight / max(1, tooltipSize.height)
    )
    let scaledWidth = tooltipSize.width * fittedScale
    let scaledHeight = tooltipSize.height * fittedScale

    let cursor = NSCursor.current
    let cursorSize = cursor.image.size
    let hotSpot = cursor.hotSpot
    let cursorLeft = pointer.x - min(max(0, hotSpot.x), cursorSize.width)
    let cursorRight = cursorLeft + max(0, cursorSize.width)
    let leftCenter = cursorLeft - cursorGap - scaledWidth / 2
    let rightCenter = cursorRight + cursorGap + scaledWidth / 2
    let prefersLeft = leftCenter - scaledWidth / 2 >= margin
    let desiredX = prefersLeft ? leftCenter : rightCenter
    let desiredY = max(minimumTop, pointer.y + cursorGap)
        + scaledHeight / 2

    func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(upper, max(lower, value))
    }

    let center = CGPoint(
        x: clamp(
            desiredX,
            lower: margin + scaledWidth / 2,
            upper: canvasSize.width - margin - scaledWidth / 2
        ),
        y: clamp(
            desiredY,
            lower: margin + scaledHeight / 2,
            upper: canvasSize.height - margin - scaledHeight / 2
        )
    )
    let scale = max(1, displayScale)
    return IslandPopoverPlacement(
        center: CGPoint(
            x: (center.x * scale).rounded() / scale,
            y: (center.y * scale).rounded() / scale
        ),
        scale: fittedScale
    )
}

private func islandChartLegendPopoverPlacement(
    pointer: CGPoint,
    popoverSize: CGSize,
    canvasSize: CGSize,
    displayScale: CGFloat,
    margin: CGFloat = 7,
    cursorGap: CGFloat = 6
) -> IslandPopoverPlacement {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
        return IslandPopoverPlacement(center: pointer, scale: 1)
    }

    let cursor = NSCursor.current
    let cursorSize = cursor.image.size
    let hotSpot = cursor.hotSpot
    let cursorTop = pointer.y - min(max(0, hotSpot.y), cursorSize.height)
    let cursorBottom = cursorTop + max(0, cursorSize.height)
    let belowCenter = cursorBottom + cursorGap + popoverSize.height / 2
    let aboveCenter = cursorTop - cursorGap - popoverSize.height / 2
    let canFitBelow = belowCenter + popoverSize.height / 2
        <= canvasSize.height - margin
    let desiredY = canFitBelow ? belowCenter : aboveCenter

    func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(upper, max(lower, value))
    }

    let center = CGPoint(
        x: clamp(
            pointer.x,
            lower: margin + popoverSize.width / 2,
            upper: canvasSize.width - margin - popoverSize.width / 2
        ),
        y: clamp(
            desiredY,
            lower: margin + popoverSize.height / 2,
            upper: canvasSize.height - margin - popoverSize.height / 2
        )
    )
    let scale = max(1, displayScale)
    return IslandPopoverPlacement(
        center: CGPoint(
            x: (center.x * scale).rounded() / scale,
            y: (center.y * scale).rounded() / scale
        ),
        scale: 1
    )
}

private func islandDefaultTokenPopoverPointer(rank: Int, canvasSize: CGSize) -> CGPoint {
    let rowsTop = canvasSize.height
        - IslandLayout.expandedBottomPadding
        - IslandLayout.recentConversationsHeight
    return CGPoint(
        x: canvasSize.width - 80,
        y: rowsTop + (CGFloat(rank) + 0.5) * IslandLayout.conversationRowHeight
    )
}

private func islandDefaultContextPopoverPointer(
    rank: Int,
    canvasSize: CGSize
) -> CGPoint {
    let rowsTop = canvasSize.height
        - IslandLayout.expandedBottomPadding
        - IslandLayout.recentConversationsHeight
    return CGPoint(
        x: canvasSize.width * 0.57,
        y: rowsTop + (CGFloat(rank) + 0.5) * IslandLayout.conversationRowHeight
    )
}

private func islandDefaultResetPopoverPointer(
    topRegionHeight: CGFloat,
    canvasSize: CGSize
) -> CGPoint {
    CGPoint(
        x: canvasSize.width / 2 + IslandLayout.metricCenterGutter,
        y: IslandLayout.expandedHeaderHeight(
            forTopRegionHeight: topRegionHeight
        ) + 63
    )
}

private func islandDefaultChartLegendPopoverPointer(
    topRegionHeight: CGFloat,
    canvasSize: CGSize
) -> CGPoint {
    CGPoint(
        x: canvasSize.width * 0.69,
        y: IslandLayout.expandedHeaderHeight(
            forTopRegionHeight: topRegionHeight
        ) + 105
    )
}

@MainActor
final class IslandDisplayGeometry: ObservableObject {
    @Published private(set) var hasNotch: Bool
    @Published private(set) var notchWidth: CGFloat
    @Published private(set) var topRegionHeight: CGFloat

    init(
        hasNotch: Bool = false,
        notchWidth: CGFloat = 132,
        topRegionHeight: CGFloat = IslandLayout.compactFallbackHeight
    ) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.topRegionHeight = topRegionHeight
    }

    func update(
        hasNotch: Bool,
        notchWidth: CGFloat,
        topRegionHeight: CGFloat
    ) {
        guard self.hasNotch != hasNotch
                || self.notchWidth != notchWidth
                || self.topRegionHeight != topRegionHeight else { return }
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.topRegionHeight = topRegionHeight
    }

}

@MainActor
private enum TaskSoundPlayer {
    private static let completionSound: NSSound? = {
        let url = Bundle.module.url(
            forResource: "TaskCompletion8Bit",
            withExtension: "wav"
        ) ?? Bundle.module.url(
            forResource: "TaskCompletion",
            withExtension: "mp3"
        )
        guard let url else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: false)
    }()

    private static let approvalSound: NSSound? = {
        guard let url = Bundle.module.url(
            forResource: "TaskApprovalAlert",
            withExtension: "wav"
        ) else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: false)
    }()

    static func playCompletion() {
        play(completionSound)
    }

    static func playApproval() {
        play(approvalSound)
    }

    private static func play(_ sound: NSSound?) {
        sound?.stop()
        if sound?.play() != true {
            NSSound.beep()
        }
    }
}

struct IslandView: View {
    @ObservedObject var viewModel: CodexStatusViewModel
    @ObservedObject var displayGeometry: IslandDisplayGeometry
    @ObservedObject var displaySelection: IslandDisplaySelectionModel
    @Environment(\.displayScale) private var displayScale
    @AppStorage("codexIsland.statusAnimationsEnabled")
    private var statusAnimationsEnabled = true
    @AppStorage("codexIsland.tokenConsumptionEffectEnabled")
    private var tokenConsumptionEffectEnabled = true
    @AppStorage("codexIsland.completionSoundEnabled")
    private var completionSoundEnabled = false
    @AppStorage("codexIsland.languagePreference")
    private var storedLanguagePreference = IslandLanguagePreference.automatic.rawValue
    @AppStorage(IslandColorTheme.storageKey)
    private var storedColorTheme = IslandColorTheme.ocean.rawValue
    @State private var launchAtLoginSetting: LaunchAtLoginSettingModel
    @State private var activePopover: IslandPopoverPresentation?
    @State private var isIslandSettingsPresented = false
    @State private var hoveredHeaderAction: IslandHeaderAction?
    @State private var headerTooltipPointer: CGPoint?
    @State private var screenshotCopied = false
    @State private var tokenChartRange: TokenChartRange
    @State private var previousThreadStates: [String: ThreadExecutionState]
    private let initialPopover: IslandPopoverPresentation?
    private let initialTokenConsumptionPhase: Double?
    private let previewDisplayPickerPresentation: Bool?
    private let previewLanguagePreference: IslandLanguagePreference?
    private let previewColorTheme: IslandColorTheme?
    private let onCopyScreenshot: () -> Bool
    private let usesTimelineUpdates: Bool

    init(
        viewModel: CodexStatusViewModel,
        displayGeometry: IslandDisplayGeometry,
        displaySelection: IslandDisplaySelectionModel,
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
        previewColorTheme: IslandColorTheme? = nil,
        launchAtLoginBackend: LaunchAtLoginBackend = .live,
        onCopyScreenshot: @escaping () -> Bool = { false },
        usesTimelineUpdates: Bool = true
    ) {
        self.viewModel = viewModel
        self.displayGeometry = displayGeometry
        self.displaySelection = displaySelection
        self.initialTokenConsumptionPhase = initialTokenConsumptionPhase
        self.previewDisplayPickerPresentation = previewDisplayPickerPresentation
        _tokenChartRange = State(initialValue: initialTokenChartRange)
        _previousThreadStates = State(
            initialValue: Self.threadStates(
                from: viewModel.snapshot.recentThreads
            )
        )
        self.previewLanguagePreference = previewLanguagePreference
        self.previewColorTheme = previewColorTheme
        self.onCopyScreenshot = onCopyScreenshot
        self.usesTimelineUpdates = usesTimelineUpdates
        _launchAtLoginSetting = State(
            initialValue: LaunchAtLoginSettingModel(
                backend: launchAtLoginBackend
            )
        )

        let visibleThreads = CodexDisplayPolicy.visibleRecentThreads(
            from: viewModel.snapshot.recentThreads
        )
        if let threadID = initialHoveredContextThreadID,
           let rank = visibleThreads.firstIndex(where: {
               $0.id == threadID
           }) {
            self.initialPopover = IslandPopoverPresentation(
                content: .context(
                    threadID: threadID,
                    rank: rank,
                    usage: visibleThreads[rank].tokenUsage
                ),
                pointer: nil
            )
        } else if let threadID = initialHoveredTokenThreadID,
           let rank = visibleThreads.firstIndex(where: {
               $0.id == threadID
           }),
           let usage = visibleThreads[rank].tokenUsage {
            self.initialPopover = IslandPopoverPresentation(
                content: .token(threadID: threadID, rank: rank, usage: usage),
                pointer: nil
            )
        } else if initialResetSummaryHover,
                  let summary = viewModel.snapshot.resetCredits {
            self.initialPopover = IslandPopoverPresentation(
                content: .reset(summary),
                pointer: nil
            )
        } else if let initialHoveredChartLegend {
            self.initialPopover = IslandPopoverPresentation(
                content: .chartLegend(initialHoveredChartLegend),
                pointer: nil
            )
        } else {
            self.initialPopover = nil
        }
        _activePopover = State(initialValue: nil)
        _isIslandSettingsPresented = State(
            initialValue: initialIslandSettingsPresented
        )
        _hoveredHeaderAction = State(initialValue: initialHoveredHeaderAction)
        _headerTooltipPointer = State(initialValue: nil)
    }

    var body: some View {
        GeometryReader { canvas in
            ZStack {
                islandShape
                    .fill(Color(red: 0.012, green: 0.014, blue: 0.019))

                if viewModel.isExpanded {
                    expandedContent
                        .transition(
                            usesTimelineUpdates
                                ? .opacity.animation(
                                    .easeOut(duration: 0.14).delay(0.08)
                                )
                                : .identity
                        )

                    islandPopoverLayer(canvasSize: canvas.size)
                    headerTooltipLayer(canvasSize: canvas.size)
                } else {
                    compactContent
                        .transition(
                            usesTimelineUpdates
                                ? .opacity.animation(.easeOut(duration: 0.08))
                                : .identity
                        )
                }
            }
            .environment(
                \.islandStatusAnimationsEnabled,
                usesTimelineUpdates && statusAnimationsEnabled
            )
            .environment(
                \.islandTokenConsumptionEffectEnabled,
                usesTimelineUpdates && tokenConsumptionEffectEnabled
            )
            .environment(\.islandInterfaceLanguage, interfaceLanguage)
            .environment(\.islandColorTheme, selectedColorTheme)
            .coordinateSpace(name: IslandCoordinateSpace.name)
            .clipShape(islandShape)
            .contentShape(islandShape)
            .animation(
                usesTimelineUpdates
                    ? .timingCurve(
                        0.16,
                        1,
                        0.30,
                        1,
                        duration: viewModel.isExpanded ? 0.28 : 0.20
                    )
                    : nil,
                value: viewModel.isExpanded
            )
        }
        .onChange(of: viewModel.isExpanded) { expanded in
            if !expanded {
                activePopover = nil
                isIslandSettingsPresented = false
                hoveredHeaderAction = nil
                headerTooltipPointer = nil
            }
        }
        .onChange(of: viewModel.snapshot.recentThreads) { threads in
            handleThreadStateChanges(threads)
        }
    }

    private static func threadStates(
        from threads: [ThreadSummary]
    ) -> [String: ThreadExecutionState] {
        Dictionary(uniqueKeysWithValues: threads.map {
            ($0.id, $0.executionState)
        })
    }

    private func handleThreadStateChanges(_ threads: [ThreadSummary]) {
        let inputRequestedThreadIDs = CodexDisplayPolicy.inputRequestedThreadIDs(
            previousStates: previousThreadStates,
            currentThreads: threads
        )
        let completedThreadIDs = CodexDisplayPolicy.completedThreadIDs(
            previousStates: previousThreadStates,
            currentThreads: threads
        )
        previousThreadStates = Self.threadStates(from: threads)

        guard usesTimelineUpdates,
              completionSoundEnabled else {
            return
        }
        if !inputRequestedThreadIDs.isEmpty {
            TaskSoundPlayer.playApproval()
        } else if !completedThreadIDs.isEmpty {
            TaskSoundPlayer.playCompletion()
        }
    }

    private var islandShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: viewModel.isExpanded ? 26 : 20,
            style: .circular
        )
    }

    private func islandPopoverLayer(canvasSize: CGSize) -> some View {
        GeometryReader { _ in
            if let displayedPopover = activePopover ?? initialPopover {
                let pointer = displayedPopover.pointer
                    ?? defaultPopoverPointer(
                        for: displayedPopover.content,
                        canvasSize: canvasSize
                    )
                let popoverSize = displayedPopover.content.size(
                    for: interfaceLanguage
                )
                let placement = popoverPlacement(
                    for: displayedPopover.content,
                    pointer: pointer,
                    popoverSize: popoverSize,
                    canvasSize: canvasSize
                )

                popoverView(for: displayedPopover.content)
                    .id(displayedPopover.content.identity)
                    .scaleEffect(placement.scale)
                    .position(placement.center)
            }
        }
        .allowsHitTesting(false)
    }

    private func popoverPlacement(
        for content: IslandPopoverContent,
        pointer: CGPoint,
        popoverSize: CGSize,
        canvasSize: CGSize
    ) -> IslandPopoverPlacement {
        if case .chartLegend = content {
            return islandChartLegendPopoverPlacement(
                pointer: pointer,
                popoverSize: popoverSize,
                canvasSize: canvasSize,
                displayScale: displayScale
            )
        }
        return islandPopoverPlacement(
            pointer: pointer,
            popoverSize: popoverSize,
            canvasSize: canvasSize,
            displayScale: displayScale
        )
    }

    private func headerTooltipLayer(canvasSize: CGSize) -> some View {
        GeometryReader { _ in
            if let action = hoveredHeaderAction {
                let text = headerTooltipText(for: action)
                let tooltipSize = IslandHeaderTooltip.size(
                    for: text,
                    displayScale: displayScale
                )
                let pointer = headerTooltipPointer
                    ?? defaultHeaderTooltipPointer(
                        for: action,
                        canvasSize: canvasSize
                    )
                let placement = islandCursorTooltipPlacement(
                    pointer: pointer,
                    tooltipSize: tooltipSize,
                    canvasSize: canvasSize,
                    displayScale: displayScale,
                    cursorGap: IslandLayout.headerTooltipCursorGap,
                    minimumTop: expandedHeaderHeight
                        + IslandLayout.headerTooltipTopGap
                )

                IslandHeaderTooltip(text: text)
                    .scaleEffect(placement.scale)
                    .position(placement.center)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func headerTooltipText(for action: IslandHeaderAction) -> String {
        switch action {
        case .islandSettings:
            return interfaceLanguage.text("灵动岛设置", "Island settings")
        case .screenshot:
            return interfaceLanguage.text("截图并复制", "Copy screenshot")
        case .codexSettings:
            return interfaceLanguage.text("Codex 设置", "Codex settings")
        case .quit:
            return interfaceLanguage.text("退出应用", "Quit app")
        }
    }

    private func defaultHeaderTooltipPointer(
        for action: IslandHeaderAction,
        canvasSize: CGSize
    ) -> CGPoint {
        let buttonsToRight: CGFloat
        switch action {
        case .screenshot: buttonsToRight = 3
        case .codexSettings: buttonsToRight = 2
        case .islandSettings: buttonsToRight = 1
        case .quit: buttonsToRight = 0
        }
        return CGPoint(
            x: canvasSize.width
                - IslandLayout.contentHorizontalInset
                - IslandLayout.headerActionButtonSize / 2
                - buttonsToRight * (
                    IslandLayout.headerActionButtonSize
                        + IslandLayout.headerActionSpacing
                ),
            y: expandedHeaderHeight / 2
        )
    }

    private func handleHeaderActionHover(
        _ action: IslandHeaderAction,
        phase: HoverPhase
    ) {
        switch phase {
        case .active(let location):
            headerTooltipPointer = location
            guard hoveredHeaderAction != action else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                hoveredHeaderAction = action
            }
        case .ended:
            guard hoveredHeaderAction == action else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                hoveredHeaderAction = nil
            }
            headerTooltipPointer = nil
        }
    }

    @ViewBuilder
    private func popoverView(for content: IslandPopoverContent) -> some View {
        switch content {
        case .token(_, _, let usage):
            TokenUsageDetailPopover(usage: usage)
        case .context(_, _, let usage):
            ContextWindowPopover(usage: usage)
        case .reset(let summary):
            ResetExpirationPopover(summary: summary)
        case .chartLegend(let kind):
            TokenChartLegendPopover(kind: kind)
        }
    }

    private func defaultPopoverPointer(
        for content: IslandPopoverContent,
        canvasSize: CGSize
    ) -> CGPoint {
        switch content {
        case .token(_, let rank, _):
            return islandDefaultTokenPopoverPointer(
                rank: rank,
                canvasSize: canvasSize
            )
        case .context(_, let rank, _):
            return islandDefaultContextPopoverPointer(
                rank: rank,
                canvasSize: canvasSize
            )
        case .reset:
            return islandDefaultResetPopoverPointer(
                topRegionHeight: displayGeometry.topRegionHeight,
                canvasSize: canvasSize
            )
        case .chartLegend:
            return islandDefaultChartLegendPopoverPointer(
                topRegionHeight: displayGeometry.topRegionHeight,
                canvasSize: canvasSize
            )
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        if displayGeometry.hasNotch {
            GeometryReader { proxy in
                let notchWidth = min(displayGeometry.notchWidth, proxy.size.width)
                let sideWidth = max(0, (proxy.size.width - notchWidth) / 2)

                HStack(spacing: 0) {
                    compactIdentity(showsTokenConsumption: true)
                        .padding(.leading, 7)
                        .frame(width: sideWidth, alignment: .leading)
                        .clipped()

                    Color.clear
                        .frame(width: notchWidth)

                    compactQuota
                        .padding(.trailing, 7)
                        .frame(width: sideWidth, alignment: .trailing)
                        .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            HStack(spacing: 8) {
                compactIdentity(showsTokenConsumption: false)
                Spacer(minLength: 12)
                compactQuota
            }
            .padding(.horizontal, 12)
        }
    }

    private func compactIdentity(showsTokenConsumption: Bool) -> some View {
        HStack(spacing: 0) {
            PulsingStatusDot(
                color: sessionActivityColor,
                size: 6,
                isPulsing: viewModel.snapshot.hasRunningSession,
                shadowRadius: 3
            )

            Color.clear
                .frame(width: 5)

            Text(compactIslandTodayTokenText)
                .font(.system(size: IslandTypography.body, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .offset(y: 0.5)

            if showsTokenConsumption {
                Spacer(minLength: 0)

                CompactTokenBlackHole(
                    trigger: viewModel.tokenConsumptionGeneration,
                    tokenCount: viewModel.snapshot.todayThreadTokens,
                    hasRunningSession: viewModel.snapshot.hasRunningSession,
                    previewPhase: initialTokenConsumptionPhase
                )
                .frame(
                    width: IslandLayout.compactTokenEffectWidth,
                    height: 8
                )
                .offset(y: 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(compactActivityAccessibilityLabel)
    }

    private var compactQuota: some View {
        HStack(spacing: 4) {
            CompactQuotaRing(
                fraction: compactQuotaFraction,
                color: compactQuotaColor
            )

            Text(compactQuotaText)
                .font(.system(size: IslandTypography.body, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .offset(y: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            interfaceLanguage.text(
                "主额度剩余 \(compactQuotaText)",
                "Primary limit remaining \(compactQuotaText)"
            )
        )
    }

    @ViewBuilder
    private var expandedContent: some View {
        if usesTimelineUpdates {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                expandedContentBody
            }
        } else {
            expandedContentBody
        }
    }

    private var expandedContentBody: some View {
        VStack(spacing: 0) {
            expandedHeader
                .frame(height: expandedHeaderHeight)
                .zIndex(3)

            Hairline()
                .padding(.horizontal, IslandLayout.contentHorizontalInset)

            if isIslandSettingsPresented {
                IslandSettingsPanel(
                    statusAnimationsEnabled: $statusAnimationsEnabled,
                    tokenConsumptionEffectEnabled: $tokenConsumptionEffectEnabled,
                    completionSoundEnabled: $completionSoundEnabled,
                    launchAtLoginState: launchAtLoginSetting.state,
                    launchAtLoginEnabled: launchAtLoginBinding,
                    languagePreference: languagePreferenceBinding,
                    displaySelection: displaySelection,
                    previewDisplayPickerPresentation: previewDisplayPickerPresentation,
                    colorTheme: colorThemeBinding,
                    isRefreshing: viewModel.isRefreshing,
                    onRefresh: viewModel.refresh
                )
                .frame(maxHeight: .infinity)
                .onAppear(perform: refreshLaunchAtLoginSetting)
                .transition(
                    .move(edge: .trailing)
                        .combined(with: .opacity)
                )
            } else {
                dashboardContent
                    .frame(maxHeight: .infinity)
                    .transition(
                        .move(edge: .leading)
                        .combined(with: .opacity)
                    )
            }
        }
        .padding(.bottom, IslandLayout.expandedBottomPadding)
        .animation(
            usesTimelineUpdates ? .easeOut(duration: 0.18) : nil,
            value: isIslandSettingsPresented
        )
    }

    private var dashboardContent: some View {
        ZStack(alignment: .bottomTrailing) {
            if selectedColorTheme.watermarkResourceName != nil {
                IslandThemeWatermark(theme: selectedColorTheme)
                    .frame(
                        width: selectedColorTheme.watermarkSize.width,
                        height: selectedColorTheme.watermarkSize.height
                    )
                    .opacity(selectedColorTheme.watermarkOpacity)
                    .padding(.trailing, 2)
                    .offset(y: selectedColorTheme == .tsinghua ? 24 : 8)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                metrics
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        CodexLauncher.openCodex()
                    }

                Hairline()
                    .padding(.horizontal, IslandLayout.contentHorizontalInset)

                recentConversations
                    .frame(
                        height: IslandLayout.recentConversationsHeight,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, IslandLayout.contentHorizontalInset)
            }
        }
    }

    private var expandedHeader: some View {
        ZStack(alignment: .trailing) {
            topHeader
                .contentShape(Rectangle())
                .onTapGesture {
                    CodexLauncher.openCodex()
                }

            HStack(spacing: IslandLayout.headerActionSpacing) {
                screenshotButton
                codexSettingsButton
                islandSettingsButton
                quitButton
            }
            .padding(.trailing, IslandLayout.contentHorizontalInset)
        }
    }

    private var expandedHeaderHeight: CGFloat {
        IslandLayout.expandedHeaderHeight(
            forTopRegionHeight: displayGeometry.topRegionHeight
        )
    }

    private var selectedLanguagePreference: IslandLanguagePreference {
        previewLanguagePreference
            ?? IslandLanguagePreference.stored(storedLanguagePreference)
    }

    private var interfaceLanguage: IslandInterfaceLanguage {
        IslandLanguageResolver.resolve(preference: selectedLanguagePreference)
    }

    private var selectedColorTheme: IslandColorTheme {
        previewColorTheme ?? IslandColorTheme.stored(storedColorTheme)
    }

    private var languagePreferenceBinding: Binding<IslandLanguagePreference> {
        Binding(
            get: { selectedLanguagePreference },
            set: { storedLanguagePreference = $0.rawValue }
        )
    }

    private var colorThemeBinding: Binding<IslandColorTheme> {
        Binding(
            get: { selectedColorTheme },
            set: { storedColorTheme = $0.rawValue }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginSetting.state.isEnabled },
            set: { shouldEnable in
                var updated = launchAtLoginSetting
                updated.setEnabled(shouldEnable)
                launchAtLoginSetting = updated
            }
        )
    }

    private func refreshLaunchAtLoginSetting() {
        var updated = launchAtLoginSetting
        updated.refresh()
        launchAtLoginSetting = updated
    }

    private var isIslandSettingsButtonHovered: Bool {
        hoveredHeaderAction == .islandSettings
    }

    private var isScreenshotButtonHovered: Bool {
        hoveredHeaderAction == .screenshot
    }

    private var isCodexSettingsButtonHovered: Bool {
        hoveredHeaderAction == .codexSettings
    }

    private var isQuitButtonHovered: Bool {
        hoveredHeaderAction == .quit
    }

    private var islandSettingsButton: some View {
        Button {
            activePopover = nil
            withAnimation(.easeOut(duration: 0.18)) {
                isIslandSettingsPresented.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        isIslandSettingsPresented
                            ? selectedColorTheme.accent.opacity(0.12)
                            : Color.white.opacity(
                                isIslandSettingsButtonHovered ? 0.075 : 0
                            )
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: IslandTypography.body, weight: .semibold))
                    .foregroundStyle(
                        isIslandSettingsPresented
                            ? selectedColorTheme.accent.opacity(0.88)
                            : Color.white.opacity(
                                isIslandSettingsButtonHovered ? 0.72 : 0.38
                            )
                    )
            }
            .frame(
                width: IslandLayout.headerActionButtonSize,
                height: IslandLayout.headerActionButtonSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover(
            coordinateSpace: .named(IslandCoordinateSpace.name)
        ) { phase in
            handleHeaderActionHover(.islandSettings, phase: phase)
        }
        .accessibilityLabel(
            interfaceLanguage.text("打开灵动岛设置", "Open Island settings")
        )
        .accessibilityAddTraits(
            isIslandSettingsPresented ? .isSelected : []
        )
    }

    private var screenshotButton: some View {
        Button {
            activePopover = nil
            hoveredHeaderAction = nil
            headerTooltipPointer = nil
            Task { @MainActor in
                await Task.yield()
                guard onCopyScreenshot() else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    screenshotCopied = true
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeOut(duration: 0.12)) {
                    screenshotCopied = false
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        screenshotCopied
                            ? Color.green.opacity(0.13)
                            : Color.white.opacity(
                                isScreenshotButtonHovered ? 0.075 : 0
                            )
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: screenshotCopied ? "checkmark" : "camera")
                    .font(.system(size: IslandTypography.body, weight: .semibold))
                    .foregroundStyle(
                        screenshotCopied
                            ? Color.green.opacity(0.88)
                            : Color.white.opacity(
                                isScreenshotButtonHovered ? 0.72 : 0.38
                            )
                    )
            }
            .frame(
                width: IslandLayout.headerActionButtonSize,
                height: IslandLayout.headerActionButtonSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover(
            coordinateSpace: .named(IslandCoordinateSpace.name)
        ) { phase in
            handleHeaderActionHover(.screenshot, phase: phase)
        }
        .accessibilityLabel(
            screenshotCopied
                ? interfaceLanguage.text("截图已复制", "Screenshot copied")
                : interfaceLanguage.text(
                    "将灵动岛截图复制到剪切板",
                    "Copy Island screenshot to clipboard"
                )
        )
    }

    private var codexSettingsButton: some View {
        Button {
            CodexLauncher.openSettings()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        Color.white.opacity(
                            isCodexSettingsButtonHovered ? 0.075 : 0
                        )
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: "gearshape")
                    .font(.system(size: IslandTypography.body, weight: .semibold))
                    .foregroundStyle(
                        Color.white.opacity(
                            isCodexSettingsButtonHovered ? 0.72 : 0.38
                        )
                    )
            }
            .frame(
                width: IslandLayout.headerActionButtonSize,
                height: IslandLayout.headerActionButtonSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover(
            coordinateSpace: .named(IslandCoordinateSpace.name)
        ) { phase in
            handleHeaderActionHover(.codexSettings, phase: phase)
        }
        .accessibilityLabel(
            interfaceLanguage.text("打开 Codex 设置", "Open Codex settings")
        )
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        isQuitButtonHovered
                            ? Color.red.opacity(0.10)
                            : Color.clear
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: "power")
                    .font(.system(size: IslandTypography.body, weight: .semibold))
                    .foregroundStyle(
                        isQuitButtonHovered
                            ? Color.red.opacity(0.76)
                            : Color.white.opacity(0.38)
                    )
            }
            .frame(
                width: IslandLayout.headerActionButtonSize,
                height: IslandLayout.headerActionButtonSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover(
            coordinateSpace: .named(IslandCoordinateSpace.name)
        ) { phase in
            handleHeaderActionHover(.quit, phase: phase)
        }
        .accessibilityLabel(
            interfaceLanguage.text("退出 Codex Island", "Quit Codex Island")
        )
    }

    @ViewBuilder
    private var topHeader: some View {
        if displayGeometry.hasNotch {
            notchHeader
        } else {
            HStack(spacing: 8) {
                headerIdentity(showsLifetimeToken: true)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, IslandLayout.contentHorizontalInset)
        }
    }

    private var notchHeader: some View {
        GeometryReader { proxy in
            let notchWidth = min(displayGeometry.notchWidth, proxy.size.width)
            let sideWidth = max(0, (proxy.size.width - notchWidth) / 2)

            HStack(spacing: 0) {
                headerIdentity(showsLifetimeToken: sideWidth >= 150)
                    .padding(.leading, IslandLayout.contentHorizontalInset)
                    .frame(width: sideWidth, alignment: .leading)
                    .clipped()

                Color.clear
                    .frame(width: notchWidth)

                Color.clear
                    .frame(width: sideWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func headerIdentity(showsLifetimeToken: Bool) -> some View {
        HStack(spacing: 4) {
            PulsingStatusDot(
                color: sessionActivityColor,
                size: 7,
                isPulsing: viewModel.snapshot.hasRunningSession,
                shadowRadius: 4
            )

            headerTokenMetric(
                value: compactTodayTokenText,
                label: interfaceLanguage.text("今日", "DAY")
            )

            if showsLifetimeToken {
                PixelVerticalDivider(height: 16, opacity: 0.12)
                headerTokenMetric(
                    value: headerLifetimeTokenText,
                    label: interfaceLanguage.text("累计", "ALL")
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(expandedHeaderAccessibilityLabel)
    }

    private func headerTokenMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: IslandTypography.emphasized, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(selectedColorTheme.accent.opacity(0.88))
                .lineLimit(1)

            Text(label)
                .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                .tracking(-0.35)
                .foregroundStyle(.white.opacity(0.25))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var metrics: some View {
        AccountActivityCard(
            identity: viewModel.snapshot.profileIdentity,
            usage: viewModel.snapshot.usage,
            todayTokens: viewModel.snapshot.todayThreadTokens,
            hourlyUsage: viewModel.snapshot.hourlyThreadTokens,
            dailyUsage: viewModel.snapshot.dailyThreadTokens,
            billedTodayTokens: viewModel.snapshot.billedTodayThreadTokens,
            billedHourlyUsage: viewModel.snapshot.billedHourlyThreadTokens,
            billedDailyUsage: viewModel.snapshot.billedDailyThreadTokens,
            chartCreditTotals: viewModel.snapshot.chartCreditTotals,
            window: viewModel.snapshot.rateLimit?.primary,
            remainingTokenEstimate: viewModel.snapshot.remainingTokenEstimate,
            resetSummary: viewModel.snapshot.resetCredits,
            onResetHoverChange: { hovering, pointer in
                updateResetHover(hovering: hovering, pointer: pointer)
            },
            onLegendHoverChange: { kind, hovering, pointer in
                updateChartLegendHover(
                    kind: kind,
                    hovering: hovering,
                    pointer: pointer
                )
            },
            chartRange: $tokenChartRange,
            planLabel: CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: viewModel.snapshot.account.planType,
                rateLimitPlanType: viewModel.snapshot.rateLimit?.planType
            )
        )
    }

    @ViewBuilder
    private var recentConversations: some View {
        let threads = CodexDisplayPolicy.visibleRecentThreads(
            from: viewModel.snapshot.recentThreads
        )
        let activityBucketCount = tokenChartRange == .hours48
            ? viewModel.snapshot.hourlyThreadTokens.count
            : CodexUsageTimeline.lastDaysIncludingToday(
                from: viewModel.snapshot.usage.dailyUsageBuckets,
                localDailyBuckets: viewModel.snapshot.dailyThreadTokens
            ).count
        let reasoningColumnWidth = ThreadConfigurationView.reasoningColumnWidth(
            for: threads
        )
        if threads.isEmpty {
            GeometryReader { proxy in
                let indicatorOffset = activityIndicatorOffset(
                    rowWidth: proxy.size.width,
                    bucketCount: activityBucketCount
                )
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: IslandTypography.body, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(width: IslandLayout.activityIndicatorSlotWidth)
                        .offset(x: indicatorOffset)
                    Text(
                        interfaceLanguage.text(
                            "尚未读取到本地会话",
                            "No local sessions found"
                        )
                    )
                        .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                    Spacer()
                }
            }
            .frame(height: IslandLayout.conversationRowHeight, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    ConversationRow(
                        thread: thread,
                        rank: index,
                        activityBucketCount: activityBucketCount,
                        reasoningColumnWidth: reasoningColumnWidth,
                        onContextHover: { hovering, pointer in
                            updateContextHover(
                                thread: thread,
                                rank: index,
                                hovering: hovering,
                                pointer: pointer
                            )
                        },
                        onTokenHover: { hovering, pointer in
                            updateTokenHover(
                                thread: thread,
                                rank: index,
                                hovering: hovering,
                                pointer: pointer
                            )
                        },
                        onOpen: {
                            CodexLauncher.openThread(threadID: thread.id)
                        }
                    )
                        .frame(height: IslandLayout.conversationRowHeight)
                }
            }
        }
    }

    private var sessionActivityColor: Color {
        viewModel.snapshot.hasRunningSession
            ? .green
            : .white.opacity(0.28)
    }

    private var compactTodayTokenText: String {
        guard let tokens = viewModel.snapshot.todayThreadTokens else { return "--" }
        return CodexDisplayPolicy.headerTokenCount(tokens)
    }

    private var compactIslandTodayTokenText: String {
        guard let tokens = viewModel.snapshot.todayThreadTokens else { return "--" }
        return menuBarTokenCount(tokens)
    }

    private var headerLifetimeTokenText: String {
        viewModel.snapshot.usage.lifetimeTokens.map(
            CodexDisplayPolicy.headerTokenCount
        ) ?? "--"
    }

    private var expandedHeaderAccessibilityLabel: String {
        let lifetime: String
        if let tokens = viewModel.snapshot.usage.lifetimeTokens {
            lifetime = interfaceLanguage.text(
                "累计词元 \(exactTokenCount(tokens))",
                "Total tokens \(exactTokenCount(tokens))"
            )
        } else {
            lifetime = interfaceLanguage.text(
                "累计词元尚未同步",
                "Total tokens not yet synced"
            )
        }
        return "\(compactActivityAccessibilityLabel), \(lifetime)"
    }

    private var compactActivityAccessibilityLabel: String {
        let state = viewModel.snapshot.hasRunningSession
            ? interfaceLanguage.text(
                "有会话正在运行",
                "A session is running"
            )
            : interfaceLanguage.text(
                "当前没有运行中的会话",
                "No sessions are currently running"
            )
        guard let tokens = viewModel.snapshot.todayThreadTokens else {
            return interfaceLanguage.text(
                "\(state)，今日会话词元用量暂不可用",
                "\(state). Today's session token usage is unavailable"
            )
        }
        let exactTokens = NumberFormatter.localizedString(
            from: NSNumber(value: tokens),
            number: .decimal
        )
        return interfaceLanguage.text(
            "\(state)，今日会话词元用量 \(exactTokens)",
            "\(state). Today's session token usage is \(exactTokens)"
        )
    }

    private var compactQuotaWindow: RateLimitWindow? {
        viewModel.snapshot.rateLimit?.primary
    }

    private var compactQuotaText: String {
        guard let remaining = compactQuotaWindow?.remainingPercent else { return "--" }
        return "\(Int(remaining.rounded()))%"
    }

    private var compactQuotaFraction: CGFloat {
        CGFloat((compactQuotaWindow?.remainingPercent ?? 0) / 100)
    }

    private var compactQuotaColor: Color {
        quotaRemainingColor(
            compactQuotaWindow?.remainingPercent,
            unavailableColor: .white.opacity(0.28)
        )
    }

    private func updateTokenHover(
        thread: ThreadSummary,
        rank: Int,
        hovering: Bool,
        pointer: CGPoint?
    ) {
        if hovering, let usage = thread.tokenUsage, let pointer {
            showPopover(
                IslandPopoverPresentation(
                    content: .token(threadID: thread.id, rank: rank, usage: usage),
                    pointer: pointer
                )
            )
        } else if case .token(let threadID, _, _) = activePopover?.content,
                  threadID == thread.id {
            hidePopover()
        }
    }

    private func updateContextHover(
        thread: ThreadSummary,
        rank: Int,
        hovering: Bool,
        pointer: CGPoint?
    ) {
        if hovering, let pointer {
            showPopover(
                IslandPopoverPresentation(
                    content: .context(
                        threadID: thread.id,
                        rank: rank,
                        usage: thread.tokenUsage
                    ),
                    pointer: pointer
                )
            )
        } else if case .context(let threadID, _, _) = activePopover?.content,
                  threadID == thread.id {
            hidePopover()
        }
    }

    private func updateResetHover(hovering: Bool, pointer: CGPoint?) {
        if hovering,
           let summary = viewModel.snapshot.resetCredits,
           summary.availableCount > 0,
           let pointer {
            showPopover(
                IslandPopoverPresentation(
                    content: .reset(summary),
                    pointer: pointer
                )
            )
        } else if case .reset = activePopover?.content {
            hidePopover()
        }
    }

    private func updateChartLegendHover(
        kind: TokenChartLegendKind,
        hovering: Bool,
        pointer: CGPoint?
    ) {
        if hovering {
            showPopover(
                IslandPopoverPresentation(
                    content: .chartLegend(kind),
                    pointer: pointer
                )
            )
        } else if case .chartLegend(let activeKind) = activePopover?.content,
                  activeKind == kind {
            hidePopover()
        }
    }

    private func showPopover(_ presentation: IslandPopoverPresentation) {
        if activePopover == nil {
            withAnimation(.easeOut(duration: 0.12)) {
                activePopover = presentation
            }
        } else {
            activePopover = presentation
        }
    }

    private func hidePopover() {
        withAnimation(.easeOut(duration: 0.08)) {
            activePopover = nil
        }
    }

}

private struct IslandHeaderTooltip: View {
    private static let fontSize: CGFloat = IslandTypography.body
    private static let horizontalPadding: CGFloat = 8
    private static let height: CGFloat = 22

    let text: String

    @Environment(\.displayScale) private var displayScale

    static func size(for text: String, displayScale: CGFloat) -> CGSize {
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded)
            ?? baseFont.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: fontSize) ?? baseFont
        let measuredWidth = (text as NSString).size(
            withAttributes: [.font: font]
        ).width + horizontalPadding * 2
        let scale = max(1, displayScale)
        return CGSize(
            width: (measuredWidth * scale).rounded(.up) / scale,
            height: height
        )
    }

    var body: some View {
        let tooltipSize = Self.size(for: text, displayScale: displayScale)

        Text(text)
            .font(.system(size: Self.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(1)
            .frame(width: tooltipSize.width, height: tooltipSize.height)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color(red: 0.035, green: 0.039, blue: 0.050))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.13),
                        lineWidth: 1 / max(1, displayScale)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

private struct IslandSettingsPanel: View {
    @Binding var statusAnimationsEnabled: Bool
    @Binding var tokenConsumptionEffectEnabled: Bool
    @Binding var completionSoundEnabled: Bool
    let launchAtLoginState: LaunchAtLoginPresentationState
    @Binding var launchAtLoginEnabled: Bool
    @Binding var languagePreference: IslandLanguagePreference
    @ObservedObject var displaySelection: IslandDisplaySelectionModel
    let previewDisplayPickerPresentation: Bool?
    @Binding var colorTheme: IslandColorTheme
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme
    @State private var isRefreshHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(language.text("灵动岛设置", "Island settings"))
                    .font(.system(size: IslandTypography.emphasized, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 8)

                Text(
                    language.text(
                        "偏好设置会自动保存",
                        "Preferences are saved automatically"
                    )
                )
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.26))
            }
            .frame(height: 18)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 0)
                ],
                spacing: 8
            ) {
                IslandSettingToggleCard(
                    icon: "dot.radiowaves.left.and.right",
                    title: language.text("状态动效", "Status animation"),
                    detail: language.text(
                        "运行会话的呼吸提示",
                        "Pulse while running"
                    ),
                    tint: .green,
                    isOn: $statusAnimationsEnabled
                )

                IslandSettingToggleCard(
                    icon: "sparkles",
                    title: language.text("词元动效", "Token effects"),
                    detail: language.text(
                        "消耗时播放刘海粒子",
                        "Particles on token use"
                    ),
                    tint: theme.accent,
                    isOn: $tokenConsumptionEffectEnabled
                )

                IslandSettingToggleCard(
                    icon: "speaker.wave.2.fill",
                    title: language.text("完成音效", "Completion sound"),
                    detail: language.text(
                        "完成或等待输入时播放",
                        "Plays on finish or input request"
                    ),
                    tint: .orange,
                    isOn: $completionSoundEnabled
                )

                IslandSettingToggleCard(
                    icon: "power",
                    title: language.text("开机启动", "Launch at login"),
                    detail: launchAtLoginDetailText,
                    tint: .purple,
                    isOn: $launchAtLoginEnabled
                )
            }

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.accent.opacity(0.09))

                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: IslandTypography.body, weight: .semibold))
                        .foregroundStyle(theme.accent.opacity(0.78))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("颜色风格", "Color theme"))
                        .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(
                        language.text(
                            "当前：\(colorTheme.label(language: language)) · 黑底刘海适配",
                            "\(colorTheme.label(language: language)) · black and notch safe"
                        )
                    )
                        .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                IslandThemePicker(selection: $colorTheme)
            }
            .padding(.horizontal, 9)
            .frame(height: 52)
            .background(settingsCardBackground)
            .overlay(settingsCardBorder)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.accent.opacity(0.08))

                    Image(systemName: "globe")
                        .font(.system(size: IslandTypography.body, weight: .semibold))
                        .foregroundStyle(theme.accent.opacity(0.72))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("语言", "Language"))
                        .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(languageDetailText)
                        .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                IslandLanguagePicker(selection: $languagePreference)
                    .layoutPriority(2)

                IslandDisplayPicker(
                    selection: displaySelection,
                    previewPresentation: previewDisplayPickerPresentation
                )
                .layoutPriority(1)

                Button(action: onRefresh) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: IslandTypography.body, weight: .semibold))

                        Text(
                            isRefreshing
                                ? language.text("同步中", "Syncing")
                                : language.text("同步", "Sync")
                        )
                            .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(
                        theme.accent.opacity(isRefreshing ? 0.40 : 0.82)
                    )
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    theme.accent.opacity(
                                        isRefreshHovered && !isRefreshing ? 0.13 : 0.075
                                    )
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    theme.accent.opacity(0.12),
                                    lineWidth: 1 / max(1, displayScale)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.08)) {
                        isRefreshHovered = hovering
                    }
                }
                .help(
                    language.text(
                        "立即同步 Codex 数据",
                        "Sync Codex data now"
                    )
                )
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(settingsCardBackground)
            .overlay(settingsCardBorder)
        }
        .padding(.horizontal, IslandLayout.contentHorizontalInset)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var languageDetailText: String {
        if languagePreference == .automatic {
            return language.text(
                "跟随 macOS",
                "Follows macOS"
            )
        }
        return language.text("手动选择", "Manual")
    }

    private var launchAtLoginDetailText: String {
        switch launchAtLoginState {
        case .disabled:
            return language.text("当前关闭", "Currently off")
        case .enabled:
            return language.text("登录后自动运行", "Starts after login")
        case .updateFailed:
            return language.text("更新失败，请重试", "Update failed · Retry")
        }
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.028))
    }

    private var settingsCardBorder: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
                Color.white.opacity(0.065),
                lineWidth: 1 / max(1, displayScale)
            )
    }
}

private struct IslandDisplayPicker: View {
    private static let width: CGFloat = 116
    @ObservedObject var selection: IslandDisplaySelectionModel

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isHovered = false
    @State private var isPresented = false
    private let previewPresentation: Bool?

    init(
        selection: IslandDisplaySelectionModel,
        previewPresentation: Bool? = nil
    ) {
        self.selection = selection
        self.previewPresentation = previewPresentation
    }

    var body: some View {
        ZStack {
            Button {
                guard previewPresentation == nil else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isPresented.toggle()
                }
            } label: {
                pickerLabel
            }
            .buttonStyle(.plain)
            .help(
                language.text(
                    "选择灵动岛显示位置",
                    "Choose which display hosts Codex Island"
                )
            )
            .accessibilityLabel(
                language.text(
                    "灵动岛显示位置：\(selectedLabel)",
                    "Codex Island display: \(selectedLabel)"
                )
            )
        }
        .frame(width: Self.width, height: 28)
        .overlay(alignment: .bottomTrailing) {
            if isMenuPresented {
                displayMenu
                    .offset(y: -24)
                    .transition(
                        previewPresentation == nil
                            ? .opacity.combined(
                                with: .scale(
                                    scale: 0.96,
                                    anchor: .bottomTrailing
                                )
                            )
                            : .identity
                    )
                    .zIndex(1)
            }
        }
        .zIndex(isMenuPresented ? 20 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "display")
                .font(.system(size: 10.5, weight: .semibold))

            Text(selectedLabel)
                .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 1)

            Image(systemName: isMenuPresented ? "chevron.up" : "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.58)
        }
        .foregroundStyle(
            Color.cyan.opacity(isHovered || isMenuPresented ? 0.90 : 0.72)
        )
        .padding(.horizontal, 7)
        .frame(width: Self.width, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    Color.cyan.opacity(
                        isHovered || isMenuPresented ? 0.12 : 0.07
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    Color.cyan.opacity(
                        isHovered || isMenuPresented ? 0.18 : 0.10
                    ),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
    }

    private var displayMenu: some View {
        VStack(spacing: 1) {
            ForEach(selection.choices) { choice in
                Button {
                    guard choice.isAvailable else { return }
                    selection.preference = choice.target
                    if previewPresentation == nil {
                        withAnimation(.easeOut(duration: 0.10)) {
                            isPresented = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(
                            systemName: choice.target == selection.preference
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                choice.target == selection.preference
                                    ? Color.cyan.opacity(0.86)
                                    : Color.white.opacity(0.18)
                            )
                            .frame(width: 8)

                        Text(optionLabel(for: choice))
                            .font(
                                .system(
                                    size: IslandTypography.body,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                choice.isAvailable
                                    ? Color.white.opacity(0.72)
                                    : Color.white.opacity(0.28)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 142, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!choice.isAvailable)
                .accessibilityLabel(optionLabel(for: choice))
                .accessibilityAddTraits(
                    choice.target == selection.preference ? .isSelected : []
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.025, green: 0.028, blue: 0.036))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.11),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .shadow(color: .black.opacity(0.62), radius: 5, y: 2)
    }

    private var selectedLabel: String {
        guard let selected = selection.choices.first(where: {
            $0.target == selection.preference
        }) else {
            return language.text("自动选屏", "Auto")
        }
        if selected.target == .automatic {
            return language.text("自动选屏", "Auto")
        }
        return optionLabel(for: selected)
    }

    private var isMenuPresented: Bool {
        previewPresentation ?? isPresented
    }

    private func optionLabel(for choice: IslandDisplayChoice) -> String {
        switch choice.target {
        case .automatic:
            return language.text("自动", "Automatic")
        case .builtIn:
            return choice.isAvailable
                ? language.text("内建显示器", "Built-in display")
                : language.text(
                    "内建显示器（未连接）",
                    "Built-in display (disconnected)"
                )
        case .external:
            guard let display = choice.display else {
                return language.text("外接屏未连接", "Display disconnected")
            }
            if let duplicateIndex = choice.duplicateIndex {
                return "\(display.name) · \(duplicateIndex)"
            }
            return display.name
        }
    }
}

private struct IslandSettingToggleCard: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let isInteractive: Bool
    @Binding var isOn: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var isHovered = false

    init(
        icon: String,
        title: String,
        detail: String,
        tint: Color,
        isInteractive: Bool = true,
        isOn: Binding<Bool>
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.tint = tint
        self.isInteractive = isInteractive
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(isOn ? 0.12 : 0.055))

                Image(systemName: icon)
                    .font(.system(size: IslandTypography.body, weight: .semibold))
                    .foregroundStyle(tint.opacity(isOn ? 0.82 : 0.38))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.27))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Toggle(isOn: $isOn) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(IslandToggleStyle(tint: tint))
            .frame(width: 30, height: 17)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel(Text(title))
        }
        .disabled(!isInteractive)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.045 : 0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isHovered ? 0.10 : 0.065),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering && isInteractive
            }
        }
    }
}

private struct IslandThemePicker: View {
    @Binding var selection: IslandColorTheme

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IslandColorTheme.allCases) { theme in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        selection = theme
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [theme.accent, theme.secondaryAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 14, height: 14)
                            .shadow(
                                color: theme.accent.opacity(
                                    selection == theme ? 0.42 : 0
                                ),
                                radius: 3
                            )

                        if selection == theme {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.black.opacity(0.76))
                        }
                    }
                    .frame(width: 25, height: 25)
                    .background(
                        Circle()
                            .fill(
                                selection == theme
                                    ? theme.accent.opacity(0.13)
                                    : Color.white.opacity(0.025)
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                selection == theme
                                    ? theme.accent.opacity(0.42)
                                    : Color.white.opacity(0.065),
                                lineWidth: 1 / max(1, displayScale)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(theme.label(language: language))
                .accessibilityLabel(
                    language.text(
                        "选择\(theme.label(language: language))配色",
                        "Select \(theme.label(language: language)) theme"
                    )
                )
                .accessibilityAddTraits(
                    selection == theme ? .isSelected : []
                )
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.065),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
    }
}

private struct IslandLanguagePicker: View {
    private static let width: CGFloat = 120
    @Binding var selection: IslandLanguagePreference

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        HStack(spacing: 1) {
            ForEach(IslandLanguagePreference.allCases) { preference in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        selection = preference
                    }
                } label: {
                    Text(optionLabel(for: preference))
                        .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            preference == selection
                                ? theme.accent.opacity(0.90)
                                : Color.white.opacity(0.34)
                        )
                        .lineLimit(1)
                        .frame(
                            width: optionWidth(for: preference),
                            height: 24
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    preference == selection
                                        ? theme.accent.opacity(0.11)
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: preference))
                .accessibilityAddTraits(
                    preference == selection ? .isSelected : []
                )
            }
        }
        .padding(2)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.065),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
    }

    private func optionWidth(
        for preference: IslandLanguagePreference
    ) -> CGFloat {
        switch preference {
        case .automatic, .chinese: return 34
        case .english: return 46
        }
    }

    private func optionLabel(
        for preference: IslandLanguagePreference
    ) -> String {
        switch preference {
        case .automatic: return language.text("自动", "Auto")
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    private func accessibilityLabel(
        for preference: IslandLanguagePreference
    ) -> String {
        switch preference {
        case .automatic:
            return language.text(
                "自动跟随 macOS 语言",
                "Follow the macOS language automatically"
            )
        case .chinese:
            return language.text("使用中文", "Use Chinese")
        case .english:
            return language.text("使用英文", "Use English")
        }
    }
}

private struct IslandToggleStyle: ToggleStyle {
    let tint: Color

    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    configuration.isOn
                        ? tint.opacity(0.68)
                        : Color.white.opacity(0.12)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(
                                configuration.isOn ? 0.08 : 0.07
                            ),
                            lineWidth: 1 / max(1, displayScale)
                        )
                )

            Circle()
                .fill(
                    configuration.isOn
                        ? Color.white.opacity(0.92)
                        : Color.white.opacity(0.42)
                )
                .frame(width: 13, height: 13)
                .offset(x: configuration.isOn ? 6.5 : -6.5)
                .shadow(color: .black.opacity(0.24), radius: 1, y: 0.5)
        }
        .frame(width: 30, height: 17)
        .opacity(isEnabled ? 1 : 0.48)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                configuration.isOn.toggle()
            }
        }
    }
}

private struct ConversationRow: View {
    let thread: ThreadSummary
    let rank: Int
    let activityBucketCount: Int
    let reasoningColumnWidth: CGFloat
    let onContextHover: (Bool, CGPoint?) -> Void
    let onTokenHover: (Bool, CGPoint?) -> Void
    let onOpen: () -> Void
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            let indicatorOffset = activityIndicatorOffset(
                rowWidth: proxy.size.width,
                bucketCount: activityBucketCount
            )
            let configurationDensity = ThreadConfigurationDensity(
                availableRowWidth: proxy.size.width
            )

            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ThreadActivityIndicator(state: thread.executionState)
                        .frame(width: IslandLayout.activityIndicatorSlotWidth)
                        .offset(x: indicatorOffset)

                    Text(thread.title)
                        .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                .padding(.trailing, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )

                ThreadSourceLabel(source: thread.clientSource)
                    .frame(
                        width: IslandLayout.threadSourceColumnWidth,
                        height: proxy.size.height,
                        alignment: .center
                    )

                HStack(spacing: 4) {
                    ThreadConfigurationView(
                        thread: thread,
                        density: configurationDensity,
                        reasoningWidth: reasoningColumnWidth,
                        onContextHover: onContextHover
                    )

                    ThreadTokenUsageView(
                        usage: thread.tokenUsage,
                        onHoverChange: onTokenHover
                    )

                    Spacer(minLength: 0)

                    Text(trailingLabel)
                        .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(trailingColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(
                            width: trailingColumnWidth,
                            alignment: .trailing
                        )
                        .help(executionStateHelp)
                }
                .padding(.leading, IslandLayout.metricCenterGutter)
                .frame(
                    height: proxy.size.height,
                    alignment: .trailing
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.035 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
        .onTapGesture(perform: onOpen)
        .accessibilityLabel(conversationAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var conversationAccessibilityLabel: String {
        let source = thread.clientSource.map {
            language.text("，来源 \($0.displayLabel)", ", source \($0.displayLabel)")
        } ?? ""
        return language.text(
            "在 Codex 中打开会话：\(thread.title)\(source)",
            "Open session in Codex: \(thread.title)\(source)"
        )
    }

    private var titleColor: Color {
        switch thread.executionState {
        case .running: return .white.opacity(0.76)
        case .waitingForInput: return .yellow.opacity(0.72)
        case .interrupted: return .orange.opacity(0.62)
        case .failed: return .red.opacity(0.66)
        case .idle, .unknown: return .white.opacity(rank == 0 ? 0.60 : 0.48)
        }
    }

    private var trailingLabel: String {
        switch thread.executionState {
        case .running: return language.text("执行中", "Running")
        case .waitingForInput: return language.text("等待输入", "Input needed")
        case .interrupted: return language.text("已中断", "Interrupted")
        case .failed: return language.text("失败", "Failed")
        case .idle, .unknown:
            return conversationUpdatedLabel(thread.updatedAt, language: language)
        }
    }

    private var trailingColumnWidth: CGFloat {
        switch language {
        case .chinese:
            return IslandLayout.compactThreadTrailingColumnWidth
        case .english:
            return IslandLayout.threadTrailingColumnWidth
        }
    }

    private var trailingColor: Color {
        switch thread.executionState {
        case .running: return .green.opacity(0.72)
        case .waitingForInput: return .yellow.opacity(0.72)
        case .interrupted: return .orange.opacity(0.58)
        case .failed: return .red.opacity(0.62)
        case .idle, .unknown: return .white.opacity(rank == 0 ? 0.25 : 0.18)
        }
    }

    private var executionStateHelp: String {
        switch thread.executionState {
        case .running:
            return language.text(
                "Codex 正在执行这条会话",
                "Codex is running this session"
            )
        case .waitingForInput:
            return language.text(
                "Codex 正在等待你的输入",
                "Codex is waiting for your input"
            )
        case .idle:
            return language.text(
                "最近一轮任务已结束",
                "The latest task has finished"
            )
        case .interrupted:
            return language.text(
                "最近一轮任务已中断",
                "The latest task was interrupted"
            )
        case .failed:
            return language.text(
                "最近一轮任务执行失败",
                "The latest task failed"
            )
        case .unknown:
            return language.text(
                "尚未读取到执行状态",
                "Execution status is unavailable"
            )
        }
    }
}

private struct ThreadSourceLabel: View {
    let source: ThreadClientSource?
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        Text(source?.displayLabel ?? "")
            .font(.system(size: IslandTypography.body, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.34))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .help(sourceHelp)
            .accessibilityHidden(true)
    }

    private var sourceHelp: String {
        switch source {
        case .tui: return language.text("来源：Codex TUI", "Source: Codex TUI")
        case .app: return language.text("来源：Codex App", "Source: Codex App")
        case nil: return ""
        }
    }
}

private struct CompactTokenBlackHole: View {
    let trigger: UInt64
    let tokenCount: Int64?
    let hasRunningSession: Bool
    let previewPhase: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokenConsumptionEffectEnabled) private var animationsEnabled
    @State private var isActive = false
    @State private var animationStartedAt = Date()
    @State private var stopTask: Task<Void, Never>?
    @State private var previousTokenCount: Int64?

    var body: some View {
        Group {
            if let previewPhase {
                TokenBlackHoleFrame(phase: previewPhase)
            } else if isActive, animationsEnabled, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    let elapsed = max(
                        0,
                        context.date.timeIntervalSince(animationStartedAt)
                    )
                    TokenBlackHoleFrame(
                        phase: (elapsed / 0.72).truncatingRemainder(
                            dividingBy: 1
                        )
                    )
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            previousTokenCount = tokenCount
        }
        .onChange(of: trigger) { _ in
            handleTrigger()
        }
        .onChange(of: tokenCount) { newValue in
            defer { previousTokenCount = newValue }
            guard previewPhase == nil else { return }
            let decreased: Bool
            if let previousTokenCount, let newValue {
                decreased = newValue < previousTokenCount
            } else {
                decreased = false
            }
            if newValue == nil || decreased {
                deactivate()
            }
        }
        .onChange(of: hasRunningSession) { isRunning in
            if isRunning, isActive {
                stopTask?.cancel()
                stopTask = nil
            } else if !isRunning, stopTask == nil {
                deactivate()
            }
        }
        .onDisappear {
            deactivate()
        }
        .accessibilityHidden(true)
    }

    private func handleTrigger() {
        guard previewPhase == nil,
              animationsEnabled,
              !reduceMotion else {
            return
        }

        if !isActive {
            animationStartedAt = Date()
            isActive = true
        }

        stopTask?.cancel()
        stopTask = nil
        guard !hasRunningSession else { return }

        // A final token update can land just after the task completes. Keep a
        // short visible acknowledgement in that case; active tasks otherwise
        // animate continuously until their running state clears.
        stopTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_600_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isActive = false
            stopTask = nil
        }
    }

    private func deactivate() {
        stopTask?.cancel()
        stopTask = nil
        isActive = false
    }
}

private struct TokenBlackHoleFrame: View {
    let phase: Double
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let accent = theme.accent
            let pixel = 1 / max(displayScale, 1)
            let center = CGPoint(
                x: snapped(size.width + 0.5, pixel: pixel),
                y: snapped(size.height / 2, pixel: pixel)
            )
            let pulse = 0.5 + 0.5 * sin(phase * .pi * 2)

            for (radius, opacity) in [
                (3.0, 0.16 + pulse * 0.10),
                (2.0, 0.10 + pulse * 0.07)
            ] {
                var lens = Path()
                lens.addEllipse(
                    in: CGRect(
                        x: snapped(center.x - radius, pixel: pixel),
                        y: snapped(center.y - radius, pixel: pixel),
                        width: snapped(radius * 2, pixel: pixel),
                        height: snapped(radius * 2, pixel: pixel)
                    )
                )
                context.stroke(
                    lens,
                    with: .color(accent.opacity(opacity)),
                    lineWidth: pixel
                )
            }

            for index in 0 ..< 3 {
                let particlePhase = (phase + Double(index) / 3)
                    .truncatingRemainder(dividingBy: 1)
                // Time-reverse the original inward trajectory: particles now
                // emerge from the notch, expand, and travel toward today's
                // consumed-token total on the left.
                let pathPhase = 1 - particlePhase
                let travel = pow(pathPhase, 1.35)
                let orbitRadius = (1 - pathPhase) * 1.65
                let orbitAngle = pathPhase * .pi * 2.2
                    + Double(index) * .pi * 0.72
                let x = snapped(
                    0.45 + CGFloat(travel) * (size.width - 0.85),
                    pixel: pixel
                )
                let y = snapped(
                    size.height / 2
                        + CGFloat(sin(orbitAngle)) * CGFloat(orbitRadius),
                    pixel: pixel
                )
                let rawDiameter = 0.45 + CGFloat(1 - pathPhase) * 1.05
                let diameter = max(pixel, snapped(rawDiameter, pixel: pixel))
                let leadingFade = min(1, pathPhase / 0.12)
                let trailingFade = min(1, (1 - pathPhase) / 0.14)
                let opacity = max(0, min(leadingFade, trailingFade))

                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: snapped(x - diameter / 2, pixel: pixel),
                            y: snapped(y - diameter / 2, pixel: pixel),
                            width: diameter,
                            height: diameter
                        )
                    ),
                    with: .color(accent.opacity(opacity * 0.90))
                )
            }
        }
    }

    private func snapped(_ value: CGFloat, pixel: CGFloat) -> CGFloat {
        (value / pixel).rounded() * pixel
    }
}

private struct ThreadActivityIndicator: View {
    let state: ThreadExecutionState
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        ZStack {
            if state == .unknown {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
                    .frame(width: 5, height: 5)
            } else {
                PulsingStatusDot(
                    color: indicatorColor,
                    size: indicatorSize,
                    isPulsing: state == .running,
                    shadowRadius: 3
                )
            }
        }
        // The layout slot remains 10pt in ConversationRow, while this larger
        // drawing surface keeps the running shadow from being clipped.
        .frame(width: 13, height: 13)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var indicatorColor: Color {
        switch state {
        case .running: return .green
        case .waitingForInput: return .yellow
        case .idle: return .white.opacity(0.20)
        case .interrupted: return .orange.opacity(0.72)
        case .failed: return .red.opacity(0.76)
        case .unknown: return .clear
        }
    }

    private var indicatorSize: CGFloat {
        switch state {
        case .running: return 5.5
        case .waitingForInput: return 5.5
        case .idle, .interrupted, .failed: return 4.5
        case .unknown: return 5
        }
    }

    private var helpText: String {
        switch state {
        case .running: return language.text("执行中", "Running")
        case .waitingForInput: return language.text("等待输入", "Input needed")
        case .idle: return language.text("空闲", "Idle")
        case .interrupted: return language.text("已中断", "Interrupted")
        case .failed: return language.text("失败", "Failed")
        case .unknown: return language.text("状态未知", "Status unknown")
        }
    }
}

private struct PulsingStatusDot: View {
    let color: Color
    let size: CGFloat
    let isPulsing: Bool
    let shadowRadius: CGFloat
    @Environment(\.islandStatusAnimationsEnabled) private var animationsEnabled

    @ViewBuilder
    var body: some View {
        if isPulsing, animationsEnabled {
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.4) / 1.4
                let wave = 1 - abs(cycle * 2 - 1)
                dot(scale: 0.88 + wave * 0.24, opacity: 0.48 + wave * 0.52)
            }
            .frame(width: size, height: size)
        } else {
            dot(scale: 1, opacity: 1)
        }
    }

    private func dot(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(
                color: isPulsing && animationsEnabled ? color.opacity(0.55) : .clear,
                radius: isPulsing && animationsEnabled ? shadowRadius : 0
            )
    }
}

private enum ThreadConfigurationDensity {
    case full
    case compact
    case minimal

    init(availableRowWidth: CGFloat) {
        if availableRowWidth >= 450 {
            self = .full
        } else if availableRowWidth >= 370 {
            self = .compact
        } else {
            self = .minimal
        }
    }

    var showsModel: Bool { self == .full }
    var showsReasoning: Bool { self != .minimal }
}

private struct ThreadConfigurationView: View {
    private static let contextWidth: CGFloat = 16
    private static let fastWidth: CGFloat = 16
    private static let modelWidth: CGFloat = 58
    private static let spacing: CGFloat = 3
    let thread: ThreadSummary
    let density: ThreadConfigurationDensity
    let reasoningWidth: CGFloat
    let onContextHover: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        HStack(spacing: Self.spacing) {
            ThreadContextWindowStatusView(
                usage: thread.tokenUsage,
                onHoverChange: onContextHover
            )

            ThreadFastStatusIconView(thread: thread)

            if density.showsModel {
                modelSlot
            }
            if density.showsReasoning {
                reasoningSlot
            }
        }
        .frame(width: configurationWidth, alignment: .leading)
    }

    private var configurationWidth: CGFloat {
        switch density {
        case .full:
            return Self.contextWidth + Self.fastWidth + Self.modelWidth
                + reasoningWidth + Self.spacing * 3
        case .compact:
            return Self.contextWidth + Self.fastWidth + reasoningWidth
                + Self.spacing * 2
        case .minimal:
            return Self.contextWidth + Self.fastWidth + Self.spacing
        }
    }

    @ViewBuilder
    private var modelSlot: some View {
        if let model = thread.model {
            Text(displayModelName(model))
                .font(.system(size: IslandTypography.body, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.modelWidth, alignment: .leading)
                .help(displayModelName(model))
        } else {
            Color.clear.frame(width: Self.modelWidth, height: 1)
        }
    }

    @ViewBuilder
    private var reasoningSlot: some View {
        if let effort = thread.reasoningEffort,
           !effort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let displayLabel = CodexDisplayPolicy.reasoningEffortLabel(effort)
            ThreadSettingBadge(
                text: displayLabel,
                color: reasoningBadgeColor(for: displayLabel)
            )
            .frame(width: reasoningWidth, alignment: .leading)
            .help(
                language.text(
                    "推理强度：\(displayLabel)",
                    "Reasoning effort: \(displayLabel)"
                )
            )
        } else {
            Color.clear.frame(width: reasoningWidth, height: 1)
        }
    }

    private func reasoningBadgeColor(for displayLabel: String) -> Color {
        switch displayLabel {
        case "max":
            // Codex CLI Max uses a warm gold-to-orange ignition palette.
            return Color(red: 1.0, green: 178.0 / 255.0, blue: 66.0 / 255.0)
                .opacity(0.94)
        case "ultra":
            // Codex CLI Ultra uses a violet-to-magenta ignition palette.
            return Color(red: 186.0 / 255.0, green: 130.0 / 255.0, blue: 1.0)
                .opacity(0.94)
        default:
            return .white.opacity(0.42)
        }
    }

    static func reasoningColumnWidth(
        for threads: [ThreadSummary]
    ) -> CGFloat {
        threads.compactMap { thread -> CGFloat? in
            guard let effort = thread.reasoningEffort?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !effort.isEmpty else {
                return nil
            }
            let font = NSFont.monospacedSystemFont(
                ofSize: IslandTypography.settingBadge,
                weight: .semibold
            )
            let displayLabel = CodexDisplayPolicy.reasoningEffortLabel(effort)
            let textWidth = (displayLabel as NSString).size(
                withAttributes: [.font: font]
            ).width
            return ceil(textWidth) + 11
        }.max() ?? 0
    }

}

private struct ThreadContextWindowStatusView: View {
    let usage: ThreadTokenUsage?
    let onHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isPointerInside = false

    var body: some View {
        GeometryReader { proxy in
            contextRing
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let localFrame = proxy.frame(
                            in: .named(IslandCoordinateSpace.name)
                        )
                        isPointerInside = true
                        onHoverChange(
                            true,
                            CGPoint(
                                x: localFrame.minX + location.x,
                                y: localFrame.minY + location.y
                            )
                        )
                    case .ended:
                        guard isPointerInside else { return }
                        isPointerInside = false
                        onHoverChange(false, nil)
                    }
                }
                .help(contextWindowHelp(usage, language: language))
        }
        .frame(width: 16, height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contextWindowHelp(usage, language: language))
    }

    private var contextRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: 2.2)

            if let fraction = contextWindowFraction(usage) {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Color.white.opacity(0.58),
                        style: StrokeStyle(
                            lineWidth: 2.2,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 11, height: 11)
    }
}

private struct ThreadFastStatusIconView: View {
    let thread: ThreadSummary
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(fastColor)
            .frame(width: 16, height: 20)
            .contentShape(Rectangle())
            .help(fastHelp)
            .accessibilityLabel(fastHelp)
    }

    private var fastColor: Color {
        guard let tier = thread.serviceTier?.lowercased() else {
            return .white.opacity(0.08)
        }
        let isFast = tier == "priority" || tier == "fast"
        let isInferred = thread.serviceTierSource == .effectiveConfig
        if isFast {
            return theme.accent.opacity(isInferred ? 0.62 : 0.94)
        }
        return .white.opacity(isInferred ? 0.08 : 0.12)
    }

    private var fastHelp: String {
        let fast: String
        if let tier = thread.serviceTier?.lowercased() {
            fast = tier == "priority" || tier == "fast"
                ? language.text("Fast 开启", "Fast on")
                : language.text("Fast 关闭", "Fast off")
        } else {
            fast = language.text("Fast 状态未知", "Fast status unknown")
        }
        let source = thread.serviceTierSource == .effectiveConfig
            ? language.text(
                "，Fast 按当前配置推断",
                ", Fast inferred from the current configuration"
            )
            : ""
        return "\(fast)\(source)"
    }
}

private struct ThreadTokenUsageView: View {
    @AppStorage("codexIsland.remainingShowsCredits")
    private var showsRemainingCredits = false
    let usage: ThreadTokenUsage?
    let onHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isPointerInside = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let usage {
                    Text(showsRemainingCredits
                        ? (usage.creditEstimate?.amountText ?? "—")
                        : compactTokenCount(usage.totalTokens))
                        .font(.system(size: IslandTypography.body, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(showsRemainingCredits ? creditsGold : Color.white.opacity(0.31))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(
                            tokenUsageHelp(usage, language: language)
                        )
                } else {
                    Color.clear
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard usage != nil else { return }
                switch phase {
                case .active(let location):
                    let localFrame = proxy.frame(
                        in: .named(IslandCoordinateSpace.name)
                    )
                    isPointerInside = true
                    onHoverChange(
                        true,
                        CGPoint(
                            x: localFrame.minX + location.x,
                            y: localFrame.minY + location.y
                        )
                    )
                case .ended:
                    guard isPointerInside else { return }
                    isPointerInside = false
                    onHoverChange(false, nil)
                }
            }
        }
        .frame(width: 46, height: 20)
    }
}

private struct TokenUsageDetailPopover: View {
    @AppStorage("codexIsland.remainingShowsCredits")
    private var showsRemainingCredits = false
    static let minimumWidth: CGFloat = 278
    static let height: CGFloat = 78

    static func size(
        for usage: ThreadTokenUsage,
        language: IslandInterfaceLanguage
    ) -> CGSize {
        CGSize(
            width: width(for: usage, language: language),
            height: height
        )
    }

    private static func width(
        for usage: ThreadTokenUsage,
        language: IslandInterfaceLanguage
    ) -> CGFloat {
        let longestValue = [
            usage.totalTokens,
            usage.inputTokens,
            usage.cachedInputTokens,
            usage.outputTokens,
            usage.reasoningOutputTokens
        ]
            .map { exactTokenCount($0).count }
            .max() ?? 0
        let baseWidth: CGFloat = language == .english ? 320 : 290
        let overflowCharacters = max(0, longestValue - 13)
        let creditCharacters = (usage.creditEstimate?.displayText.count ?? 9) + 2
        let headerWidth = CGFloat(language == .english ? 110 : 68)
            + CGFloat(exactTokenCount(usage.totalTokens).count) * 7
            + CGFloat(creditCharacters) * 6.5 + 60
        return min(460, max(headerWidth, baseWidth + CGFloat(overflowCharacters) * 13))
    }

    let usage: ThreadTokenUsage
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        let width = Self.width(for: usage, language: language)

        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(language.text("累计消耗", "TOTAL USAGE"))
                    .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                    .tracking(0.25)
                    .foregroundStyle(.white.opacity(0.38))

                Text(consumptionText)
                    .font(.system(size: IslandTypography.body, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-0.45)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .help(tokenCreditHelp(usage, language: language))

                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                detail(language.text("输入", "Input"), usage.inputTokens)
                divider
                detail(
                    language.text("缓存", "Cache"),
                    usage.cachedInputTokens
                )
            }

            HStack(spacing: 7) {
                detail(language.text("输出", "Output"), usage.outputTokens)
                divider
                detail(
                    language.text("推理", "Reasoning"),
                    usage.reasoningOutputTokens
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width, height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.018, green: 0.020, blue: 0.026))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.11),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .shadow(color: .black.opacity(0.48), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokenUsageHelp(usage, language: language))
    }

    private var consumptionText: AttributedString {
        let tokenValue = exactTokenCount(usage.totalTokens) + language.text(" 词元", " Tokens")
        let creditValue = localizedCredits(usage.creditEstimate?.displayText ?? "— credits", language: language)
        var first = AttributedString(showsRemainingCredits ? creditValue : tokenValue)
        first.foregroundColor = showsRemainingCredits ? creditsGold : theme.accent.opacity(0.88)
        var second = AttributedString(" (" + (showsRemainingCredits ? tokenValue : creditValue) + ")")
        second.foregroundColor = showsRemainingCredits ? theme.accent.opacity(0.88) : creditsGold
        first.append(second)
        return first
    }

    private func detail(
        _ label: String,
        _ value: Int64,
        color: Color = .white.opacity(0.68)
    ) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Text(exactTokenCount(value))
                .font(.system(size: IslandTypography.body, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .tracking(-0.45)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 1, height: 14)
    }
}

private struct ContextWindowPopover: View {
    static let width: CGFloat = 210
    static let height: CGFloat = 72
    static let size = CGSize(width: width, height: height)

    let usage: ThreadTokenUsage?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.text("上下文窗口", "Context window"))
                .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.42))

            if let values = contextWindowValues(usage) {
                Text(usageSummary(values))
                    .font(.system(size: IslandTypography.emphasized, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                Text(tokenSummary(values))
                    .font(.system(size: IslandTypography.body, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent.opacity(0.84))
                    .lineLimit(1)
            } else {
                Text(
                    language.text(
                        "当前会话暂未记录上下文用量",
                        "Context usage is unavailable for this session"
                    )
                )
                .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: Self.width, height: Self.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.018, green: 0.020, blue: 0.026))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.11),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .shadow(color: .black.opacity(0.48), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contextWindowHelp(usage, language: language))
    }

    private func usageSummary(
        _ values: (used: Int64, window: Int64)
    ) -> String {
        let usedPercent = contextWindowUsedPercent(values)
        let remainingPercent = max(0, 100 - usedPercent)
        return language.text(
            "已使用 \(usedPercent)%（剩余 \(remainingPercent)%）",
            "\(usedPercent)% used (\(remainingPercent)% left)"
        )
    }

    private func tokenSummary(
        _ values: (used: Int64, window: Int64)
    ) -> String {
        language.text(
            "已使用 \(compactTokenCount(values.used)) / \(compactTokenCount(values.window)) 词元",
            "\(compactTokenCount(values.used)) / \(compactTokenCount(values.window)) tokens used"
        )
    }
}

private struct TokenChartLegendPopover: View {
    @AppStorage("codexIsland.remainingShowsCredits")
    private var showsRemainingCredits = false
    private static let horizontalPadding: CGFloat = 11
    private static let verticalPadding: CGFloat = 9

    let kind: TokenChartLegendKind

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    static func size(
        for kind: TokenChartLegendKind,
        language: IslandInterfaceLanguage
    ) -> CGSize {
        switch (kind, language) {
        case (.actual, .chinese):
            return CGSize(width: 272, height: 68)
        case (.actual, .english):
            return CGSize(width: 314, height: 72)
        case (.modeEquivalent, .chinese):
            return CGSize(width: 344, height: 120)
        case (.modeEquivalent, .english):
            return CGSize(width: 358, height: 146)
        }
    }

    var body: some View {
        let popoverSize = Self.size(for: kind, language: language)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TokenChartLegendMarker(
                    kind: kind,
                    color: markerColor,
                    isVisible: true,
                    width: 5,
                    height: 10
                )

                Text(kind.title(for: language, credits: showsRemainingCredits))
                    .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
            }

            Text(kind.explanation(for: language, credits: showsRemainingCredits))
                .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(
            width: popoverSize.width,
            height: popoverSize.height,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.018, green: 0.020, blue: 0.026))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .shadow(color: .black.opacity(0.52), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(kind.title(for: language, credits: showsRemainingCredits))，\(kind.explanation(for: language, credits: showsRemainingCredits))"
        )
    }

    private var markerColor: Color {
        if showsRemainingCredits { return creditsGold }
        switch kind {
        case .actual:
            return theme.accent.opacity(0.78)
        case .modeEquivalent:
            return theme.accent.opacity(0.90)
        }
    }

    private var titleColor: Color {
        if showsRemainingCredits { return creditsGold }
        switch kind {
        case .actual:
            return .white.opacity(0.82)
        case .modeEquivalent:
            return theme.accent.opacity(0.92)
        }
    }
}

private struct ThreadSettingBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: IslandTypography.settingBadge, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(color.opacity(0.11))
            )
    }
}

private struct AccountActivityCard: View {
    @AppStorage("codexIsland.remainingShowsCredits")
    private var showsRemainingCredits = false
    let identity: ProfileIdentitySummary
    let usage: UsageSummary
    let todayTokens: Int64?
    let hourlyUsage: [HourlyUsageBucket]
    let dailyUsage: [DailyUsageBucket]
    let billedTodayTokens: Int64?
    let billedHourlyUsage: [HourlyUsageBucket]
    let billedDailyUsage: [DailyUsageBucket]
    let chartCreditTotals: [Date: CodexChartCreditTotal]
    let window: RateLimitWindow?
    let remainingTokenEstimate: CodexRemainingTokenEstimate?
    let resetSummary: ResetCreditSummary?
    let onResetHoverChange: (Bool, CGPoint?) -> Void
    let onLegendHoverChange: (TokenChartLegendKind, Bool, CGPoint?) -> Void
    let planLabel: String?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme
    @AppStorage("codexIsland.tokenChartShowsActual")
    private var showsActual = true
    @AppStorage("codexIsland.tokenChartShowsBilled")
    private var showsBilled = true
    @State private var hoveredBucket: DailyUsageBucket?
    @State private var hoveredHourlyBucket: HourlyUsageBucket?
    @Binding private var chartRange: TokenChartRange
    @State private var avatarImage: NSImage?

    init(
        identity: ProfileIdentitySummary,
        usage: UsageSummary,
        todayTokens: Int64?,
        hourlyUsage: [HourlyUsageBucket],
        dailyUsage: [DailyUsageBucket],
        billedTodayTokens: Int64?,
        billedHourlyUsage: [HourlyUsageBucket],
        billedDailyUsage: [DailyUsageBucket],
        chartCreditTotals: [Date: CodexChartCreditTotal],
        window: RateLimitWindow?,
        remainingTokenEstimate: CodexRemainingTokenEstimate?,
        resetSummary: ResetCreditSummary?,
        onResetHoverChange: @escaping (Bool, CGPoint?) -> Void,
        onLegendHoverChange: @escaping (
            TokenChartLegendKind,
            Bool,
            CGPoint?
        ) -> Void,
        chartRange: Binding<TokenChartRange>,
        planLabel: String?
    ) {
        self.identity = identity
        self.usage = usage
        self.todayTokens = todayTokens
        self.hourlyUsage = hourlyUsage
        self.dailyUsage = dailyUsage
        self.billedTodayTokens = billedTodayTokens
        self.billedHourlyUsage = billedHourlyUsage
        self.billedDailyUsage = billedDailyUsage
        self.chartCreditTotals = chartCreditTotals
        self.window = window
        self.remainingTokenEstimate = remainingTokenEstimate
        self.resetSummary = resetSummary
        self.onResetHoverChange = onResetHoverChange
        self.onLegendHoverChange = onLegendHoverChange
        self.planLabel = planLabel
        _avatarImage = State(initialValue: identity.avatarData.flatMap(NSImage.init(data:)))
        _chartRange = chartRange
    }

    private var recentUsage: [DailyUsageBucket] {
        CodexUsageTimeline.lastDaysIncludingToday(
            from: usage.dailyUsageBuckets,
            todayTokens: todayTokens,
            localDailyBuckets: dailyUsage
        )
    }

    private var billedRecentUsage: [DailyUsageBucket] {
        CodexUsageTimeline.lastDaysIncludingToday(
            from: usage.dailyUsageBuckets,
            todayTokens: billedTodayTokens,
            localDailyBuckets: billedDailyUsage
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    profileAvatar

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName)
                            .font(.system(size: IslandTypography.profileName, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        if let planLabel {
                            Text(compactPlanBadgeLabel(planLabel))
                                .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.accent.opacity(0.88))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(theme.accent.opacity(0.09))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            theme.accent.opacity(0.14),
                                            lineWidth: 1 / max(1, displayScale)
                                        )
                                )
                                .fixedSize(horizontal: true, vertical: true)
                                .help(planLabel)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 178, alignment: .leading)

                QuotaMetric(
                    window: window,
                    planLabel: planLabel,
                    tokenEstimate: remainingTokenEstimate,
                    resetSummary: resetSummary,
                    onResetHoverChange: onResetHoverChange
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, IslandLayout.contentHorizontalInset)
            .frame(height: 76)
            .padding(.top, 4)

            Hairline()
                .padding(.horizontal, IslandLayout.contentHorizontalInset)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(activityTitle)
                        .font(.system(size: IslandTypography.emphasized, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)

                    if let activityDetail {
                        Text(activityDetail)
                            .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.accent.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .help(String(activityDetail.characters) + language.text(
                                "。额度点 仅按本机日志折算，不包含其他电脑的用量。≥ 表示本机部分调用缺少费率或明细，仅显示可计价部分；— 表示暂无足够本机明细。",
                                ". Credits are calculated from local logs only, excluding other computers. ≥ indicates some local calls lack pricing details; — means insufficient local records."
                            ))
                    }

                    Spacer(minLength: 4)
                    chartLegend
                        .layoutPriority(2)
                    chartRangePicker
                        .layoutPriority(3)
                }
                .frame(height: 28)

                if showsRemainingCredits {
                    CreditActivityChart(
                        buckets: creditChartBuckets,
                        showsStandard: showsActual, showsActualCredits: showsBilled,
                        hoveredID: chartRange == .days30 ? hoveredBucket?.id : hoveredHourlyBucket.map { String($0.hourStart.timeIntervalSince1970) },
                        onHover: { id, hovering in
                            if chartRange == .days30 {
                                updateHoveredBucket(recentUsage.first { $0.id == id }, hovering: hovering)
                            } else {
                                updateHoveredHourlyBucket(hourlyUsage.first { String($0.hourStart.timeIntervalSince1970) == id }, hovering: hovering)
                            }
                        }
                    )
                    .frame(height: 82)
                } else if chartRange == .days30 {
                    DailyTokenActivityChart(
                        actualBuckets: recentUsage,
                        billedBuckets: billedRecentUsage,
                        showsActual: showsActual,
                        showsBilled: showsBilled,
                        hoveredBucket: hoveredBucket,
                        onHover: updateHoveredBucket
                    )
                    .frame(height: 82)
                } else {
                    HourlyTokenActivityChart(
                        actualBuckets: hourlyUsage,
                        billedBuckets: billedHourlyUsage,
                        showsActual: showsActual,
                        showsBilled: showsBilled,
                        hoveredBucket: hoveredHourlyBucket,
                        onHover: updateHoveredHourlyBucket
                    )
                    .frame(height: 82)
                }

                chartAxis
                    .frame(height: 17, alignment: .top)
            }
            .padding(.horizontal, IslandLayout.contentHorizontalInset)
            .padding(.top, 1)
            .padding(.bottom, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: identity.avatarData) { data in
            avatarImage = data.flatMap(NSImage.init(data:))
        }
        .onAppear {
            if !showsActual && !showsBilled {
                showsBilled = true
            }
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let image = avatarImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(avatarBorder)
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent.opacity(0.58), theme.secondaryAccent.opacity(0.36)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(displayInitial)
                    .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 44, height: 44)
            .overlay(avatarBorder)
        }
    }

    private var avatarBorder: some View {
        Circle()
            .strokeBorder(
                Color.white.opacity(0.12),
                lineWidth: 1 / max(1, displayScale)
            )
    }

    private var displayName: String {
        if let value = identity.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return language.text("Codex 用户", "Codex user")
    }

    private var displayInitial: String {
        displayName.first.map(String.init)?.uppercased() ?? "C"
    }

    private var activityTitle: String {
        chartRange == .days30
            ? language.text("每日", "Daily")
            : language.text("分时", "Hourly")
    }

    private var creditChartBuckets: [CreditChartBucket] {
        if chartRange == .days30 {
            let totals = dailyCreditTotals
            return recentUsage.map { bucket in
                CreditChartBucket(id: bucket.id,
                    label: shortUsageDate(bucket.startDate, language: language),
                    total: totals[bucket.startDate] ?? CodexChartCreditTotal())
            }
        }
        return hourlyUsage.map { bucket in
            CreditChartBucket(id: String(bucket.hourStart.timeIntervalSince1970),
                label: hourlyUsageDateText(bucket.hourStart, language: language),
                total: chartCreditTotals[bucket.hourStart] ?? CodexChartCreditTotal())
        }
    }

    private var activityDetail: AttributedString? {
        if chartRange == .hours48,
           let bucket = hoveredHourlyBucket ?? hourlyUsage.last {
            let billed = billedHourlyUsage.first {
                $0.hourStart == bucket.hourStart
            }?.tokens ?? bucket.tokens
            return chartDetail(
                dateText: hourlyUsageDateText(bucket.hourStart, language: language),
                actualTokens: bucket.tokens,
                billedTokens: billed,
                creditTotal: chartCreditTotals[bucket.hourStart] ?? CodexChartCreditTotal()
            )
        }
        if chartRange == .days30,
           let bucket = hoveredBucket ?? recentUsage.last {
            let billed = billedRecentUsage.first {
                $0.startDate == bucket.startDate
            }?.tokens ?? bucket.tokens
            return chartDetail(
                dateText: shortUsageDate(bucket.startDate, language: language),
                actualTokens: bucket.tokens,
                billedTokens: billed,
                creditTotal: dailyCreditTotal(for: bucket.startDate)
            )
        }
        return nil
    }

    private func dailyCreditTotal(for date: String) -> CodexChartCreditTotal {
        dailyCreditTotals[date] ?? CodexChartCreditTotal()
    }

    private var dailyCreditTotals: [String: CodexChartCreditTotal] {
        let calendar = Calendar.autoupdatingCurrent
        var totals: [String: CodexChartCreditTotal] = [:]
        for (hour, value) in chartCreditTotals {
            let components = calendar.dateComponents([.year, .month, .day], from: hour)
            let key = String(format: "%04d-%02d-%02d", components.year ?? 0,
                             components.month ?? 0, components.day ?? 0)
            totals[key, default: CodexChartCreditTotal()].merge(value)
        }
        return totals
    }

    private func chartDetail(
        dateText: String,
        actualTokens: Int64,
        billedTokens: Int64,
        creditTotal: CodexChartCreditTotal
    ) -> AttributedString {
        if showsRemainingCredits {
            let values = creditTotal.chartDisplayText(
                matching: actualTokens, showsStandard: showsActual, showsActual: showsBilled
            )
            var detail = AttributedString("\(dateText) · ")
            detail.foregroundColor = theme.accent.opacity(0.72)
            var credits = AttributedString(values)
            credits.foregroundColor = creditsGold
            detail.append(credits)
            var tokens = AttributedString(" (\(chartTokenCount(actualTokens)))")
            tokens.foregroundColor = theme.accent.opacity(0.72)
            detail.append(tokens)
            return detail
        }
        let tokenText: String
        if showsActual && showsBilled {
            tokenText = "\(dateText) · \(chartTokenCount(actualTokens)) / \(chartTokenCount(billedTokens))"
        } else {
            let tokens = showsActual ? actualTokens : billedTokens
            tokenText = "\(dateText) · \(chartTokenCount(tokens))"
        }
        var detail = AttributedString(tokenText)
        let creditAmount = creditTotal.displayText(matching: actualTokens)
            .replacingOccurrences(of: " credits", with: "")
        var credits = AttributedString(" (\(creditAmount))")
        credits.foregroundColor = creditsGold
        detail.append(credits)
        return detail
    }

    private var chartLegend: some View {
        HStack(spacing: 7) {
            chartLegendItem(
                kind: .actual,
                color: (showsRemainingCredits ? creditsGold : theme.accent).opacity(0.78),
                isVisible: showsActual
            ) {
                toggleActualSeries()
            }
            chartLegendItem(
                kind: .modeEquivalent,
                color: (showsRemainingCredits ? creditsGold : theme.accent).opacity(0.86),
                isVisible: showsBilled
            ) {
                toggleBilledSeries()
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func chartLegendItem(
        kind: TokenChartLegendKind,
        color: Color,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                TokenChartLegendMarker(
                    kind: kind,
                    color: color,
                    isVisible: isVisible,
                    width: 5,
                    height: 8
                )
                Text(kind.title(for: language, credits: showsRemainingCredits))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isVisible ? 0.38 : 0.18))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onLegendHoverChange(kind, hovering, nil)
        }
        .onContinuousHover(
            coordinateSpace: .named(IslandCoordinateSpace.name)
        ) { phase in
            switch phase {
            case .active(let location):
                onLegendHoverChange(kind, true, location)
            case .ended:
                onLegendHoverChange(kind, false, nil)
            }
        }
        .accessibilityLabel(kind.title(for: language, credits: showsRemainingCredits))
        .accessibilityHint(kind.explanation(for: language, credits: showsRemainingCredits))
    }

    private func toggleActualSeries() {
        if showsActual && !showsBilled {
            showsActual = false
            showsBilled = true
        } else {
            showsActual.toggle()
        }
    }

    private func toggleBilledSeries() {
        if showsBilled && !showsActual {
            showsBilled = false
            showsActual = true
        } else {
            showsBilled.toggle()
        }
    }

    @ViewBuilder
    private var chartAxis: some View {
        let labels = chartRange == .hours48
            ? hourlyAxisLabels
            : dailyAxisLabels
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.25))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)

                if index < labels.count - 1 {
                    Spacer(minLength: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var hourlyAxisLabels: [String] {
        guard !hourlyUsage.isEmpty else { return [] }
        let lastIndex = hourlyUsage.count - 1
        let indices = Array(Set([0, 12, 24, 36, lastIndex]))
            .filter { $0 >= 0 && $0 <= lastIndex }
            .sorted()
        return indices.map { index in
            hourlyAxisLabel(
                hourlyUsage[index].hourStart,
                isCurrent: index == lastIndex
            )
        }
    }

    private var dailyAxisLabels: [String] {
        guard !recentUsage.isEmpty else { return [] }
        let lastIndex = recentUsage.count - 1
        let indices = Array(Set([0, lastIndex / 2, lastIndex])).sorted()
        return indices.map { index in
            if index == lastIndex {
                return language.text("今天", "Today")
            }
            return shortUsageDate(recentUsage[index].startDate, language: language)
        }
    }

    private func hourlyAxisLabel(_ date: Date, isCurrent: Bool) -> String {
        if isCurrent { return language.text("现在", "Now") }
        let calendar = Calendar.autoupdatingCurrent
        let targetDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let daysAgo = calendar.dateComponents(
            [.day],
            from: targetDay,
            to: today
        ).day ?? 0
        let hour = calendar.component(.hour, from: date)
        let time = String(format: "%02d:00", hour)
        if language == .chinese {
            switch daysAgo {
            case 0: return "今天 \(time)"
            case 1: return "昨天 \(time)"
            case 2: return "前天 \(time)"
            default:
                let month = calendar.component(.month, from: date)
                let day = calendar.component(.day, from: date)
                return "\(month)/\(day) \(time)"
            }
        }
        switch daysAgo {
        case 0: return "Today \(hour)h"
        case 1: return "-1d \(hour)h"
        case 2: return "-2d \(hour)h"
        default: return "-\(daysAgo)d \(hour)h"
        }
    }

    private var chartRangePicker: some View {
        HStack(spacing: 0) {
            chartRangeButton(
                .days30,
                label: language.text("30日", "30D")
            )
            chartRangeButton(
                .hours48,
                label: language.text("48时", "48H")
            )
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.07),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private func chartRangeButton(
        _ range: TokenChartRange,
        label: String
    ) -> some View {
        Button {
            chartRange = range
            hoveredBucket = nil
            hoveredHourlyBucket = nil
        } label: {
            Text(label)
                .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    chartRange == range
                        ? theme.accent.opacity(0.88)
                        : Color.white.opacity(0.28)
                )
                .padding(.horizontal, 5)
                .frame(height: 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            chartRange == range
                                ? theme.accent.opacity(0.11)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help(range.helpText(language: language))
    }

    private func updateHoveredBucket(_ bucket: DailyUsageBucket?, hovering: Bool) {
        if hovering {
            hoveredBucket = bucket
        } else if hoveredBucket?.id == bucket?.id {
            hoveredBucket = nil
        }
    }

    private func updateHoveredHourlyBucket(
        _ bucket: HourlyUsageBucket?,
        hovering: Bool
    ) {
        if hovering {
            hoveredHourlyBucket = bucket
        } else if hoveredHourlyBucket?.id == bucket?.id {
            hoveredHourlyBucket = nil
        }
    }
}

enum TokenChartRange {
    case days30
    case hours48

    func helpText(language: IslandInterfaceLanguage) -> String {
        switch self {
        case .days30:
            return language.text("查看近30天每日用量", "Show daily usage for 30 days")
        case .hours48:
            return language.text("查看近48小时分时用量", "Show hourly usage for 48 hours")
        }
    }
}

private enum TokenChartBarStyle {
    case solid
    case marker(seed: UInt64)
}

private struct TokenChartBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        return Path(
            roundedRect: rect,
            cornerRadius: min(rect.width, rect.height) / 2
        )
    }
}

private struct TokenChartSketchRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func signed(_ amplitude: CGFloat) -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        let unit = CGFloat(value & 0xFFFF) / CGFloat(UInt16.max)
        return ((unit * 2) - 1) * amplitude
    }
}

private func tokenChartSketchSeed(_ value: String) -> UInt64 {
    value.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
        (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
}

private func tokenChartSketchSeed(_ hourStart: Date) -> UInt64 {
    let hour = Int64(floor(hourStart.timeIntervalSince1970 / 3_600))
    return UInt64(bitPattern: hour) &* 0x9E37_79B9_7F4A_7C15
}

private struct TokenChartLegendMarker: View {
    let kind: TokenChartLegendKind
    let color: Color
    let isVisible: Bool
    let width: CGFloat
    let height: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if isVisible {
                TokenChartSlimBar(
                    height: height,
                    width: width,
                    color: color,
                    isEmpty: false,
                    style: kind == .actual
                        ? .solid
                        : .marker(seed: tokenChartSketchSeed("legend"))
                )
            } else {
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .strokeBorder(
                        color.opacity(0.46),
                        lineWidth: 1 / max(1, displayScale)
                    )
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct TokenChartSlimBar: View {
    let height: CGFloat
    let width: CGFloat
    let color: Color
    let isEmpty: Bool
    var style: TokenChartBarStyle = .solid

    @Environment(\.displayScale) private var displayScale

    @ViewBuilder
    var body: some View {
        if !isEmpty {
            switch style {
            case .solid:
                TokenChartBarShape()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)
            case .marker(let seed):
                Canvas(opaque: false, colorMode: .linear) { context, size in
                    drawMarkerBar(
                        context: &context,
                        size: size,
                        seed: seed
                    )
                }
                .frame(width: width, height: height)
            }
        }
    }

    private func drawMarkerBar(
        context: inout GraphicsContext,
        size: CGSize,
        seed: UInt64
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let pixel = 1 / max(1, displayScale)
        var random = TokenChartSketchRandom(seed: seed)
        let baseInset = max(
            pixel / 2,
            min(0.42, size.width * 0.08)
        )
        let baseRect = CGRect(
            x: baseInset,
            y: baseInset,
            width: max(pixel, size.width - (baseInset * 2)),
            height: max(pixel, size.height - (baseInset * 2))
        )
        let silhouette = TokenChartBarShape().path(in: baseRect)

        // A transparent body with two slightly misregistered outlines stays
        // legible at menu-bar scale while retaining a restrained hand-drawn
        // character. The silhouette still preserves the exact data height.
        context.fill(silhouette, with: .color(color.opacity(0.075)))

        let primaryWidth = max(pixel, min(0.82, size.width * 0.18))
        let secondaryWidth = max(pixel, min(0.58, size.width * 0.13))
        let maximumOffset = min(0.20, size.width * 0.04)
        let topOffset = min(0.22, size.height * 0.018)

        for pass in 0..<2 {
            let xOffset = random.signed(maximumOffset)
            let yOffset = pass == 0
                ? max(0, random.signed(topOffset))
                : max(0, random.signed(topOffset * 0.75))
            let passInset = baseInset + CGFloat(pass) * min(0.10, pixel / 2)
            let rect = CGRect(
                x: max(0, passInset + xOffset),
                y: passInset + yOffset,
                width: max(
                    pixel,
                    size.width - (passInset * 2) - abs(xOffset)
                ),
                height: max(
                    pixel,
                    size.height - (passInset * 2) - yOffset
                )
            )
            let outline = TokenChartBarShape().path(in: rect)
            context.stroke(
                outline,
                with: .color(color.opacity(pass == 0 ? 0.72 : 0.30)),
                style: StrokeStyle(
                    lineWidth: pass == 0 ? primaryWidth : secondaryWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

private struct TokenChartCombinedBar: View {
    let actualHeight: CGFloat
    let billedHeight: CGFloat
    let width: CGFloat
    let color: Color
    let showsActual: Bool
    let showsBilled: Bool
    let isHovered: Bool
    let seed: UInt64

    private var visibleActualHeight: CGFloat {
        showsActual ? max(0, actualHeight) : 0
    }

    private var visibleBilledHeight: CGFloat {
        showsBilled ? max(0, billedHeight) : 0
    }

    private var combinedHeight: CGFloat {
        max(visibleActualHeight, visibleBilledHeight)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if visibleBilledHeight > 0 {
                TokenChartSlimBar(
                    height: visibleBilledHeight,
                    width: width,
                    color: color,
                    isEmpty: false,
                    style: .marker(seed: seed)
                )
                .opacity(isHovered ? 1 : 0.92)
            }

            if visibleActualHeight > 0 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.58)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width, height: visibleActualHeight)
                    .opacity(isHovered ? 0.98 : 0.76)
            }
        }
        .frame(width: width, height: combinedHeight, alignment: .bottom)
        .clipShape(TokenChartBarShape())
    }
}

private struct CreditChartBucket: Identifiable {
    var id: String
    var label: String
    var total: CodexChartCreditTotal
}

private struct CreditActivityChart: View {
    let buckets: [CreditChartBucket]
    let showsStandard: Bool
    let showsActualCredits: Bool
    let hoveredID: String?
    let onHover: (String?, Bool) -> Void
    @Environment(\.islandInterfaceLanguage) private var language

    private func visibleCost(_ bucket: CreditChartBucket) -> Double {
        max(showsStandard ? bucket.total.standardCredits : 0,
            showsActualCredits ? bucket.total.credits : 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(0.01, buckets.map(visibleCost).max() ?? 0)
            HStack(alignment: .bottom, spacing: IslandLayout.activityChartBarSpacing) {
                ForEach(buckets) { bucket in
                    let standard = showsStandard ? bucket.total.standardCredits : 0
                    let actual = showsActualCredits ? bucket.total.credits : 0
                    ZStack(alignment: .bottom) {
                        Color.clear
                        TokenChartCombinedBar(
                            actualHeight: CGFloat(standard / maximum) * proxy.size.height,
                            billedHeight: CGFloat(actual / maximum) * proxy.size.height,
                            width: 6.25, color: creditsGold,
                            showsActual: showsStandard, showsBilled: showsActualCredits,
                            isHovered: hoveredID == bucket.id,
                            seed: tokenChartSketchSeed(bucket.id)
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onHover { onHover(bucket.id, $0) }
                    .help(bucket.total.tokens == 0
                        ? bucket.label + language.text("：暂无本机用量记录", ": no local usage records")
                        : bucket.label + (bucket.total.unpricedCalls > 0
                            ? language.text("（仅可计价部分）", " (priced portion only)") : "") + language.text(
                        "：本机标准 \(CodexThreadCreditEstimate(credits: bucket.total.standardCredits).amountText) 额度点；⚡实际 \(CodexThreadCreditEstimate(credits: bucket.total.credits).amountText) 额度点。标准为不开启 Fast 时的用量；实际 − 标准为开启 Fast 浪费的额度。",
                        ": local Standard \(CodexThreadCreditEstimate(credits: bucket.total.standardCredits).amountText) credits; ⚡ Actual \(CodexThreadCreditEstimate(credits: bucket.total.credits).amountText) credits. Standard assumes Fast off; Actual minus Standard is the extra Fast cost."
                    ))
                }
            }
        }
    }
}

private struct DailyTokenActivityChart: View {
    let actualBuckets: [DailyUsageBucket]
    let billedBuckets: [DailyUsageBucket]
    let showsActual: Bool
    let showsBilled: Bool
    let hoveredBucket: DailyUsageBucket?
    let onHover: (DailyUsageBucket?, Bool) -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let billedByDate = billedBuckets.reduce(into: [String: Int64]()) {
                $0[$1.startDate] = $1.tokens
            }
            let maximum = max(1, max(
                showsActual ? actualBuckets.map(\.tokens).max() ?? 0 : 0,
                showsBilled ? billedBuckets.map(\.tokens).max() ?? 0 : 0
            ))

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.035))
                    .frame(height: 1 / max(1, displayScale))

                HStack(
                    alignment: .bottom,
                    spacing: IslandLayout.activityChartBarSpacing
                ) {
                    ForEach(actualBuckets) { bucket in
                        let billedTokens = billedByDate[bucket.startDate]
                            ?? bucket.tokens
                        let actualIntensity = Double(max(0, bucket.tokens))
                            / Double(maximum)
                        let billedIntensity = Double(max(0, billedTokens))
                            / Double(maximum)
                        let actualHeight = bucket.tokens == 0
                            ? 0
                            : max(6, proxy.size.height * CGFloat(actualIntensity))
                        let billedHeight = billedTokens == 0
                            ? 0
                            : max(6, proxy.size.height * CGFloat(billedIntensity))
                        let isHovered = hoveredBucket?.id == bucket.id

                        ZStack(alignment: .bottom) {
                            Color.clear

                            TokenChartCombinedBar(
                                actualHeight: actualHeight,
                                billedHeight: billedHeight,
                                width: 6.25,
                                color: theme.accent,
                                showsActual: showsActual,
                                showsBilled: showsBilled,
                                isHovered: isHovered,
                                seed: tokenChartSketchSeed(bucket.startDate)
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            onHover(bucket, hovering)
                        }
                        .help(
                            bucketHelp(bucket, billedTokens: billedTokens)
                        )
                    }
                }
            }
        }
    }

    private func bucketHelp(
        _ bucket: DailyUsageBucket,
        billedTokens: Int64
    ) -> String {
        let date = shortUsageDate(bucket.startDate, language: language)
        if showsActual && showsBilled {
            return language.text(
                "\(date)：实际消耗 \(exactTokenCount(bucket.tokens)) 词元；⚡模式等效 \(exactTokenCount(billedTokens)) 词元",
                "\(date): Actual usage \(exactTokenCount(bucket.tokens)) tokens; mode equivalent \(exactTokenCount(billedTokens)) tokens"
            )
        }
        if showsActual {
            return language.text(
                "\(date)：实际消耗 \(exactTokenCount(bucket.tokens)) 词元",
                "\(date): Actual usage \(exactTokenCount(bucket.tokens)) tokens"
            )
        }
        return language.text(
            "\(date)：⚡模式等效 \(exactTokenCount(billedTokens)) 词元",
            "\(date): Mode equivalent \(exactTokenCount(billedTokens)) tokens"
        )
    }

}

private struct HourlyTokenActivityChart: View {
    let actualBuckets: [HourlyUsageBucket]
    let billedBuckets: [HourlyUsageBucket]
    let showsActual: Bool
    let showsBilled: Bool
    let hoveredBucket: HourlyUsageBucket?
    let onHover: (HourlyUsageBucket?, Bool) -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let billedByHour = billedBuckets.reduce(into: [Date: Int64]()) {
                $0[$1.hourStart] = $1.tokens
            }
            let maximum = max(1, max(
                showsActual ? actualBuckets.map(\.tokens).max() ?? 0 : 0,
                showsBilled ? billedBuckets.map(\.tokens).max() ?? 0 : 0
            ))

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.035))
                    .frame(height: 1 / max(1, displayScale))

                HStack(
                    alignment: .bottom,
                    spacing: IslandLayout.hourlyActivityChartBarSpacing
                ) {
                    ForEach(actualBuckets) { bucket in
                        let billedTokens = billedByHour[bucket.hourStart]
                            ?? bucket.tokens
                        let actualIntensity = Double(max(0, bucket.tokens))
                            / Double(maximum)
                        let billedIntensity = Double(max(0, billedTokens))
                            / Double(maximum)
                        let actualHeight = bucket.tokens == 0
                            ? 0
                            : max(5, proxy.size.height * CGFloat(actualIntensity))
                        let billedHeight = billedTokens == 0
                            ? 0
                            : max(5, proxy.size.height * CGFloat(billedIntensity))
                        let isHovered = hoveredBucket?.id == bucket.id
                        let isCurrentHour = Calendar.autoupdatingCurrent.isDate(
                            bucket.hourStart,
                            equalTo: Date(),
                            toGranularity: .hour
                        )
                        let isMidnight = Calendar.autoupdatingCurrent.component(
                            .hour,
                            from: bucket.hourStart
                        ) == 0

                        ZStack(alignment: .bottom) {
                            if isMidnight {
                                Rectangle()
                                    .fill(Color.white.opacity(0.055))
                                    .frame(width: 1 / max(1, displayScale))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            }

                            TokenChartCombinedBar(
                                actualHeight: actualHeight,
                                billedHeight: billedHeight,
                                width: isCurrentHour ? 4 : 3.5,
                                color: theme.accent,
                                showsActual: showsActual,
                                showsBilled: showsBilled,
                                isHovered: isHovered,
                                seed: tokenChartSketchSeed(bucket.hourStart)
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            onHover(bucket, hovering)
                        }
                        .help(
                            hourlyBucketHelp(
                                bucket,
                                billedTokens: billedTokens,
                                isCurrentHour: isCurrentHour
                            )
                        )
                    }
                }
            }
        }
    }

    private func hourlyBucketHelp(
        _ bucket: HourlyUsageBucket,
        billedTokens: Int64,
        isCurrentHour: Bool
    ) -> String {
        let suffix = isCurrentHour
            ? language.text("（本小时进行中）", " (current hour)")
            : ""
        if showsActual && showsBilled {
            return language.text(
                "\(hourlyUsageDateText(bucket.hourStart, language: language))：实际消耗 \(exactTokenCount(bucket.tokens)) 词元；⚡模式等效 \(exactTokenCount(billedTokens)) 词元\(suffix)",
                "\(hourlyUsageDateText(bucket.hourStart, language: language)): Actual usage \(exactTokenCount(bucket.tokens)) tokens; mode equivalent \(exactTokenCount(billedTokens)) tokens\(suffix)"
            )
        }
        if showsActual {
            return language.text(
                "\(hourlyUsageDateText(bucket.hourStart, language: language))：实际消耗 \(exactTokenCount(bucket.tokens)) 词元\(suffix)",
                "\(hourlyUsageDateText(bucket.hourStart, language: language)): Actual usage \(exactTokenCount(bucket.tokens)) tokens\(suffix)"
            )
        }
        return language.text(
            "\(hourlyUsageDateText(bucket.hourStart, language: language))：⚡模式等效 \(exactTokenCount(billedTokens)) 词元\(suffix)",
            "\(hourlyUsageDateText(bucket.hourStart, language: language)): Mode equivalent \(exactTokenCount(billedTokens)) tokens\(suffix)"
        )
    }
}

private struct QuotaMetric: View {
    let window: RateLimitWindow?
    let planLabel: String?
    @AppStorage("codexIsland.remainingShowsCredits")
    private var showsRemainingCredits = false
    let tokenEstimate: CodexRemainingTokenEstimate?
    let resetSummary: ResetCreditSummary?
    let onResetHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let resetTimestamp {
                    Text(
                        language.text(
                            "\(resetTimestamp) 重置",
                            "Resets \(resetTimestamp)"
                        )
                    )
                    .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.30))
                }

                if let resetSummary,
                   resetSummary.availableCount > 0 {
                    ResetSummaryLine(
                        summary: resetSummary,
                        onHoverChange: onResetHoverChange
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .layoutPriority(1)
                }

                Spacer(minLength: 4)

                if let paceAssessment {
                    Text(paceLabel(for: paceAssessment.pace))
                        .font(.system(size: IslandTypography.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(paceColor(for: paceAssessment.pace))
                        .lineLimit(1)
                        .help(paceHelp(for: paceAssessment))
                        .accessibilityLabel(paceHelp(for: paceAssessment))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(remainingText)
                    .font(.system(size: IslandTypography.display, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: true, vertical: true)

                Text(remainingAmountDisplay)
                    .font(.system(size: IslandTypography.emphasized, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(showsRemainingCredits ? creditsGold : theme.accent.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .help(showsRemainingCredits ? remainingCreditsHelp : estimatedRemainingTokenHelp)
                    .layoutPriority(1)

                Spacer(minLength: 0)
                remainingUnitPicker
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            .frame(height: 30)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(remainingBarColor.opacity(0.9))
                        .frame(width: proxy.size.width * remainingFraction)
                }
            }
            .frame(height: 9)
        }
        .padding(.leading, IslandLayout.metricCenterGutter)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var remainingText: String {
        guard let window else { return "--" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private var remainingFraction: CGFloat {
        CGFloat((window?.remainingPercent ?? 0) / 100)
    }

    private var remainingBarColor: Color {
        quotaRemainingColor(
            window?.remainingPercent,
            unavailableColor: .white.opacity(0.18)
        )
    }

    private var resetTimestamp: String? {
        guard let date = window?.resetsAt else { return nil }
        return quotaResetDateText(date, language: language)
    }

    private var estimatedRemainingTokens: Int64? {
        guard let tokenEstimate, tokenEstimate.resetsAt > Date() else { return nil }
        return tokenEstimate.tokens
    }

    private var estimatedRemainingTokenText: String? {
        guard let estimatedRemainingTokens else { return nil }
        return language.text(
            "≈\(compactTokenCount(estimatedRemainingTokens)) 词元",
            "≈\(compactTokenCount(estimatedRemainingTokens)) Tokens"
        )
    }

    private var remainingAmountDisplay: AttributedString {
        let amount = remainingAmountText
        guard !amount.hasPrefix("—") else { return AttributedString(amount) }
        var prefix = AttributedString("≈ ")
        prefix.foregroundColor = .white.opacity(0.94)
        prefix.append(AttributedString(amount))
        return prefix
    }

    private var remainingAmountText: String {
        if showsRemainingCredits {
            guard let credits = CodexDisplayPolicy.remainingCredits(
                planLabel: planLabel, remainingPercent: window?.remainingPercent
            ) else { return language.text("— 额度点", "— credits") }
            return localizedCredits(String(format: "%.0f credits", credits), language: language)
        }
        return estimatedRemainingTokenText.map { String($0.dropFirst()) }
            ?? language.text("— 词元", "— Tokens")
    }

    private var remainingCreditsHelp: String {
        language.text(
            "按 Plus 2,750 额度点、PRO5X 13,750 额度点、Pro 20X 55,000 额度点 乘以当前剩余额度比例计算",
            "Calculated from the remaining quota percentage: Plus 2,750 credits, PRO5X 13,750, Pro 20X 55,000"
        )
    }

    private var remainingUnitPicker: some View {
        HStack(spacing: 0) {
            remainingUnitButton(language.text("词元", "Tokens"), credits: false)
            remainingUnitButton(language.text("额度点", "Credits"), credits: true)
        }
        .padding(2)
        .background(alignment: .leading) {
            Capsule()
                .fill((showsRemainingCredits ? creditsGold : theme.accent).opacity(0.16))
                .frame(width: 39, height: 18)
                .offset(x: showsRemainingCredits ? 41 : 2)
        }
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .fixedSize()
    }

    private func remainingUnitButton(_ title: String, credits: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showsRemainingCredits = credits
            }
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(showsRemainingCredits == credits
                    ? (credits ? creditsGold : theme.accent)
                    : Color.white.opacity(0.38))
                .frame(width: 39, height: 18)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(credits
            ? language.text("显示剩余额度点", "Show remaining credits")
            : language.text("显示剩余 Token", "Show remaining tokens"))
        .accessibilityAddTraits(showsRemainingCredits == credits ? .isSelected : [])
    }

    private var estimatedRemainingTokenHelp: String {
        let explanation = language.text(
            "根据最近 7 天本机调用的模型、缓存、输出及各会话 Fast 使用比例，结合官方费率与实际额度变化估算；假设后续使用习惯相近，取可用额度中先耗尽的一项。跨设备和其他共享额度的使用可能影响准确性",
            "Estimated from the last 7 days of local model, cache, output, and per-session Fast usage, official rates, and observed quota changes. Assumes similar future usage and uses the first allowance to run out. Other devices and shared usage can affect accuracy"
        )
        guard tokenEstimate?.usesHistoricalCalibration == true else { return explanation }
        return explanation + language.text(
            "。当前周期样本较少，容量参考近期同套餐的已校准周期",
            ". This cycle has limited data; capacity is based on recent calibrated cycles on the same plan"
        )
    }

    private var paceAssessment: QuotaConsumptionPaceAssessment? {
        CodexDisplayPolicy.quotaConsumptionPace(window: window)
    }

    private func paceLabel(for pace: QuotaConsumptionPace) -> String {
        switch pace {
        case .slow:
            return language.text("消耗偏慢", "Below pace")
        case .normal:
            return language.text("节奏正常", "On pace")
        case .warning:
            return language.text("轻度告急", "Caution")
        case .critical:
            return language.text("严重告急", "Critical")
        }
    }

    private func paceColor(for pace: QuotaConsumptionPace) -> Color {
        switch pace {
        case .slow:
            return .purple
        case .normal:
            return .green
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }

    private func paceHelp(for assessment: QuotaConsumptionPaceAssessment) -> String {
        let used = Int(assessment.usedPercent.rounded())
        let remaining = Int(assessment.remainingPercent.rounded())
        let elapsed = Int(assessment.elapsedPercent.rounded())
        let projectedRemaining = Int(
            assessment.projectedRemainingPercentAtReset.rounded()
        )
        let coverage = Int(
            min(999, max(0, assessment.runwayCoverageRatio * 100)).rounded()
        )

        switch assessment.pace {
        case .slow:
            return language.text(
                "本周期已过 \(elapsed)%，已用 \(used)%；按当前平均速度，重置时预计仍余 \(projectedRemaining)%",
                "\(elapsed)% elapsed and \(used)% used; about \(projectedRemaining)% is projected to remain at reset"
            )
        case .normal where remaining >= 50:
            return language.text(
                "当前剩余 \(remaining)%：余量充足，短时集中使用不会触发告急",
                "\(remaining)% remains; short bursts do not trigger an alert while capacity is ample"
            )
        case .normal:
            return language.text(
                "当前剩余 \(remaining)%：按当前平均速度仍可覆盖到重置，暂不需要调整",
                "\(remaining)% remains; projected runway reaches the reset, so no action is needed"
            )
        case .warning, .critical:
            return language.text(
                "当前剩余 \(remaining)%：按当前平均速度约能覆盖剩余周期的 \(coverage)%",
                "\(remaining)% remains; projected runway covers about \(coverage)% of the time until reset"
            )
        }
    }
}

private struct ResetSummaryLine: View {
    let summary: ResetCreditSummary
    let onHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        summaryContent
            .frame(height: 18, alignment: .leading)
    }

    private var summaryContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(language.text("（", "("))
                .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))

            if summary.availableCount <= 0 {
                Text(language.text("暂无可用重置", "No resets available"))
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.30))
            } else {
                Text(language.text("剩余 ", ""))
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))

                resetCount

                Text(
                    language.text(
                        " 次重置",
                        " resets left"
                    )
                )
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
            }

            Text(language.text("）", ")"))
                .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .frame(height: 18, alignment: .leading)
    }

    private var resetCount: some View {
        Text(String(summary.availableCount))
            .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(resetCountColor)
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let localFrame = proxy.frame(
                                    in: .named(IslandCoordinateSpace.name)
                                )
                                onHoverChange(
                                    true,
                                    CGPoint(
                                        x: localFrame.minX + location.x,
                                        y: localFrame.minY + location.y
                                    )
                                )
                            case .ended:
                                onHoverChange(false, nil)
                            }
                        }
                }
            }
    }

    private var resetCountColor: Color {
        CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(summary)
            ? Color.red.opacity(0.88)
            : Color.green.opacity(0.82)
    }
}

private struct ResetExpirationPopover: View {
    let summary: ResetCreditSummary
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @Environment(\.islandColorTheme) private var theme

    static func size(
        for summary: ResetCreditSummary,
        language: IslandInterfaceLanguage
    ) -> CGSize {
        let dateCount = summary.expirationDates.count
        let missingDateCount = max(0, summary.availableCount - dateCount)
        let height: CGFloat
        if dateCount == 0 {
            height = 54
        } else {
            height = 34 + CGFloat(dateCount) * 21
                + (missingDateCount > 0 ? 21 : 0)
        }
        return CGSize(width: width(for: language), height: height)
    }

    static func width(for language: IslandInterfaceLanguage) -> CGFloat {
        language == .chinese ? 160 : 175
    }

    private var expirationDates: [Date] {
        summary.expirationDates.sorted()
    }

    private var missingDateCount: Int {
        max(0, summary.availableCount - expirationDates.count)
    }

    private var missingDateText: String {
        if language == .chinese {
            return "另有 \(missingDateCount) 次未返回到期时间"
        }
        let noun = missingDateCount == 1 ? "date" : "dates"
        return "+\(missingDateCount) \(noun) unavailable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.text("重置到期时间", "Reset expirations"))
                .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .padding(.leading, language == .chinese ? 3 : 0)
                .frame(height: 16, alignment: .leading)

            if expirationDates.isEmpty {
                Text(
                    language.text(
                        "服务暂未返回具体日期",
                        "Dates unavailable"
                    )
                )
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .frame(height: 16, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(expirationDates.enumerated()), id: \.offset) { index, date in
                        let isExpiringSoon = CodexDisplayPolicy
                            .isResetCreditExpiringWithinWeek(date)
                        HStack(spacing: 3) {
                            Text(String(index + 1))
                                .font(.system(size: IslandTypography.body, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle().fill(theme.accent.opacity(0.12))
                                )

                            Text(
                                resetExpirationDateText(
                                    date,
                                    language: language
                                )
                            )
                                .font(.system(size: IslandTypography.body, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isExpiringSoon
                                        ? Color.red.opacity(0.78)
                                        : Color.white.opacity(0.52)
                                )
                                .lineLimit(1)
                                .frame(width: 58, alignment: .leading)

                            Text(resetExpirationTimeText(date))
                                .font(.system(size: IslandTypography.body, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isExpiringSoon
                                        ? Color.red.opacity(0.78)
                                        : Color.white.opacity(0.52)
                                )
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: language == .chinese ? .center : .leading
                        )
                        .frame(height: 18)
                    }
                }
            }

            if !expirationDates.isEmpty, missingDateCount > 0 {
                Text(missingDateText)
                    .font(.system(size: IslandTypography.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.48))
                    .lineLimit(1)
                    .frame(height: 16, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(
            width: Self.width(for: language),
            height: Self.size(for: summary, language: language).height,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.018, green: 0.020, blue: 0.026))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.13),
                    lineWidth: 1 / max(1, displayScale)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 10, y: 4)
    }

}

private struct MetricDivider: View {
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.075))
            .frame(width: width, height: 70)
    }
}

private struct PixelVerticalDivider: View {
    let height: CGFloat
    let opacity: Double
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(opacity))
            .frame(width: 1 / max(1, displayScale), height: height)
    }
}

private struct IslandThemeWatermark: View {
    let theme: IslandColorTheme

    var body: some View {
        if let resourceName = theme.watermarkResourceName,
           let image = Bundle.module.url(
               forResource: resourceName,
               withExtension: "png"
           ).flatMap(NSImage.init(contentsOf:)) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(theme.usesOriginalWatermarkColors ? .original : .template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(theme.accent)
        }
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

private struct CompactQuotaRing: View {
    let fraction: CGFloat
    let color: Color

    private let drawingInset: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .inset(by: drawingInset)
                .stroke(Color.white.opacity(0.11), lineWidth: 1.6)

            Circle()
                .inset(by: drawingInset)
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        // Keep the visible ring at roughly 14pt while reserving enough room
        // for the rounded trim caps at cardinal angles such as exactly 50%.
        .frame(width: 16, height: 16)
    }
}

private func windowLabel(
    _ window: RateLimitWindow?,
    fallback: String,
    language: IslandInterfaceLanguage
) -> String {
    guard let minutes = window?.windowDurationMinutes else { return fallback }
    if minutes == 7 * 24 * 60 {
        return language.text("剩余用量", "Remaining usage")
    }
    if minutes < 60 {
        return language.text(
            "\(minutes) 分钟限额",
            "\(minutes)-minute limit"
        )
    }
    if minutes < 24 * 60, minutes % 60 == 0 {
        return language.text(
            "\(minutes / 60) 小时限额",
            "\(minutes / 60)-hour limit"
        )
    }
    if minutes % (24 * 60) == 0 {
        return language.text(
            "\(minutes / (24 * 60)) 天限额",
            "\(minutes / (24 * 60))-day limit"
        )
    }
    return fallback
}

private func compactPlanBadgeLabel(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > 10 else { return normalized }
    return String(normalized.prefix(8)) + "…"
}

private func displayModelName(_ rawValue: String) -> String {
    CodexDisplayPolicy.displayModelName(rawValue)
}

private func conversationUpdatedLabel(
    _ date: Date?,
    language: IslandInterfaceLanguage
) -> String {
    guard let date else { return "—" }
    if abs(Date().timeIntervalSince(date)) < 5 {
        return language.text("刚刚", "Just now")
    }
    return RelativeDateTimeFormatter.codexIsland(for: language).localizedString(
        for: date,
        relativeTo: Date()
    )
}

private func chartTokenCount(_ value: Int64) -> String {
    var count = Double(max(0, value))
    guard count >= 1_000 else { return String(max(0, value)) }
    let units = ["K", "M", "B", "T", "P", "E"]
    count /= 1_000
    var unitIndex = 0
    while count >= 999.95, unitIndex < units.count - 1 {
        count /= 1_000
        unitIndex += 1
    }
    return String(format: "%.1f%@", count, units[unitIndex])
}

private func compactTokenCount(_ value: Int64) -> String {
    let value = max(0, value)
    let count = Double(value)
    if value >= 1_000_000_000_000_000_000 {
        return compactScaledTokenCount(count / 1_000_000_000_000_000_000, unit: "E")
    }
    if value >= 1_000_000_000_000_000 {
        return compactScaledTokenCount(count / 1_000_000_000_000_000, unit: "P")
    }
    if value >= 1_000_000_000_000 {
        return compactScaledTokenCount(count / 1_000_000_000_000, unit: "T")
    }
    if value >= 1_000_000_000 {
        return compactScaledTokenCount(count / 1_000_000_000, unit: "B")
    }
    if value >= 100_000_000 {
        return String(format: "%.0fM", count / 1_000_000)
    }
    if value >= 10_000_000 {
        return String(format: "%.1fM", count / 1_000_000)
    }
    if value >= 1_000_000 {
        return String(format: "%.2fM", count / 1_000_000)
    }
    if value >= 100_000 {
        return String(format: "%.0fK", count / 1_000)
    }
    if value >= 10_000 {
        return String(format: "%.1fK", count / 1_000)
    }
    if value >= 1_000 {
        return String(format: "%.2fK", count / 1_000)
    }
    return String(value)
}

private func menuBarTokenCount(_ value: Int64) -> String {
    let value = max(0, value)
    let count = Double(value)
    if value >= 1_000_000_000_000 {
        return String(format: "%.0fT", count / 1_000_000_000_000)
    }
    if value >= 1_000_000_000 {
        return String(format: "%.0fB", count / 1_000_000_000)
    }
    if value >= 1_000_000 {
        return String(format: "%.0fM", count / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.0fK", count / 1_000)
    }
    return String(value)
}

private func compactScaledTokenCount(_ count: Double, unit: String) -> String {
    if count >= 100 { return String(format: "%.0f%@", count, unit) }
    if count >= 10 { return String(format: "%.1f%@", count, unit) }
    return String(format: "%.2f%@", count, unit)
}

private func shortUsageDate(
    _ value: String,
    language: IslandInterfaceLanguage
) -> String {
    let parts = value.split(separator: "-")
    guard parts.count == 3,
          let month = Int(parts[1]),
          let day = Int(parts[2]),
          (1 ... 12).contains(month) else {
        return value
    }
    if language == .chinese { return "\(month)月\(day)日" }
    let monthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]
    return "\(monthNames[month - 1]) \(day)"
}

private func hourlyUsageDateText(
    _ date: Date,
    language: IslandInterfaceLanguage
) -> String {
    DateFormatter.codexIslandHourlyUsage(for: language).string(from: date)
}

private func tokenUsageHelp(
    _ usage: ThreadTokenUsage,
    language: IslandInterfaceLanguage
) -> String {
    language.text(
        """
        累计词元：\(exactTokenCount(usage.totalTokens))
        输入：\(exactTokenCount(usage.inputTokens))（其中缓存：\(exactTokenCount(usage.cachedInputTokens))）
        输出：\(exactTokenCount(usage.outputTokens))（其中推理：\(exactTokenCount(usage.reasoningOutputTokens))）
        """,
        """
        Total tokens: \(exactTokenCount(usage.totalTokens))
        Input: \(exactTokenCount(usage.inputTokens)) (cached: \(exactTokenCount(usage.cachedInputTokens)))
        Output: \(exactTokenCount(usage.outputTokens)) (reasoning: \(exactTokenCount(usage.reasoningOutputTokens)))
        """
    ) + "\n" + tokenCreditHelp(usage, language: language)
}

private func tokenCreditHelp(
    _ usage: ThreadTokenUsage,
    language: IslandInterfaceLanguage
) -> String {
    guard let estimate = usage.creditEstimate else {
        return language.text(
            "额度点暂无法估算：历史用量、模型或费率记录不完整。",
            "Credits estimate unavailable: historical usage, model, or rate information is incomplete."
        )
    }
    var text = language.text(
        "估算消耗：\(localizedCredits(estimate.displayText, language: language))。按官方费率分别计算普通输入（输入减缓存）、缓存输入和输出，再应用各次调用的 Fast 倍率。推理已包含在输出中。此值是费用参考，不代表实际扣费。",
        "Estimated usage: \(estimate.displayText). Official rates are applied to uncached input (Input − Cache), cached input, and output, with each call's Fast multiplier. Reasoning is already included in Output. This is a cost reference, not an actual charge."
    )
    if estimate.assumesStandardTier {
        text += language.text(
            " 未记录 Fast 状态的调用按 Standard 估算。",
            " Calls without a recorded Fast setting are estimated at the Standard rate."
        )
    }
    return text
}

private func contextWindowValues(
    _ usage: ThreadTokenUsage?
) -> (used: Int64, window: Int64)? {
    guard let used = usage?.contextTokensUsed,
          let window = usage?.contextWindowTokens,
          used >= 0,
          window > 0 else {
        return nil
    }
    return (used, window)
}

private func contextWindowUsedPercent(
    _ values: (used: Int64, window: Int64)
) -> Int {
    min(
        100,
        max(
            0,
            Int(
                (Double(values.used) / Double(values.window) * 100)
                    .rounded()
            )
        )
    )
}

private func contextWindowFraction(_ usage: ThreadTokenUsage?) -> CGFloat? {
    guard let values = contextWindowValues(usage) else { return nil }
    return CGFloat(contextWindowUsedPercent(values)) / 100
}

private func contextWindowHelp(
    _ usage: ThreadTokenUsage?,
    language: IslandInterfaceLanguage
) -> String {
    guard let values = contextWindowValues(usage) else {
        return language.text(
            "上下文窗口：当前会话暂未记录上下文用量",
            "Context window: usage unavailable for this session"
        )
    }
    let usedPercent = contextWindowUsedPercent(values)
    let remainingPercent = max(0, 100 - usedPercent)
    return language.text(
        "上下文窗口：已使用 \(usedPercent)%（剩余 \(remainingPercent)%），\(compactTokenCount(values.used)) / \(compactTokenCount(values.window)) 词元",
        "Context window: \(usedPercent)% used (\(remainingPercent)% left), \(compactTokenCount(values.used)) / \(compactTokenCount(values.window)) tokens used"
    )
}

private func quotaResetDateText(
    _ date: Date,
    language: IslandInterfaceLanguage
) -> String {
    DateFormatter.codexIslandQuotaReset(for: language).string(from: date)
}

private func resetExpirationDateText(
    _ date: Date,
    language: IslandInterfaceLanguage
) -> String {
    DateFormatter.codexIslandResetExpiration(for: language).string(from: date)
}

private func resetExpirationTimeText(_ date: Date) -> String {
    DateFormatter.codexIslandResetExpirationTime.string(from: date)
}

private func exactTokenCount(_ value: Int64) -> String {
    NumberFormatter.codexIslandTokenCount.string(from: NSNumber(value: max(0, value)))
        ?? String(max(0, value))
}

private extension RelativeDateTimeFormatter {
    static func codexIsland(
        for language: IslandInterfaceLanguage
    ) -> RelativeDateTimeFormatter {
        language == .chinese ? codexIslandChinese : codexIslandEnglish
    }

    static let codexIslandChinese: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    static let codexIslandEnglish: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .short
        return formatter
    }()
}

private extension DateFormatter {
    static func codexIslandHourlyUsage(
        for language: IslandInterfaceLanguage
    ) -> DateFormatter {
        language == .chinese
            ? codexIslandHourlyUsageChinese
            : codexIslandHourlyUsageEnglish
    }

    static func codexIslandQuotaReset(
        for language: IslandInterfaceLanguage
    ) -> DateFormatter {
        language == .chinese
            ? codexIslandQuotaResetChinese
            : codexIslandQuotaResetEnglish
    }

    static func codexIslandResetExpiration(
        for language: IslandInterfaceLanguage
    ) -> DateFormatter {
        language == .chinese
            ? codexIslandResetExpirationChinese
            : codexIslandResetExpirationEnglish
    }

    static let codexIslandQuotaResetChinese: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let codexIslandHourlyUsageChinese: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 HH:00"
        return formatter
    }()

    static let codexIslandHourlyUsageEnglish: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d, HH:00"
        return formatter
    }()

    static let codexIslandQuotaResetEnglish: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    static let codexIslandResetExpirationChinese: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let codexIslandResetExpirationEnglish: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let codexIslandResetExpirationTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private extension NumberFormatter {
    static let codexIslandTokenCount: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
