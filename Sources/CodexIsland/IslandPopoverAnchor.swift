import AppKit
import SwiftUI

/// A native transient popover keeps editing outside the island's scroll layout.
struct IslandPopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.parent = self
        // Defer presentation until SwiftUI has attached and laid out the anchor.
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.updatePresentation(from: view)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var parent: IslandPopoverAnchor
        private var popover: NSPopover?
        private weak var panel: IslandPanel?
        private var localMouseMonitor: Any?
        private var globalMouseMonitor: Any?

        init(_ parent: IslandPopoverAnchor) { self.parent = parent }

        func updatePresentation(from anchor: NSView) {
            guard parent.isPresented else { close(); return }
            guard popover == nil, anchor.window != nil else { return }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.delegate = self
            let controller = NSHostingController(rootView: parent.content())
            controller.sizingOptions = [.preferredContentSize]
            popover.contentViewController = controller
            popover.contentSize = controller.view.fittingSize
            self.popover = popover
            panel = anchor.window as? IslandPanel
            panel?.hasActivePopover = true
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            controller.view.window?.makeKey()
            // Transient popovers can exempt clicks in a nonactivating parent
            // panel. Explicitly treat those clicks as cancellation as well.
            let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
                guard let self, let popoverWindow = self.popover?.contentViewController?.view.window else { return event }
                var target = event.window
                while let window = target {
                    if window === popoverWindow { return event }
                    target = window.parent
                }
                self.close()
                return event
            }
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
                self?.close()
            }
        }

        func close() { popover?.performClose(nil) }

        func popoverDidClose(_ notification: Notification) {
            if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
            if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
            localMouseMonitor = nil
            globalMouseMonitor = nil
            popover = nil
            panel?.hasActivePopover = false
            panel?.onPopoverDismissed?()
            panel = nil
            if parent.isPresented { parent.isPresented = false }
        }
    }
}
