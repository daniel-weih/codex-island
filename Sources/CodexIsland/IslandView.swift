import AppKit
import SwiftUI

enum IslandLayout {
    static let compactMinimumWidth: CGFloat = 300
    static let compactExtraWidth: CGFloat = 115
    static let compactFallbackWidth: CGFloat = 240
    static let compactFallbackHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 500
    static let contentHorizontalInset: CGFloat = 14
    static let metricCenterGutter: CGFloat = 10
    static let conversationRowHeight: CGFloat = 18
    static let activityChartBarSpacing: CGFloat = 2
    static let activityIndicatorSlotWidth: CGFloat = 10
    static let threadSourceColumnWidth: CGFloat = 24
    static let threadStatusColumnWidth: CGFloat = 48
    static let compactTokenEffectWidth: CGFloat = 9.5
    static let headerActionButtonSize: CGFloat = 24
    static let headerActionSpacing: CGFloat = 4
    static let headerTooltipCursorGap: CGFloat = 4
    static let headerTooltipTopGap: CGFloat = 2
    static let recentConversationsHeight = conversationRowHeight
        * CGFloat(CodexDisplayPolicy.recentThreadLimit)
    static let expandedBodyHeight: CGFloat = 84 + recentConversationsHeight

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

private enum IslandCoordinateSpace {
    static let name = "codex-island"
}

enum IslandHeaderAction: Sendable {
    case islandSettings
    case codexSettings
    case quit
}

private func activityIndicatorOffset(
    rowWidth: CGFloat,
    bucketCount: Int
) -> CGFloat {
    guard bucketCount > 0 else { return -2 }
    let panelWidth = rowWidth + IslandLayout.contentHorizontalInset * 2
    let chartWidth = panelWidth / 2
        - IslandLayout.contentHorizontalInset
        - IslandLayout.metricCenterGutter
    let totalSpacing = IslandLayout.activityChartBarSpacing
        * CGFloat(max(0, bucketCount - 1))
    let barWidth = max(0, (chartWidth - totalSpacing) / CGFloat(bucketCount))
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
}

private struct IslandPopoverPlacement {
    let center: CGPoint
    let scale: CGFloat
}

private enum IslandPopoverContent: Equatable {
    case token(threadID: String, rank: Int, usage: ThreadTokenUsage)
    case reset(ResetCreditSummary)

    var identity: String {
        switch self {
        case .token(let threadID, _, _): return "token-\(threadID)"
        case .reset: return "reset"
        }
    }

