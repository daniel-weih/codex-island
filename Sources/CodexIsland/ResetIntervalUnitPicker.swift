import AppKit
import SwiftUI

/// Draw the field in SwiftUI so it shares the numeric field's exact height.
/// The native button preserves menu tracking, keyboard control and VoiceOver.
struct ResetIntervalUnitPicker: View {
    @Binding var selection: ResetIntervalUnit
    let language: IslandInterfaceLanguage

    var body: some View {
        ZStack {
            Text(label(for: selection))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack {
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(.trailing, 10)
            .accessibilityHidden(true)
            ResetIntervalMenuAnchor(selection: $selection, language: language)
        }
    }

    private func label(for unit: ResetIntervalUnit) -> String {
        unit == .hours ? language.text("小时", "Hours") : language.text("分钟", "Minutes")
    }
}

private struct ResetIntervalMenuAnchor: NSViewRepresentable {
    @Binding var selection: ResetIntervalUnit
    let language: IslandInterfaceLanguage

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ResetMenuButton {
        let button = ResetMenuButton(frame: .zero)
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityIdentifier("reset-interval-unit")
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ResetMenuButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = language.text("选择检查间隔的单位", "Choose the check interval unit")
        button.setAccessibilityLabel(language.text("检查间隔单位", "Check interval unit"))
        button.setAccessibilityValue(label(for: selection))
    }

    private func label(for unit: ResetIntervalUnit) -> String {
        unit == .hours ? language.text("小时", "Hours") : language.text("分钟", "Minutes")
    }

    final class Coordinator: NSObject {
        var parent: ResetIntervalMenuAnchor

        init(_ parent: ResetIntervalMenuAnchor) { self.parent = parent }

        @objc func openMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.minimumWidth = sender.bounds.width
            for unit in ResetIntervalUnit.allCases {
                let item = NSMenuItem(title: parent.label(for: unit), action: #selector(selectUnit(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = unit.rawValue
                item.state = unit == parent.selection ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }

        @objc private func selectUnit(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let unit = ResetIntervalUnit(rawValue: raw) else { return }
            parent.selection = unit
        }
    }
}
