import AppKit
import SwiftUI

struct IslandSelectionOption: Identifiable, Equatable {
    let id: String
    let title: String
    var isEnabled = true
}

enum IslandMenuPlacement { case above, below }

/// SwiftUI draws the same opaque menu on every macOS version. The native
/// anchor supplies keyboard focus, VoiceOver, and outside-click dismissal.
struct IslandSelectionPicker<Label: View>: View {
    @Binding var selection: String
    let options: [IslandSelectionOption]
    let theme: IslandColorTheme
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let help: String
    var placement: IslandMenuPlacement = .above
    var menuWidth: CGFloat? = nil
    var menuOverlap: CGFloat = 4
    var maxVisibleRows = 6
    var previewPresentation: Bool? = nil
    var onPresentationChange: (Bool) -> Void = { _ in }
    @ViewBuilder var label: (Bool, Bool) -> Label
    @State private var isPresented = false
    @State private var isHovered = false
    @State private var isFocused = false
    @State private var highlightedID: String?

    private var showsMenu: Bool { previewPresentation ?? isPresented }
    private var menuHeight: CGFloat {
        let rows = CGFloat(min(options.count, max(1, maxVisibleRows)))
        return rows * IslandSelectionMenuStyle.rowHeight
            + max(0, rows - 1) * IslandSelectionMenuStyle.spacing
            + 2 * IslandSelectionMenuStyle.inset
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                label(showsMenu, isHovered || isFocused)
                    .accessibilityHidden(true)
                IslandSelectionMenuAnchor(
                    selection: $selection, isPresented: $isPresented,
                    isFocused: $isFocused, highlightedID: $highlightedID,
                    options: options, placement: placement, menuOverlap: menuOverlap,
                    menuSize: CGSize(width: menuWidth ?? geometry.size.width, height: menuHeight),
                    accessibilityLabel: accessibilityLabel,
                    accessibilityIdentifier: accessibilityIdentifier, help: help
                )
                .allowsHitTesting(previewPresentation == nil)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: placement == .above ? .bottom : .top) {
                if showsMenu {
                    menu
                        .frame(width: menuWidth ?? geometry.size.width, height: menuHeight)
                        .offset(y: placement == .above ? menuOverlap - geometry.size.height : geometry.size.height - menuOverlap)
                }
            }
        }
        .zIndex(showsMenu ? 20 : 0)
        .onHover { isHovered = $0 }
        .onChange(of: isPresented) { onPresentationChange($0) }
        .onChange(of: options) { values in
            if !values.contains(where: { $0.id == highlightedID && $0.isEnabled }) {
                highlightedID = nil
            }
        }
        .onDisappear {
            isPresented = false
            onPresentationChange(false)
        }
    }

    private var menu: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: options.count > maxVisibleRows) {
                VStack(spacing: IslandSelectionMenuStyle.spacing) {
                    ForEach(options) { option in
                        Group {
                            if option.isEnabled {
                                Button {
                                    selection = option.id
                                    isPresented = false
                                } label: { optionLabel(option) }
                                .buttonStyle(.plain)
                            } else {
                                optionLabel(option)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityAddTraits(.isStaticText)
                            }
                        }
                        .onHover { hovering in
                            if hovering && option.isEnabled { highlightedID = option.id }
                            else if highlightedID == option.id { highlightedID = nil }
                        }
                        .help(option.title)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(selection == option.id ? .isSelected : [])
                        .accessibilityIdentifier(accessibilityIdentifier + "-" + option.id)
                        .id(option.id)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: highlightedID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .modifier(IslandSelectionMenuStyle())
    }

    private func optionLabel(_ option: IslandSelectionOption) -> some View {
        IslandSelectionMenuLabel(
            title: option.title, isSelected: selection == option.id,
            theme: theme, isAvailable: option.isEnabled,
            isHighlighted: highlightedID == option.id
        )
    }

}

private struct IslandSelectionMenuAnchor: NSViewRepresentable {
    @Binding var selection: String
    @Binding var isPresented: Bool
    @Binding var isFocused: Bool
    @Binding var highlightedID: String?
    let options: [IslandSelectionOption]
    let placement: IslandMenuPlacement
    let menuOverlap: CGFloat
    let menuSize: CGSize
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let help: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> IslandMenuButton {
        let button = IslandMenuButton(frame: .zero)
        button.title = ""
        button.isBordered = false
        button.focusRingType = .none
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        button.onFocusChange = { [weak coordinator = context.coordinator] in
            coordinator?.parent.isFocused = $0
        }
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: IslandMenuButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = help
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp(help)
        button.setAccessibilityValue(options.first { $0.id == selection }?.title ?? selection)
        button.setAccessibilityExpanded(isPresented)
        if isPresented { context.coordinator.startTracking(button) }
        else { context.coordinator.stopTracking() }
    }

    static func dismantleNSView(_ button: IslandMenuButton, coordinator: Coordinator) {
        button.onFocusChange = nil
        coordinator.stopTracking()
    }

    final class Coordinator: NSObject {
        var parent: IslandSelectionMenuAnchor
        private weak var button: IslandMenuButton?
        private var eventMonitor: Any?
        private var resignObserver: NSObjectProtocol?

        init(_ parent: IslandSelectionMenuAnchor) { self.parent = parent }
        deinit { stopTracking() }

        @objc func openMenu(_ sender: IslandMenuButton) {
            sender.window?.makeFirstResponder(sender)
            parent.highlightedID = NSApp.currentEvent?.type == .keyDown ? parent.selection : nil
            parent.isPresented.toggle()
            // Capture even keys arriving before SwiftUI's next update.
            if parent.isPresented { startTracking(sender) }
            else { stopTracking() }
        }

        func startTracking(_ button: IslandMenuButton) {
            guard eventMonitor == nil else { return }
            self.button = button
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: button.window, queue: .main
            ) { [weak self] _ in self?.parent.isPresented = false }
        }

        func stopTracking() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            eventMonitor = nil
            resignObserver = nil
            button = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard parent.isPresented, let button, let window = button.window else { return event }
            guard event.window === window else {
                parent.isPresented = false
                return event
            }
            if event.type == .keyDown {
                let enabled = parent.options.filter(\.isEnabled)
                switch event.keyCode {
                case 125, 126:
                    guard !enabled.isEmpty else { return nil }
                    let step = event.keyCode == 125 ? 1 : -1
                    let index = enabled.firstIndex { $0.id == (parent.highlightedID ?? parent.selection) }
                        ?? (step > 0 ? -1 : 0)
                    parent.highlightedID = enabled[(index + step + enabled.count) % enabled.count].id
                    return nil
                case 36, 76, 49:
                    if let option = enabled.first(where: { $0.id == (parent.highlightedID ?? parent.selection) }) {
                        parent.selection = option.id
                    }
                    parent.isPresented = false
                    return nil
                case 53:
                    parent.isPresented = false
                    return nil
                case 48:
                    parent.isPresented = false
                default: break
                }
            } else {
                let anchor = button.convert(button.bounds, to: nil)
                let menu = CGRect(
                    x: anchor.midX - parent.menuSize.width / 2,
                    y: parent.placement == .above ? anchor.maxY - parent.menuOverlap : anchor.minY + parent.menuOverlap - parent.menuSize.height,
                    width: parent.menuSize.width, height: parent.menuSize.height
                )
                if !anchor.contains(event.locationInWindow) && !menu.contains(event.locationInWindow) {
                    parent.isPresented = false
                }
            }
            return event
        }
    }
}

private final class IslandMenuButton: NSButton {
    var onFocusChange: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    // The SwiftUI surface represents focus; AppKit must not add an outline.
    override func draw(_ dirtyRect: NSRect) {}
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }
    override func keyDown(with event: NSEvent) {
        if [36, 76, 49, 125, 126].contains(event.keyCode) { performClick(nil) }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformShowMenu() -> Bool {
        performClick(nil)
        return true
    }
}
