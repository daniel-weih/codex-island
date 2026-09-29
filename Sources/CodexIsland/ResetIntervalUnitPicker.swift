import SwiftUI

struct ResetIntervalUnitPicker: View {
    static let height: CGFloat = 30
    @Binding var selection: ResetIntervalUnit
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    var previewPresentation: Bool? = nil
    var onPresentationChange: (Bool) -> Void = { _ in }

    var body: some View {
        IslandSelectionPicker(
            selection: Binding(get: { selection.rawValue }, set: { value in
                if let unit = ResetIntervalUnit(rawValue: value) { selection = unit }
            }),
            options: ResetIntervalUnit.allCases.map { .init(id: $0.rawValue, title: label(for: $0)) },
            theme: theme,
            accessibilityLabel: language.text("检查间隔单位", "Check interval unit"),
            accessibilityIdentifier: "reset-interval-unit",
            help: language.text("选择检查间隔的单位", "Choose the check interval unit"),
            previewPresentation: previewPresentation,
            onPresentationChange: onPresentationChange
        ) { presented, hovered in
            IslandPickerLabel(title: label(for: selection), systemImage: "clock", theme: theme,
                              isPresented: presented, isHovered: hovered, height: Self.height)
        }
        .frame(height: Self.height)
    }

    private func label(for unit: ResetIntervalUnit) -> String {
        unit == .hours ? language.text("小时", "Hours") : language.text("分钟", "Minutes")
    }
}
