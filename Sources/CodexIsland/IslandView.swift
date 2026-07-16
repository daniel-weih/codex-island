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
    static let compactTokenEffectWidth: CGFloat = 9.5
    static let recentConversationsHeight = conversationRowHeight
        * CGFloat(CodexDisplayPolicy.recentThreadLimit)
    static let expandedBodyHeight: CGFloat = 84 + recentConversationsHeight

    static func compactWidth(forNotchWidth notchWidth: CGFloat) -> CGFloat {
        max(compactMinimumWidth, notchWidth + compactExtraWidth)
    }

    static func compactHeight(forSafeTopInset safeTopInset: CGFloat) -> CGFloat {
        safeTopInset > 0 ? safeTopInset : compactFallbackHeight
    }

    static func expandedHeaderHeight(forSafeTopInset safeTopInset: CGFloat) -> CGFloat {
        safeTopInset > 0 ? safeTopInset : compactFallbackHeight
    }
}

private enum IslandCoordinateSpace {
    static let name = "codex-island"
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

private extension EnvironmentValues {
    var islandStatusAnimationsEnabled: Bool {
        get { self[IslandStatusAnimationsEnabledKey.self] }
        set { self[IslandStatusAnimationsEnabledKey.self] = newValue }
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

    var size: CGSize {
        switch self {
        case .token: return TokenUsageDetailPopover.size
        case .reset(let summary): return ResetExpirationPopover.size(for: summary)
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

private func islandDefaultTokenPopoverPointer(rank: Int, canvasSize: CGSize) -> CGPoint {
    let rowsTop = canvasSize.height - 7 - IslandLayout.recentConversationsHeight
    return CGPoint(
        x: canvasSize.width - 80,
        y: rowsTop + (CGFloat(rank) + 0.5) * IslandLayout.conversationRowHeight
    )
}

private func islandDefaultResetPopoverPointer(
    safeTopInset: CGFloat,
    canvasSize: CGSize
) -> CGPoint {
    CGPoint(
        x: canvasSize.width / 2 + IslandLayout.metricCenterGutter,
        y: IslandLayout.expandedHeaderHeight(
            forSafeTopInset: safeTopInset
        ) + 63
    )
}

@MainActor
final class IslandDisplayGeometry: ObservableObject {
    @Published private(set) var hasNotch: Bool
    @Published private(set) var notchWidth: CGFloat
    @Published private(set) var safeTopInset: CGFloat

    init(
        hasNotch: Bool = false,
        notchWidth: CGFloat = 132,
        safeTopInset: CGFloat = 0
    ) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.safeTopInset = safeTopInset
    }

    func update(
        hasNotch: Bool,
        notchWidth: CGFloat,
        safeTopInset: CGFloat
    ) {
        guard self.hasNotch != hasNotch
                || self.notchWidth != notchWidth
                || self.safeTopInset != safeTopInset else { return }
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.safeTopInset = safeTopInset
    }

}

struct IslandView: View {
    @ObservedObject var viewModel: CodexStatusViewModel
    @ObservedObject var displayGeometry: IslandDisplayGeometry
    @Environment(\.displayScale) private var displayScale
    @State private var activePopover: IslandPopoverPresentation?
    @State private var isSettingsButtonHovered = false
    private let initialPopover: IslandPopoverPresentation?
    private let initialTokenConsumptionPhase: Double?
    private let usesTimelineUpdates: Bool

    init(
        viewModel: CodexStatusViewModel,
        displayGeometry: IslandDisplayGeometry,
        initialHoveredTokenThreadID: String? = nil,
        initialResetSummaryHover: Bool = false,
        initialTokenConsumptionPhase: Double? = nil,
        usesTimelineUpdates: Bool = true
    ) {
        self.viewModel = viewModel
        self.displayGeometry = displayGeometry
        self.initialTokenConsumptionPhase = initialTokenConsumptionPhase
        self.usesTimelineUpdates = usesTimelineUpdates

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
                } else {
                    compactContent
                        .transition(
                            usesTimelineUpdates
                                ? .opacity.animation(.easeOut(duration: 0.08))
                                : .identity
                        )
                }
            }
            .environment(\.islandStatusAnimationsEnabled, usesTimelineUpdates)
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
                    popoverSize: displayedPopover.content.size,
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
                safeTopInset: displayGeometry.safeTopInset,
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
        .accessibilityLabel("主额度剩余 \(compactQuotaText)")
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
            nonConversationRegion
                .frame(maxHeight: .infinity)

            recentConversations
                .frame(
                    height: IslandLayout.recentConversationsHeight,
                    alignment: .topLeading
                )
                .padding(.horizontal, IslandLayout.contentHorizontalInset)
        }
        .padding(.bottom, 7)
    }

    private var nonConversationRegion: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                topHeader
                    .frame(height: expandedHeaderHeight)

                Hairline()
                    .padding(.horizontal, IslandLayout.contentHorizontalInset)

                metrics
                    .frame(maxHeight: .infinity)

