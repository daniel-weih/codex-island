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
    // The controller adds either the physical notch height or the fallback
    // header height. expandedBodyHeight intentionally excludes both.
    private let expandedSize = NSSize(
        width: IslandLayout.expandedWidth,
        height: IslandLayout.expandedBodyHeight
    )

    private let viewModel: CodexStatusViewModel
    private let displayGeometry = IslandDisplayGeometry()
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
        panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel(panel)
        let hostingView = NSHostingView(
            rootView: IslandView(viewModel: viewModel, displayGeometry: displayGeometry)
        )
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.targetScreen = self.initialTargetScreen()
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
        displayGeometry.update(
            hasNotch: notch != nil,
            notchWidth: notch?.width ?? compactSize.width,
            safeTopInset: notch == nil ? 0 : screen.safeAreaInsets.top
        )
        let size = size(for: screen)
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

    private func size(for screen: NSScreen) -> NSSize {
        if viewModel.isExpanded {
            return NSSize(
                width: min(expandedSize.width, screen.visibleFrame.width - 24),
                height: expandedSize.height
                    + IslandLayout.expandedHeaderHeight(
                        forSafeTopInset: notchGeometry(on: screen) == nil
                            ? 0
                            : screen.safeAreaInsets.top
                    )
            )
        }

        guard let notch = notchGeometry(on: screen) else { return compactSize }
        return NSSize(
            width: min(
                IslandLayout.compactWidth(forNotchWidth: notch.width),
                screen.visibleFrame.width - 24
            ),
            height: IslandLayout.compactHeight(
                forSafeTopInset: screen.safeAreaInsets.top
            )
        )
    }

    private func panelTop(on screen: NSScreen) -> CGFloat {
        if notchGeometry(on: screen) != nil {
            return screen.frame.maxY
        }
        return bodyTop(on: screen)
    }

    private func bodyTop(on screen: NSScreen) -> CGFloat {
        guard notchGeometry(on: screen) != nil,
              let leftArea = screen.auxiliaryTopLeftArea else {
            return screen.frame.maxY - 8
        }
        // The body grows from the physical notch's lower edge, which is still
        // inside the 34pt menu bar on this display.
        return leftArea.minY
    }

    private var isPointerInsideInteractionRegion: Bool {
        let mouse = NSEvent.mouseLocation
        let isInsideNotch = NSScreen.screens.contains {
            notchRect(on: $0)?.contains(mouse) == true
        }
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