    func size(for language: IslandInterfaceLanguage) -> CGSize {
        switch self {
        case .token: return TokenUsageDetailPopover.size
        case .reset(let summary):
            return ResetExpirationPopover.size(
                for: summary,
                language: language
            )
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

private func islandDefaultTokenPopoverPointer(rank: Int, canvasSize: CGSize) -> CGPoint {
    let rowsTop = canvasSize.height - 7 - IslandLayout.recentConversationsHeight
    return CGPoint(
        x: canvasSize.width - 80,
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

struct IslandView: View {
    @ObservedObject var viewModel: CodexStatusViewModel
    @ObservedObject var displayGeometry: IslandDisplayGeometry
    @ObservedObject var displaySelection: IslandDisplaySelectionModel
    @Environment(\.displayScale) private var displayScale
    @AppStorage("codexIsland.statusAnimationsEnabled")
    private var statusAnimationsEnabled = true
    @AppStorage("codexIsland.tokenConsumptionEffectEnabled")
    private var tokenConsumptionEffectEnabled = true
    @AppStorage("codexIsland.languagePreference")
    private var storedLanguagePreference = IslandLanguagePreference.automatic.rawValue
    @State private var launchAtLoginSetting: LaunchAtLoginSettingModel
    @State private var activePopover: IslandPopoverPresentation?
    @State private var isIslandSettingsPresented = false
    @State private var hoveredHeaderAction: IslandHeaderAction?
    @State private var headerTooltipPointer: CGPoint?
    private let initialPopover: IslandPopoverPresentation?
    private let initialTokenConsumptionPhase: Double?
    private let previewDisplayPickerPresentation: Bool?
    private let previewLanguagePreference: IslandLanguagePreference?
    private let usesTimelineUpdates: Bool

    init(
        viewModel: CodexStatusViewModel,
        displayGeometry: IslandDisplayGeometry,
        displaySelection: IslandDisplaySelectionModel,
        initialHoveredTokenThreadID: String? = nil,
        initialResetSummaryHover: Bool = false,
        initialIslandSettingsPresented: Bool = false,
        previewDisplayPickerPresentation: Bool? = nil,
        initialHoveredHeaderAction: IslandHeaderAction? = nil,
        initialTokenConsumptionPhase: Double? = nil,
        previewLanguagePreference: IslandLanguagePreference? = nil,
        launchAtLoginBackend: LaunchAtLoginBackend = .live,
        usesTimelineUpdates: Bool = true
    ) {
        self.viewModel = viewModel
        self.displayGeometry = displayGeometry
        self.displaySelection = displaySelection
        self.initialTokenConsumptionPhase = initialTokenConsumptionPhase
        self.previewDisplayPickerPresentation = previewDisplayPickerPresentation
        self.previewLanguagePreference = previewLanguagePreference
        self.usesTimelineUpdates = usesTimelineUpdates
        _launchAtLoginSetting = State(
            initialValue: LaunchAtLoginSettingModel(
                backend: launchAtLoginBackend
            )
        )

        if let threadID = initialHoveredTokenThreadID,
           let rank = viewModel.snapshot.recentThreads.firstIndex(where: {
               $0.id == threadID
           }),
           let usage = viewModel.snapshot.recentThreads[rank].tokenUsage {
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
    }

    private var islandShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private func islandPopoverLayer(canvasSize: CGSize) -> some View {
        GeometryReader { _ in
            if let displayedPopover = activePopover ?? initialPopover {
                let pointer = displayedPopover.pointer
                    ?? defaultPopoverPointer(
                        for: displayedPopover.content,
                        canvasSize: canvasSize
                    )
                let placement = islandPopoverPlacement(
                    pointer: pointer,
                    popoverSize: displayedPopover.content.size(
                        for: interfaceLanguage
                    ),
                    canvasSize: canvasSize,
                    displayScale: displayScale
                )

                popoverView(for: displayedPopover.content)
                    .id(displayedPopover.content.identity)
                    .scaleEffect(placement.scale)
                    .position(placement.center)
            }
        }
        .allowsHitTesting(false)
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
        case .reset(let summary):
            ResetExpirationPopover(summary: summary)
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
        case .reset:
            return islandDefaultResetPopoverPointer(
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

            Text(compactTodayTokenText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
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
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
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
                    launchAtLoginState: launchAtLoginSetting.state,
                    launchAtLoginEnabled: launchAtLoginBinding,
                    languagePreference: languagePreferenceBinding,
                    displaySelection: displaySelection,
                    previewDisplayPickerPresentation: previewDisplayPickerPresentation,
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
        .padding(.bottom, 7)
        .animation(
            usesTimelineUpdates ? .easeOut(duration: 0.18) : nil,
            value: isIslandSettingsPresented
        )
    }

    private var dashboardContent: some View {
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

    private var expandedHeader: some View {
        ZStack(alignment: .trailing) {
            topHeader
                .contentShape(Rectangle())
                .onTapGesture {
                    CodexLauncher.openCodex()
                }

            HStack(spacing: IslandLayout.headerActionSpacing) {
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

    private var languagePreferenceBinding: Binding<IslandLanguagePreference> {
        Binding(
            get: { selectedLanguagePreference },
            set: { storedLanguagePreference = $0.rawValue }
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
                            ? Color.cyan.opacity(0.12)
                            : Color.white.opacity(
                                isIslandSettingsButtonHovered ? 0.075 : 0
                            )
                    )
                    .frame(width: 18, height: 18)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(
                        isIslandSettingsPresented
                            ? Color.cyan.opacity(0.88)
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
                    .frame(width: 18, height: 18)

                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
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
                    .frame(width: 18, height: 18)

                Image(systemName: "power")
                    .font(.system(size: 9.5, weight: .semibold))
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
                headerIdentity(showsLifetimeToken: sideWidth >= 132)
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
        HStack(spacing: 8) {
            PulsingStatusDot(
                color: sessionActivityColor,
                size: 7,
                isPulsing: viewModel.snapshot.hasRunningSession,
                shadowRadius: 4
            )

            headerTokenMetric(
                value: compactTodayTokenText,
                label: interfaceLanguage.text("今日 TOKEN", "TODAY TOKEN")
            )

            if showsLifetimeToken {
                PixelVerticalDivider(height: 17, opacity: 0.12)
                headerTokenMetric(
                    value: headerLifetimeTokenText,
                    label: interfaceLanguage.text("累计 TOKEN", "TOTAL TOKEN")
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(expandedHeaderAccessibilityLabel)
    }

    private func headerTokenMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.cyan.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(label)
                .font(.system(size: 5.5, weight: .bold, design: .rounded))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(width: 43, alignment: .leading)
    }

    @ViewBuilder
    private var metrics: some View {
        GeometryReader { proxy in
            let columnWidth = max(0, proxy.size.width / 2)
            let pixelScale = max(1, displayScale)
            let dividerWidth = 1 / pixelScale
            let dividerOrigin = (columnWidth * pixelScale).rounded() / pixelScale

            ZStack {
                HStack(spacing: 0) {
                    AccountActivityCard(
                        identity: viewModel.snapshot.profileIdentity,
                        usage: viewModel.snapshot.usage,
                        planLabel: CodexDisplayPolicy.planBadgeLabel(
                            accountPlanType: viewModel.snapshot.account.planType,
                            rateLimitPlanType: viewModel.snapshot.rateLimit?.planType
                        )
                    )
                    .frame(width: columnWidth, height: proxy.size.height)
                    .clipped()

                    QuotaMetric(
                        title: windowLabel(
                            viewModel.snapshot.rateLimit?.primary,
                            fallback: interfaceLanguage.text(
                                "主额度",
                                "Primary limit"
                            ),
                            language: interfaceLanguage
                        ),
                        window: viewModel.snapshot.rateLimit?.primary,
                        resetSummary: viewModel.snapshot.resetCredits,
                        onResetHoverChange: { hovering, pointer in
                            updateResetHover(hovering: hovering, pointer: pointer)
                        }
                    )
                    .frame(width: columnWidth, height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: dividerOrigin)
                    MetricDivider(width: dividerWidth)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private var recentConversations: some View {
        let threads = Array(
            viewModel.snapshot.recentThreads.prefix(CodexDisplayPolicy.recentThreadLimit)
        )
        let activityBucketCount = CodexUsageTimeline.lastCompletedDays(
            from: viewModel.snapshot.usage.dailyUsageBuckets
        ).count
        if threads.isEmpty {
            GeometryReader { proxy in
                let indicatorOffset = activityIndicatorOffset(
                    rowWidth: proxy.size.width,
                    bucketCount: activityBucketCount
                )
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(width: IslandLayout.activityIndicatorSlotWidth)
                        .offset(x: indicatorOffset)
                    Text(
                        interfaceLanguage.text(
                            "尚未读取到本地会话",
                            "No local sessions found"
                        )
                    )
                        .font(.system(size: 8.8, weight: .medium, design: .rounded))
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
        return compactTokenCount(tokens)
    }

    private var headerLifetimeTokenText: String {
        viewModel.snapshot.usage.lifetimeTokens.map(compactTokenCount) ?? "--"
    }

    private var expandedHeaderAccessibilityLabel: String {
        let lifetime: String
        if let tokens = viewModel.snapshot.usage.lifetimeTokens {
            lifetime = interfaceLanguage.text(
                "累计 Token \(exactTokenCount(tokens))",
                "Total tokens \(exactTokenCount(tokens))"
            )
        } else {
            lifetime = interfaceLanguage.text(
                "累计 Token 尚未同步",
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
                "\(state)，今日会话 Token 用量暂不可用",
                "\(state). Today's session token usage is unavailable"
            )
        }
        let exactTokens = NumberFormatter.localizedString(
            from: NSNumber(value: tokens),
            number: .decimal
        )
        return interfaceLanguage.text(
            "\(state)，今日会话 Token 用量 \(exactTokens)",
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
        guard let remaining = compactQuotaWindow?.remainingPercent else {
            return .white.opacity(0.28)
        }
        if remaining < 10 { return .red }
        if remaining < 20 { return .orange }
        return .cyan
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
    private static let fontSize: CGFloat = 6.5
    private static let horizontalPadding: CGFloat = 5
    private static let height: CGFloat = 14

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
    let launchAtLoginState: LaunchAtLoginPresentationState
    @Binding var launchAtLoginEnabled: Bool
    @Binding var languagePreference: IslandLanguagePreference
    @ObservedObject var displaySelection: IslandDisplaySelectionModel
    let previewDisplayPickerPresentation: Bool?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isRefreshHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(language.text("灵动岛设置", "Island settings"))
                    .font(.system(size: 9.6, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 8)

                Text(
                    language.text(
                        "偏好设置会自动保存",
                        "Preferences are saved automatically"
                    )
                )
                    .font(.system(size: 6.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.26))
            }
            .frame(height: 14)

            HStack(spacing: 8) {
                IslandSettingToggleCard(
                    icon: "dot.radiowaves.left.and.right",
                    title: language.text("状态动效", "Status animation"),
                    detail: language.text(
                        "运行会话的呼吸提示",
                        "Pulse while sessions run"
                    ),
                    tint: .green,
                    isOn: $statusAnimationsEnabled
                )

                IslandSettingToggleCard(
                    icon: "sparkles",
                    title: language.text("TOKEN 消耗动效", "Token animation"),
                    detail: language.text(
                        "消耗时播放刘海粒子",
                        "Particles while tokens are used"
                    ),
                    tint: .cyan,
                    isOn: $tokenConsumptionEffectEnabled
                )

                IslandSettingToggleCard(
                    icon: "power",
                    title: language.text("开机启动", "Launch at login"),
                    detail: launchAtLoginDetailText,
                    tint: .purple,
                    isOn: $launchAtLoginEnabled
                )
            }
            .frame(height: 58)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.cyan.opacity(0.08))

                    Image(systemName: "globe")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.cyan.opacity(0.72))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(language.text("语言", "Language"))
                        .font(.system(size: 8.6, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(languageDetailText)
                        .font(.system(size: 6.4, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                IslandLanguagePicker(selection: $languagePreference)

                PixelVerticalDivider(height: 18, opacity: 0.08)

                IslandDisplayPicker(
                    selection: displaySelection,
                    previewPresentation: previewDisplayPickerPresentation
                )

                PixelVerticalDivider(height: 18, opacity: 0.08)

                Button(action: onRefresh) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 7, weight: .semibold))

                        Text(
                            isRefreshing
                                ? language.text("同步中", "Syncing")
                                : language.text("同步", "Sync")
                        )
                            .font(.system(size: 7, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(
                        Color.cyan.opacity(isRefreshing ? 0.40 : 0.82)
                    )
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    Color.cyan.opacity(
                                        isRefreshHovered && !isRefreshing ? 0.13 : 0.075
                                    )
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    Color.cyan.opacity(0.12),
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
            .frame(height: 46)
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
                "自动跟随 macOS · 当前中文",
                "Following macOS · English"
            )
        }
        return language.text("手动选择界面语言", "Manually selected")
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
        .frame(width: 104, height: 20)
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
                .font(.system(size: 7.2, weight: .semibold))

            Text(selectedLabel)
                .font(.system(size: 6.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 1)

            Image(systemName: isMenuPresented ? "chevron.up" : "chevron.down")
                .font(.system(size: 5.2, weight: .bold))
                .opacity(0.58)
        }
        .foregroundStyle(
            Color.cyan.opacity(isHovered || isMenuPresented ? 0.90 : 0.72)
        )
        .padding(.horizontal, 7)
        .frame(width: 104, height: 20)
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
                            .font(.system(size: 6.4, weight: .semibold))
                            .foregroundStyle(
                                choice.target == selection.preference
                                    ? Color.cyan.opacity(0.86)
                                    : Color.white.opacity(0.18)
                            )
                            .frame(width: 8)

                        Text(optionLabel(for: choice))
                            .font(.system(size: 6.6, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                choice.isAvailable
                                    ? Color.white.opacity(0.72)
                                    : Color.white.opacity(0.28)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 142, height: 17)
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
            return language.text("自动选屏", "Auto display")
        }
        if selected.target == .automatic {
            return language.text("自动选屏", "Auto display")
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
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint.opacity(isOn ? 0.12 : 0.055))

                        Image(systemName: icon)
                            .font(.system(size: 7.4, weight: .semibold))
                            .foregroundStyle(tint.opacity(isOn ? 0.82 : 0.38))
                    }
                    .frame(width: 20, height: 20)

                    Text(title)
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text(detail)
                    .font(.system(size: 6.1, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.27))
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }

            Spacer(minLength: 4)

            Toggle(isOn: $isOn) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(IslandToggleStyle(tint: tint))
            .frame(width: 24, height: 13)
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(2)
            .accessibilityLabel(Text(title))
        }
        .disabled(!isInteractive)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct IslandLanguagePicker: View {
    @Binding var selection: IslandLanguagePreference

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        HStack(spacing: 1) {
            ForEach(IslandLanguagePreference.allCases) { preference in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        selection = preference
                    }
                } label: {
                    Text(optionLabel(for: preference))
                        .font(.system(size: 6.6, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            preference == selection
                                ? Color.cyan.opacity(0.90)
                                : Color.white.opacity(0.34)
                        )
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    preference == selection
                                        ? Color.cyan.opacity(0.11)
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
                .frame(width: 9, height: 9)
                .offset(x: configuration.isOn ? 5.2 : -5.2)
                .shadow(color: .black.opacity(0.24), radius: 1, y: 0.5)
        }
        .frame(width: 24, height: 13)
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
    let onTokenHover: (Bool, CGPoint?) -> Void
    let onOpen: () -> Void
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            let leadingHalfWidth = proxy.size.width / 2
            let titleColumnWidth = max(
                0,
                leadingHalfWidth - IslandLayout.threadSourceColumnWidth
            )
            let trailingColumnWidth = proxy.size.width - leadingHalfWidth
            let configurationDensity = ThreadConfigurationDensity(
                availableRowWidth: proxy.size.width
            )
            let indicatorOffset = activityIndicatorOffset(
                rowWidth: proxy.size.width,
                bucketCount: activityBucketCount
            )

            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ThreadActivityIndicator(state: thread.executionState)
                        .frame(width: IslandLayout.activityIndicatorSlotWidth)
                        .offset(x: indicatorOffset)

                    Text(thread.title)
                        .font(.system(size: 8.8, weight: .medium, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                .padding(.trailing, 8)
                .frame(
                    width: titleColumnWidth,
                    height: proxy.size.height,
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
                        density: configurationDensity
                    )

                    ThreadTokenUsageView(
                        usage: thread.tokenUsage,
                        onHoverChange: onTokenHover
                    )

                    Spacer(minLength: 0)

                    Text(trailingLabel)
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .foregroundStyle(trailingColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(
                            width: IslandLayout.threadStatusColumnWidth,
                            alignment: .trailing
                        )
                        .help(executionStateHelp)
                }
                .padding(.leading, IslandLayout.metricCenterGutter)
                .frame(
                    width: trailingColumnWidth,
                    height: proxy.size.height,
                    alignment: .trailing
                )
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
        case .interrupted: return .orange.opacity(0.62)
        case .failed: return .red.opacity(0.66)
        case .idle, .unknown: return .white.opacity(rank == 0 ? 0.60 : 0.48)
        }
    }

    private var trailingLabel: String {
        switch thread.executionState {
        case .running: return language.text("执行中", "Running")
        case .interrupted: return language.text("已中断", "Interrupted")
        case .failed: return language.text("失败", "Failed")
        case .idle, .unknown:
            return conversationUpdatedLabel(thread.updatedAt, language: language)
        }
    }

    private var trailingColor: Color {
        switch thread.executionState {
        case .running: return .green.opacity(0.72)
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
            .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
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

    var body: some View {
        Canvas { context, size in
            let cyan = Color(red: 0.02, green: 0.78, blue: 0.95)
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
                    with: .color(cyan.opacity(opacity)),
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
                    with: .color(cyan.opacity(opacity * 0.90))
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
        case .idle: return .white.opacity(0.20)
        case .interrupted: return .orange.opacity(0.72)
        case .failed: return .red.opacity(0.76)
        case .unknown: return .clear
        }
    }

    private var indicatorSize: CGFloat {
        switch state {
        case .running: return 5.5
        case .idle, .interrupted, .failed: return 4.5
        case .unknown: return 5
        }
    }

    private var helpText: String {
        switch state {
        case .running: return language.text("执行中", "Running")
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

    var width: CGFloat {
        switch self {
        case .full: return 143
        case .compact: return 83
        case .minimal: return 43
        }
    }
}

private struct ThreadConfigurationView: View {
    let thread: ThreadSummary
    let density: ThreadConfigurationDensity
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        HStack(spacing: 3) {
            if density.showsModel {
                modelSlot
            }

            if density.showsReasoning {
                reasoningSlot
            }

            fastSlot
        }
        .frame(width: density.width, alignment: .leading)
        .help(configurationHelp)
    }

    @ViewBuilder
    private var modelSlot: some View {
        if let model = thread.model {
            Text(displayModelName(model))
                .font(.system(size: 7.8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 57, alignment: .leading)
        } else {
            Color.clear.frame(width: 57, height: 1)
        }
    }

    @ViewBuilder
    private var reasoningSlot: some View {
        if let effort = thread.reasoningEffort {
            let isUltra = effort.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "ultra"
            ThreadSettingBadge(
                text: effort.uppercased(),
                color: isUltra
                    ? Color(red: 0.72, green: 0.43, blue: 1.0).opacity(0.94)
                    : .white.opacity(0.42)
            )
            .frame(width: 37, alignment: .leading)
        } else {
            Color.clear.frame(width: 37, height: 1)
        }
    }

    @ViewBuilder
    private var fastSlot: some View {
        if let tier = thread.serviceTier {
            let normalizedTier = tier.lowercased()
            let isFast = normalizedTier == "priority" || normalizedTier == "fast"
            let isInferred = thread.serviceTierSource == .effectiveConfig
            ThreadSettingBadge(
                text: isFast ? "FAST ON" : "FAST OFF",
                color: isFast
                    ? .cyan.opacity(isInferred ? 0.58 : 0.90)
                    : .white.opacity(isInferred ? 0.24 : 0.30)
            )
            .frame(width: 43, alignment: .leading)
        } else {
            ThreadSettingBadge(
                text: "FAST ?",
                color: .white.opacity(0.24)
            )
            .frame(width: 43, alignment: .leading)
        }
    }

    private var configurationHelp: String {
        let model = thread.model.map(displayModelName)
            ?? language.text("模型未知", "Model unknown")
        let reasoning = thread.reasoningEffort?.uppercased()
            ?? language.text("推理强度未知", "Reasoning effort unknown")
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
        return language.text(
            "\(model)，\(reasoning)，\(fast)\(source)",
            "\(model), \(reasoning), \(fast)\(source)"
        )
    }
}

private struct ThreadTokenUsageView: View {
    let usage: ThreadTokenUsage?
    let onHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var isPointerInside = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let usage {
                    Text(compactTokenCount(usage.totalTokens))
                        .font(.system(size: 7.2, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.31))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
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
        .frame(width: 34, height: 14)
    }
}

private struct TokenUsageDetailPopover: View {
    static let width: CGFloat = 205
    static let height: CGFloat = 46
    static let size = CGSize(width: width, height: height)

    let usage: ThreadTokenUsage
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(language.text("累计 TOKEN", "TOTAL TOKEN"))
                    .font(.system(size: 6.8, weight: .bold, design: .rounded))
                    .tracking(0.25)
                    .foregroundStyle(.white.opacity(0.38))

                Spacer(minLength: 4)

                Text(exactTokenCount(usage.totalTokens))
                    .font(.system(size: 7.8, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.cyan.opacity(0.88))
            }

            HStack(spacing: 7) {
                detail(language.text("输入", "Input"), usage.inputTokens)
                divider
                detail(
                    language.text("其中缓存", "Cached"),
                    usage.cachedInputTokens
                )
            }

            HStack(spacing: 7) {
                detail(language.text("输出", "Output"), usage.outputTokens)
                divider
                detail(
                    language.text("其中推理", "Reasoning"),
                    usage.reasoningOutputTokens,
                    color: Color(red: 0.72, green: 0.43, blue: 1.0).opacity(0.82)
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: Self.width, height: Self.height)
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

    private func detail(
        _ label: String,
        _ value: Int64,
        color: Color = .white.opacity(0.68)
    ) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 6.6, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.32))

            Spacer(minLength: 3)

            Text(exactTokenCount(value))
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 1, height: 8)
    }
}

private struct ThreadSettingBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(color.opacity(0.11))
            )
    }
}

private struct AccountActivityCard: View {
    let identity: ProfileIdentitySummary
    let usage: UsageSummary
    let planLabel: String?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language
    @State private var hoveredBucket: DailyUsageBucket?
    @State private var avatarImage: NSImage?

    init(
        identity: ProfileIdentitySummary,
        usage: UsageSummary,
        planLabel: String?
    ) {
        self.identity = identity
        self.usage = usage
        self.planLabel = planLabel
        _avatarImage = State(initialValue: identity.avatarData.flatMap(NSImage.init(data:)))
    }

    private var recentUsage: [DailyUsageBucket] {
        CodexUsageTimeline.lastCompletedDays(from: usage.dailyUsageBuckets)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 7) {
                profileAvatar

                HStack(alignment: .center, spacing: 5) {
                    Text(displayName)
                        .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if let planLabel {
                        Text(compactPlanBadgeLabel(planLabel))
                            .font(.system(size: 6.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.cyan.opacity(0.88))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.cyan.opacity(0.09))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        Color.cyan.opacity(0.14),
                                        lineWidth: 1 / max(1, displayScale)
                                    )
                            )
                            .fixedSize(horizontal: true, vertical: true)
                            .layoutPriority(2)
                            .help(planLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 28)

            Text(activitySubtitle)
                .font(.system(size: 6.8, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(activitySubtitleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 1)
                .frame(height: 15, alignment: .bottom)

            DailyTokenActivityChart(
                buckets: recentUsage,
                hoveredBucket: hoveredBucket,
                onHover: updateHoveredBucket
            )
            .frame(height: 28)
        }
        .padding(.leading, IslandLayout.contentHorizontalInset)
        .padding(.trailing, IslandLayout.metricCenterGutter)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: identity.avatarData) { data in
            avatarImage = data.flatMap(NSImage.init(data:))
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let image = avatarImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(avatarBorder)
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.58), Color.blue.opacity(0.36)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(displayInitial)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 26, height: 26)
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

    private var activitySubtitle: String {
        if let hoveredBucket {
            return "\(shortUsageDate(hoveredBucket.startDate, language: language)) · \(compactTokenCount(hoveredBucket.tokens)) Token"
        }
        if usage.lifetimeTokens == nil && usage.dailyUsageBuckets.isEmpty {
            return language.text(
                "账户统计同步中",
                "Account statistics are syncing"
            )
        }
        if usage.dailyUsageBuckets.isEmpty {
            return language.text(
                "近30天暂无 Token 使用",
                "No token usage in the last 30 days"
            )
        }
        return language.text(
            "近30天每日 Token",
            "Daily tokens · last 30 days"
        )
    }

    private var activitySubtitleColor: Color {
        hoveredBucket == nil ? .white.opacity(0.30) : .cyan.opacity(0.62)
    }

    private func updateHoveredBucket(_ bucket: DailyUsageBucket?, hovering: Bool) {
        if hovering {
            hoveredBucket = bucket
        } else if hoveredBucket?.id == bucket?.id {
            hoveredBucket = nil
        }
    }
}

private struct DailyTokenActivityChart: View {
    let buckets: [DailyUsageBucket]
    let hoveredBucket: DailyUsageBucket?
    let onHover: (DailyUsageBucket?, Bool) -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(1, buckets.map(\.tokens).max() ?? 0)

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.045))
                    .frame(height: 1 / max(1, displayScale))

                HStack(
                    alignment: .bottom,
                    spacing: IslandLayout.activityChartBarSpacing
                ) {
                    ForEach(buckets) { bucket in
                        let intensity = sqrt(
                            Double(max(0, bucket.tokens)) / Double(maximum)
                        )
                        let barHeight = bucket.tokens == 0
                            ? 1
                            : max(2, proxy.size.height * CGFloat(intensity))
                        let isHovered = hoveredBucket?.id == bucket.id

                        ZStack(alignment: .bottom) {
                            Color.clear

                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(barColor(intensity: intensity, isHovered: isHovered))
                                .frame(height: barHeight)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            onHover(bucket, hovering)
                        }
                        .help(
                            "\(shortUsageDate(bucket.startDate, language: language)): \(exactTokenCount(bucket.tokens)) Token"
                        )
                    }
                }
            }
        }
    }

    private func barColor(intensity: Double, isHovered: Bool) -> Color {
        guard intensity > 0 else { return .white.opacity(0.075) }
        if isHovered { return .cyan.opacity(0.98) }
        return .cyan.opacity(0.22 + 0.68 * intensity)
    }
}

private struct QuotaMetric: View {
    let title: String
    let window: RateLimitWindow?
    let resetSummary: ResetCreditSummary?
    let onResetHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.32))

                if let resetTimestamp {
                    Text(
                        language.text(
                            "（\(resetTimestamp)重置）",
                            "(resets \(resetTimestamp))"
                        )
                    )
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.76)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(remainingText)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: true, vertical: true)

                if let resetSummary {
                    ResetSummaryLine(
                        summary: resetSummary,
                        onHoverChange: onResetHoverChange
                    )
                    .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(remainingBarColor.opacity(0.9))
                        .frame(width: proxy.size.width * remainingFraction)
                }
            }
            .frame(height: 5)
        }
        .padding(.leading, IslandLayout.metricCenterGutter)
        .padding(.trailing, IslandLayout.contentHorizontalInset)
        .padding(.vertical, 2)
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
        guard let remaining = window?.remainingPercent else {
            return .white.opacity(0.18)
        }
        return remaining <= 10 ? .red : .green
    }

    private var resetTimestamp: String? {
        guard let date = window?.resetsAt else { return nil }
        return quotaResetDateText(date, language: language)
    }
}

private struct ResetSummaryLine: View {
    let summary: ResetCreditSummary
    let onHoverChange: (Bool, CGPoint?) -> Void
    @Environment(\.islandInterfaceLanguage) private var language

    var body: some View {
        summaryContent
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
            .frame(height: 10, alignment: .leading)
    }

    private var summaryContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(language.text("（", "("))
                .font(.system(size: 7.2, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))

            if summary.availableCount <= 0 {
                Text(language.text("暂无可用重置", "No resets available"))
                    .font(.system(size: 7.2, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.30))
            } else {
                Text(String(summary.availableCount))
                    .font(.system(size: 7.8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.green.opacity(0.82))

                Text(
                    language.text(
                        "次可用重置，最近一次将于",
                        " resets available, next expires "
                    )
                )
                    .font(.system(size: 7.2, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))

                if let date = summary.earliestExpiration {
                    Text(resetExpirationDateText(date, language: language))
                        .font(.system(size: 7.2, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.red.opacity(0.78))

                    Text(language.text("到期", ""))
                        .font(.system(size: 7.2, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                } else {
                    Text(
                        language.text(
                            "到期时间未知",
                            "expiration unknown"
                        )
                    )
                        .font(.system(size: 7.2, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }

            Text(language.text("）", ")"))
                .font(.system(size: 7.2, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.76)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 10, alignment: .leading)
    }
}

private struct ResetExpirationPopover: View {
    let summary: ResetCreditSummary
    @Environment(\.displayScale) private var displayScale
    @Environment(\.islandInterfaceLanguage) private var language

    static func size(
        for summary: ResetCreditSummary,
        language: IslandInterfaceLanguage
    ) -> CGSize {
        let dateCount = summary.expirationDates.count
        let missingDateCount = max(0, summary.availableCount - dateCount)
        let height: CGFloat
        if dateCount == 0 {
            height = 35
        } else {
            height = 24 + CGFloat(dateCount) * 11
                + (missingDateCount > 0 ? 13 : 0)
        }
        return CGSize(width: width(for: language), height: height)
    }

    static func width(for language: IslandInterfaceLanguage) -> CGFloat {
        language == .chinese ? 84 : 80
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
                .font(.system(size: 7.2, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .padding(.leading, language == .chinese ? 3 : 0)
                .frame(height: 9, alignment: .leading)

            if expirationDates.isEmpty {
                Text(
                    language.text(
                        "服务暂未返回具体日期",
                        "Dates unavailable"
                    )
                )
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .frame(height: 9, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(expirationDates.enumerated()), id: \.offset) { index, date in
                        HStack(spacing: 3) {
                            Text(String(index + 1))
                                .font(.system(size: 6.2, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: 9, height: 9)
                                .background(
                                    Circle().fill(Color.cyan.opacity(0.12))
                                )

                            Text(
                                resetExpirationDateText(
                                    date,
                                    language: language
                                )
                            )
                                .font(.system(size: 6.6, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(
                                    index == 0
                                        ? Color.red.opacity(0.78)
                                        : Color.white.opacity(0.52)
                                )
                                .lineLimit(1)
                                .frame(width: 31, alignment: .leading)

                            Text(resetExpirationTimeText(date))
                                .font(.system(size: 6.6, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(
                                    index == 0
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
                        .frame(height: 9)
                    }
                }
            }

            if !expirationDates.isEmpty, missingDateCount > 0 {
                Text(missingDateText)
                    .font(.system(size: 6.3, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(height: 8, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
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
            .frame(width: width, height: 52)
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
    let slug = rawValue.split(separator: "/").last.map(String.init) ?? rawValue
    return slug
        .split(separator: "-", omittingEmptySubsequences: false)
        .map { part -> String in
            let value = String(part)
            let lowercased = value.lowercased()
            if lowercased == "gpt" { return "GPT" }
            if lowercased == "sol" { return "Sol" }
            if lowercased.first == "o", lowercased.dropFirst().first?.isNumber == true {
                return lowercased.uppercased()
            }
            guard let first = lowercased.first else { return value }
            if first.isNumber { return value }
            return first.uppercased() + lowercased.dropFirst()
        }
        .joined(separator: "-")
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

private func tokenUsageHelp(
    _ usage: ThreadTokenUsage,
    language: IslandInterfaceLanguage
) -> String {
    language.text(
        """
        累计 Token：\(exactTokenCount(usage.totalTokens))
        输入：\(exactTokenCount(usage.inputTokens))（其中缓存：\(exactTokenCount(usage.cachedInputTokens))）
        输出：\(exactTokenCount(usage.outputTokens))（其中推理：\(exactTokenCount(usage.reasoningOutputTokens))）
        """,
        """
        Total tokens: \(exactTokenCount(usage.totalTokens))
        Input: \(exactTokenCount(usage.inputTokens)) (cached: \(exactTokenCount(usage.cachedInputTokens)))
        Output: \(exactTokenCount(usage.outputTokens)) (reasoning: \(exactTokenCount(usage.reasoningOutputTokens)))
        """
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