                Hairline()
                    .padding(.horizontal, IslandLayout.contentHorizontalInset)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                CodexLauncher.openCodex()
            }

            settingsButton
                .padding(.trailing, IslandLayout.contentHorizontalInset)
                .frame(height: expandedHeaderHeight)
        }
    }

    private var expandedHeaderHeight: CGFloat {
        IslandLayout.expandedHeaderHeight(
            forSafeTopInset: displayGeometry.safeTopInset
        )
    }

    private var settingsButton: some View {
        Button {
            CodexLauncher.openSettings()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isSettingsButtonHovered ? 0.075 : 0))
                    .frame(width: 18, height: 18)

                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        Color.white.opacity(isSettingsButtonHovered ? 0.72 : 0.38)
                    )
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isSettingsButtonHovered = hovering
            }
        }
        .help("打开 Codex 设置")
        .accessibilityLabel("打开 Codex 设置")
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

            headerTokenMetric(value: compactTodayTokenText, label: "今日 TOKEN")

            if showsLifetimeToken {
                PixelVerticalDivider(height: 17, opacity: 0.12)
                headerTokenMetric(value: headerLifetimeTokenText, label: "累计 TOKEN")
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
                            fallback: "主额度"
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
                    Text("尚未读取到本地会话")
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
            lifetime = "累计 Token \(exactTokenCount(tokens))"
        } else {
            lifetime = "累计 Token 尚未同步"
        }
        return "\(compactActivityAccessibilityLabel)，\(lifetime)"
    }

    private var compactActivityAccessibilityLabel: String {
        let state = viewModel.snapshot.hasRunningSession
            ? "有会话正在运行"
            : "当前没有运行中的会话"
        guard let tokens = viewModel.snapshot.todayThreadTokens else {
            return "\(state)，今日会话 Token 用量暂不可用"
        }
        let exactTokens = NumberFormatter.localizedString(
            from: NSNumber(value: tokens),
            number: .decimal
        )
        return "\(state)，今日会话 Token 用量 \(exactTokens)"
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

private struct ConversationRow: View {
    let thread: ThreadSummary
    let rank: Int
    let activityBucketCount: Int
    let onTokenHover: (Bool, CGPoint?) -> Void
    let onOpen: () -> Void
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

                    Spacer(minLength: 2)

                    Text(trailingLabel)
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .foregroundStyle(trailingColor)
                        .fixedSize(horizontal: true, vertical: true)
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
        let source = thread.clientSource.map { "，来源 \($0.displayLabel)" } ?? ""
        return "在 Codex 中打开会话：\(thread.title)\(source)"
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
        case .running: return "执行中"
        case .interrupted: return "已中断"
        case .failed: return "失败"
        case .idle, .unknown: return conversationUpdatedLabel(thread.updatedAt)
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
        case .running: return "Codex 正在执行这条会话"
        case .idle: return "最近一轮任务已结束"
        case .interrupted: return "最近一轮任务已中断"
        case .failed: return "最近一轮任务执行失败"
        case .unknown: return "尚未读取到执行状态"
        }
    }
}

private struct ThreadSourceLabel: View {
    let source: ThreadClientSource?

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
        case .tui: return "来源：Codex TUI"
        case .app: return "来源：Codex App"
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
    @Environment(\.islandStatusAnimationsEnabled) private var animationsEnabled
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
        case .running: return "执行中"
        case .idle: return "空闲"
        case .interrupted: return "已中断"
        case .failed: return "失败"
        case .unknown: return "状态未知"
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
        let model = thread.model.map(displayModelName) ?? "模型未知"
        let reasoning = thread.reasoningEffort?.uppercased() ?? "推理强度未知"
        let fast: String
        if let tier = thread.serviceTier?.lowercased() {
            fast = tier == "priority" || tier == "fast" ? "Fast 开启" : "Fast 关闭"
        } else {
            fast = "Fast 状态未知"
        }
        let source = thread.serviceTierSource == .effectiveConfig
            ? "，Fast 按当前配置推断"
            : ""
        return "\(model)，\(reasoning)，\(fast)\(source)"
    }
}

private struct ThreadTokenUsageView: View {
    let usage: ThreadTokenUsage?
    let onHoverChange: (Bool, CGPoint?) -> Void
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
                        .accessibilityLabel(tokenUsageHelp(usage))
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

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("累计 TOKEN")
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
                detail("输入", usage.inputTokens)
                divider
                detail("其中缓存", usage.cachedInputTokens)
            }

            HStack(spacing: 7) {
                detail("输出", usage.outputTokens)
                divider
                detail(
                    "其中推理",
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
        .accessibilityLabel(tokenUsageHelp(usage))
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
        return "Codex 用户"
    }

    private var displayInitial: String {
        displayName.first.map(String.init)?.uppercased() ?? "C"
    }

    private var activitySubtitle: String {
        if let hoveredBucket {
            return "\(shortUsageDate(hoveredBucket.startDate)) · \(compactTokenCount(hoveredBucket.tokens)) Token"
        }
        if usage.lifetimeTokens == nil && usage.dailyUsageBuckets.isEmpty {
            return "账户统计同步中"
        }
        if usage.dailyUsageBuckets.isEmpty {
            return "近30天暂无 Token 使用"
        }
        return "近30天每日 Token"
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
                        .help("\(shortUsageDate(bucket.startDate))：\(exactTokenCount(bucket.tokens)) Token")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.32))

                if let resetTimestamp {
                    Text("（\(resetTimestamp)重置）")
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
        return DateFormatter.codexIslandQuotaReset.string(from: date)
    }
}

