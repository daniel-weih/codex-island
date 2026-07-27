import AppKit
import QuartzCore
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // NSWindow normally pushes borderless panels below the menu bar's
        // visibleFrame. This panel intentionally occupies the camera/notch area.
        frameRect
    }
}

@MainActor
final class IslandPanelController: NSObject {
    private let compactSize = NSSize(
        width: IslandLayout.compactFallbackWidth,
        height: IslandLayout.compactFallbackHeight
    )
    // The controller adds either the physical notch height or the target
    // screen's measured menu-bar region. expandedBodyHeight excludes both.
    private let expandedSize = NSSize(
        width: IslandLayout.expandedWidth,
        height: IslandLayout.expandedBodyHeight
    )

    private let viewModel: CodexStatusViewModel
    private let displayGeometry = IslandDisplayGeometry()
    private let displaySelection: IslandDisplaySelectionModel
    private let panel: IslandPanel
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerIsInside = false
    private var targetScreen: NSScreen?
    private var screenObserver: NSObjectProtocol?

    init(viewModel: CodexStatusViewModel) {
        self.viewModel = viewModel
        displaySelection = IslandDisplaySelectionModel()
        panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel(panel)
        let hostingView = NSHostingView(
            rootView: IslandView(
                viewModel: viewModel,
                displayGeometry: displayGeometry,
                displaySelection: displaySelection
            )
        )
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        displaySelection.onPreferenceChange = { [weak self] in
            guard let self else { return }
            self.reposition(animated: false)
            self.evaluatePointerPosition()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.targetScreen = self.initialTargetScreen()
                self.displaySelection.refresh()
                if self.panel.isVisible {
                    self.reposition(animated: false)
                }
                self.evaluatePointerPosition()
            }
        }
    }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func start() {
        displaySelection.refresh()
        targetScreen = initialTargetScreen()
        reposition(animated: false)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        installPointerMonitoring()
        evaluatePointerPosition()
    }

    func stop() {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        panel.orderOut(nil)
    }

    private func installPointerMonitoring() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.evaluatePointerPosition() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.evaluatePointerPosition() }
            return event
        }
    }

    private func configurePanel(_ panel: IslandPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.tabbingMode = .disallowed
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        // Keep this assignment last. Setting isFloatingPanel afterwards resets
        // the effective Core Graphics layer to the ordinary floating level (3),
        // which lets the menu bar (24/25) cover the top of the expanded island.
        panel.level = NSWindow.Level(
            rawValue: NSWindow.Level.popUpMenu.rawValue + 1
        )
    }

    private func handleHover(_ hovering: Bool) {
        expandWorkItem?.cancel()
        expandWorkItem = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        if hovering {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, self.isPointerInsideInteractionRegion else { return }
                    self.setExpanded(true, animated: true)
                    self.viewModel.refreshIfStale()
                }
            }
            expandWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: workItem)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.isPointerInsideInteractionRegion else { return }
                self.setExpanded(false, animated: true)
            }
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
    }

    private func evaluatePointerPosition() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: {
            notchRect(on: $0)?.contains(mouse) == true
        }) {
            targetScreen = screen
        }

        let isInside = isPointerInsideInteractionRegion
        guard isInside != pointerIsInside else { return }
        pointerIsInside = isInside
        handleHover(isInside)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        if !panel.isVisible {
            reposition(animated: false)
            panel.orderFrontRegardless()
        }

        panel.ignoresMouseEvents = !expanded
        guard viewModel.isExpanded != expanded else { return }

        viewModel.isExpanded = expanded
        reposition(animated: animated)
    }

    private func reposition(animated: Bool) {
        guard let screen = preferredScreen() else { return }
        let notch = notchGeometry(on: screen)
        let topRegionHeight = topRegionHeight(on: screen, hasNotch: notch != nil)
        displayGeometry.update(
            hasNotch: notch != nil,
            notchWidth: notch?.width ?? compactSize.width,
            topRegionHeight: topRegionHeight
        )
        let size = size(for: screen, topRegionHeight: topRegionHeight)
        let frame = frame(for: size, on: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? 0
                    : (viewModel.isExpanded ? 0.28 : 0.20)
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.16,
                    1.00,
                    0.30,
                    1.00
                )
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func preferredScreen() -> NSScreen? {
        displaySelection.resolveScreen(
            automaticScreen: automaticPreferredScreen()
        )
    }

    private func automaticPreferredScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return targetScreen
            ?? NSScreen.screens.first(where: { notchRect(on: $0)?.contains(mouse) == true })
            ?? panel.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func initialTargetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: {
            $0.frame.contains(mouse) && notchGeometry(on: $0) != nil
        })
            ?? NSScreen.screens.first(where: { notchGeometry(on: $0) != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let notchGeometry = notchGeometry(on: screen)
        let anchorX = notchGeometry?.centerX ?? screen.frame.midX
        let top = panelTop(on: screen)
        let scale = screen.backingScaleFactor
        func aligned(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }
        let origin = NSPoint(
            x: aligned(anchorX - size.width / 2),
            y: aligned(top - size.height)
        )
        return NSRect(
            origin: origin,
            size: NSSize(width: aligned(size.width), height: aligned(size.height))
        )
    }

    private func size(for screen: NSScreen, topRegionHeight: CGFloat) -> NSSize {
        if viewModel.isExpanded {
            return NSSize(
                width: min(expandedSize.width, screen.visibleFrame.width - 24),
                height: expandedSize.height
                    + IslandLayout.expandedHeaderHeight(
                        forTopRegionHeight: topRegionHeight
                    )
            )
        }

        guard let notch = notchGeometry(on: screen) else {
            return NSSize(width: compactSize.width, height: topRegionHeight)
        }
        return NSSize(
            width: min(
                IslandLayout.compactWidth(forNotchWidth: notch.width),
                screen.visibleFrame.width - 24
            ),
            height: IslandLayout.compactHeight(
                forTopRegionHeight: topRegionHeight
            )
        )
    }

    private func topRegionHeight(on screen: NSScreen, hasNotch: Bool) -> CGFloat {
        if hasNotch {
            return IslandLayout.compactHeight(
                forTopRegionHeight: screen.safeAreaInsets.top
            )
        }

        // NSStatusBar.system.thickness describes status-item content, not the
        // full menu-bar reservation, and can differ substantially under display
        // scaling. visibleFrame gives the actual top edge available to windows.
        let measuredMenuBarHeight = max(
            0,
            screen.frame.maxY - screen.visibleFrame.maxY
        )
        let scale = max(1, screen.backingScaleFactor)
        let pixelAlignedHeight =
            (measuredMenuBarHeight * scale).rounded() / scale
        return IslandLayout.compactHeight(
            forTopRegionHeight: pixelAlignedHeight
        )
    }

    private func panelTop(on screen: NSScreen) -> CGFloat {
        screen.frame.maxY
    }

    private var isPointerInsideInteractionRegion: Bool {
        let mouse = NSEvent.mouseLocation
        let isInsideNotch = preferredScreen().flatMap(notchRect)?.contains(mouse) == true
        let isInsidePanel = panel.isVisible && panel.frame.contains(mouse)
        return isInsideNotch || isInsidePanel
    }

    private func notchRect(on screen: NSScreen) -> NSRect? {
        guard let notch = notchGeometry(on: screen) else { return nil }
        let top = screen.frame.maxY
        let bottom = top - screen.safeAreaInsets.top
        return NSRect(
            x: notch.centerX - notch.width / 2,
            y: bottom,
            width: notch.width,
            height: top - bottom
        )
    }

    private func notchGeometry(on screen: NSScreen) -> (centerX: CGFloat, width: CGFloat)? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let width = max(0, right.minX - left.maxX)
        guard width > 0 else { return nil }
        return ((left.maxX + right.minX) / 2, width)
    }
}