private struct ResetSummaryLine: View {
    let summary: ResetCreditSummary
    let onHoverChange: (Bool, CGPoint?) -> Void

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
            Text("（")
                .font(.system(size: 7.2, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))

            if summary.availableCount <= 0 {
                Text("暂无可用重置")
                    .font(.system(size: 7.2, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.30))
            } else {
                Text(String(summary.availableCount))
                    .font(.system(size: 7.8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.green.opacity(0.82))

                Text("次可用重置，最近一次将于")
                    .font(.system(size: 7.2, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))

                if let date = summary.earliestExpiration {
                    Text(DateFormatter.codexIslandResetExpiration.string(from: date))
                        .font(.system(size: 7.2, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.red.opacity(0.78))

                    Text("到期")
                        .font(.system(size: 7.2, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                } else {
                    Text("到期时间未知")
                        .font(.system(size: 7.2, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }

            Text("）")
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
    static let width: CGFloat = 84

    let summary: ResetCreditSummary
    @Environment(\.displayScale) private var displayScale

    static func size(for summary: ResetCreditSummary) -> CGSize {
        let dateCount = summary.expirationDates.count
        let missingDateCount = max(0, summary.availableCount - dateCount)
        let height: CGFloat
        if dateCount == 0 {
            height = 35
        } else {
            height = 24 + CGFloat(dateCount) * 11
                + (missingDateCount > 0 ? 13 : 0)
        }
        return CGSize(width: width, height: height)
    }

    private var expirationDates: [Date] {
        summary.expirationDates.sorted()
    }

    private var missingDateCount: Int {
        max(0, summary.availableCount - expirationDates.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("重置到期时间")
                .font(.system(size: 7.2, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .padding(.leading, 3)
                .frame(height: 9, alignment: .leading)

            if expirationDates.isEmpty {
                Text("服务暂未返回具体日期")
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

                            Text(DateFormatter.codexIslandResetExpiration.string(from: date))
                                .font(.system(size: 6.6, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(
                                    index == 0
                                        ? Color.red.opacity(0.78)
                                        : Color.white.opacity(0.52)
                                )
                                .lineLimit(1)
                                .frame(width: 31, alignment: .leading)

                            Text(DateFormatter.codexIslandResetExpirationTime.string(from: date))
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
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 9)
                    }
                }
            }

            if !expirationDates.isEmpty, missingDateCount > 0 {
                Text("另有 \(missingDateCount) 次未返回到期时间")
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
            width: Self.width,
            height: Self.size(for: summary).height,
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

private func windowLabel(_ window: RateLimitWindow?, fallback: String) -> String {
    guard let minutes = window?.windowDurationMinutes else { return fallback }
    if minutes == 7 * 24 * 60 { return "剩余用量" }
    if minutes < 60 { return "\(minutes) 分钟限额" }
    if minutes < 24 * 60, minutes % 60 == 0 { return "\(minutes / 60) 小时限额" }
    if minutes % (24 * 60) == 0 { return "\(minutes / (24 * 60)) 天限额" }
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

private func conversationUpdatedLabel(_ date: Date?) -> String {
    guard let date else { return "—" }
    if abs(Date().timeIntervalSince(date)) < 5 { return "刚刚" }
    return RelativeDateTimeFormatter.codexIsland.localizedString(
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

private func shortUsageDate(_ value: String) -> String {
    let parts = value.split(separator: "-")
    guard parts.count == 3,
          let month = Int(parts[1]),
          let day = Int(parts[2]) else {
        return value
    }
    return "\(month)月\(day)日"
}

private func tokenUsageHelp(_ usage: ThreadTokenUsage) -> String {
    """
    累计 Token：\(exactTokenCount(usage.totalTokens))
    输入：\(exactTokenCount(usage.inputTokens))（其中缓存：\(exactTokenCount(usage.cachedInputTokens))）
    输出：\(exactTokenCount(usage.outputTokens))（其中推理：\(exactTokenCount(usage.reasoningOutputTokens))）
    """
}

private func exactTokenCount(_ value: Int64) -> String {
    NumberFormatter.codexIslandTokenCount.string(from: NSNumber(value: max(0, value)))
        ?? String(max(0, value))
}

private extension RelativeDateTimeFormatter {
    static let codexIsland: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}

private extension DateFormatter {
    static let codexIslandQuotaReset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let codexIslandResetExpiration: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日"
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
