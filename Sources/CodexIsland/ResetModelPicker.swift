import AppKit
import SwiftUI

enum ResetReasoningAppearance {
    static let ultraAccent = Color(red: 0.68, green: 0.38, blue: 1)

    static func isUltra(_ effort: String) -> Bool { effort.lowercased() == "ultra" }

    static func accent(for effort: String, theme: IslandColorTheme) -> Color {
        isUltra(effort) ? ultraAccent : theme.accent
    }
}

/// A compact model/effort control. Catalog changes only change the available
/// controls; settings are written by explicit user actions.
struct ResetModelPicker: View {
    static let height: CGFloat = 74
    @Binding var settings: ResetSubscriptionSettings
    let models: [ResetAnalysisModel]
    let isLoadingModels: Bool
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    @State private var previewEffort: String?

    private var selectedModel: ResetAnalysisModel? { models.first { $0.id == settings.model } }
    private var efforts: [String] { selectedModel?.reasoningEfforts ?? [] }
    private var accent: Color {
        ResetReasoningAppearance.accent(for: previewEffort ?? settings.reasoningEffort, theme: theme)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                fastButton
                Spacer(minLength: 0)
                modelMenu
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                resetButton
            }
            ResetEffortSlider(
                selection: $settings.reasoningEffort,
                preview: $previewEffort,
                efforts: efforts,
                language: language,
                theme: theme
            )
            .frame(height: 24)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var fastButton: some View {
        Button {
            settings.fast.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: settings.fast ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text("Fast")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(settings.fast ? accent : .white.opacity(0.40))
            .frame(width: 28, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(settings.fast ? accent.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A failed catalog refresh must never prevent turning an existing Fast
        // selection off. Unknown or unsupported models cannot turn it on.
        .disabled(!settings.fast && selectedModel?.fastTier == nil)
        .help(fastHelp)
        .accessibilityLabel(language.text("Fast 模式", "Fast mode"))
        .accessibilityValue(settings.fast ? language.text("已开启", "On") : language.text("已关闭", "Off"))
        .accessibilityIdentifier("reset-fast-toggle")
    }

    private var fastHelp: String {
        if !settings.fast && selectedModel?.fastTier == nil {
            return language.text("当前模型未提供 Fast", "Fast is unavailable for the current model")
        }
        return settings.fast ? language.text("关闭 Fast", "Turn Fast off") : language.text("开启 Fast", "Turn Fast on")
    }

    private var modelMenu: some View {
        ZStack {
            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Text((previewEffort ?? settings.reasoningEffort).capitalized)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.36))
                }
                Text(modelName)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            ResetModelMenuAnchor(
                models: models,
                isLoadingModels: isLoadingModels,
                selectedID: settings.model,
                currentName: modelName,
                effort: settings.reasoningEffort,
                language: language,
                onSelect: selectModel
            )
        }
        .frame(height: 30)
    }

    private var resetButton: some View {
        Button {
            var updated = settings
            updated.model = "gpt-6-sol"
            updated.reasoningEffort = "max"
            updated.fast = false
            settings = updated
            previewEffort = nil
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language.text("恢复 GPT-6 Sol · Max · Fast 关闭", "Restore GPT-6 Sol · Max · Fast off"))
        .accessibilityLabel(language.text("恢复默认模型设置", "Restore default model settings"))
        .accessibilityIdentifier("reset-model-defaults")
    }

    private var modelName: String {
        if let model = selectedModel { return model.displayName }
        if settings.model == "gpt-6-sol" { return "GPT-6 Sol" }
        return settings.model
    }

    private func selectModel(_ model: ResetAnalysisModel) {
        var updated = settings
        updated.model = model.id
        if !model.reasoningEfforts.contains(updated.reasoningEffort), !model.reasoningEfforts.isEmpty {
            updated.reasoningEffort = model.reasoningEfforts.contains("max") ? "max" : model.reasoningEfforts.last!
        }
        if model.fastTier == nil { updated.fast = false }
        settings = updated
        previewEffort = nil
    }
}

/// SwiftUI's macOS Menu flattens a multi-line label into its native menu title.
/// Keep the two-line artwork in SwiftUI and use a native, accessible button only
/// for hit testing, keyboard focus, and presenting the catalog menu.
private struct ResetModelMenuAnchor: NSViewRepresentable {
    let models: [ResetAnalysisModel]
    let isLoadingModels: Bool
    let selectedID: String
    let currentName: String
    let effort: String
    let language: IslandInterfaceLanguage
    let onSelect: (ResetAnalysisModel) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ResetMenuButton {
        let button = ResetMenuButton(frame: .zero)
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityIdentifier("reset-analysis-model")
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ResetMenuButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = language.text("选择分析模型", "Choose an analysis model")
        button.setAccessibilityLabel(language.text("分析模型", "Analysis model"))
        button.setAccessibilityValue(currentName + ", " + effort.capitalized)
        button.setAccessibilityHelp(button.toolTip)
    }

    final class Coordinator: NSObject {
        var parent: ResetModelMenuAnchor

        init(_ parent: ResetModelMenuAnchor) { self.parent = parent }

        @objc func openMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.minimumWidth = sender.bounds.width
            if !parent.models.isEmpty && !parent.models.contains(where: { $0.id == parent.selectedID }) {
                let unavailable = NSMenuItem(
                    title: parent.currentName + parent.language.text("（当前不可用）", " (currently unavailable)"),
                    action: nil, keyEquivalent: ""
                )
                unavailable.isEnabled = false
                menu.addItem(unavailable)
            }
            for model in parent.models {
                let item = NSMenuItem(title: model.displayName, action: #selector(selectModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.id
                item.state = model.id == parent.selectedID ? .on : .off
                menu.addItem(item)
            }
            if parent.models.isEmpty {
                let empty = NSMenuItem(
                    title: parent.isLoadingModels
                        ? parent.language.text("正在获取模型列表…", "Loading models…")
                        : parent.language.text("模型列表暂不可用，将自动重试", "Models unavailable; retrying automatically"),
                    action: nil, keyEquivalent: ""
                )
                empty.isEnabled = false
                menu.addItem(empty)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }

        @objc private func selectModel(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let model = parent.models.first(where: { $0.id == id }) else { return }
            parent.onSelect(model)
        }
    }
}

final class ResetMenuButton: NSButton {
    override var acceptsFirstResponder: Bool { true }

    // The visible label belongs to SwiftUI. Draw only a native keyboard focus
    // indicator; do not hide this control from the accessibility hierarchy.
    override func draw(_ dirtyRect: NSRect) {
        guard window?.firstResponder === self else { return }
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.75).setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        outline.lineWidth = 1
        outline.stroke()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if [36, 49, 125, 126].contains(event.keyCode) {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformShowMenu() -> Bool {
        performClick(nil)
        return true
    }
}

private struct ResetEffortSlider: View {
    @Binding var selection: String
    @Binding var preview: String?
    let efforts: [String]
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    @State private var dragIndex: Int?
    @FocusState private var isFocused: Bool
    private let knobSize: CGFloat = 22

    private var selectedIndex: Int? { efforts.firstIndex(of: selection) }
    private var isInteractive: Bool { efforts.count > 1 }
    private var activeEffort: String {
        if let dragIndex, efforts.indices.contains(dragIndex) { return efforts[dragIndex] }
        return selection
    }
    private var showsUltraGradient: Bool {
        efforts.contains(activeEffort) && ResetReasoningAppearance.isUltra(activeEffort)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                rail
                    .frame(height: 18)
                if efforts.count > 1 {
                    ForEach(efforts.indices, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 3, height: 3)
                            .offset(x: center(for: index, width: geometry.size.width) - 1.5)
                    }
                }
                if let index = dragIndex ?? selectedIndex {
                    Circle()
                        .fill(Color.white.opacity(isInteractive ? 0.98 : 0.42))
                        .frame(width: knobSize, height: knobSize)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: center(for: index, width: geometry.size.width) - knobSize / 2)
                }
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isInteractive else { return }
                    isFocused = true
                    let index = index(at: value.location.x, width: geometry.size.width)
                    dragIndex = index
                    preview = efforts[index]
                }
                .onEnded { value in
                    guard isInteractive else { return }
                    selection = efforts[index(at: value.location.x, width: geometry.size.width)]
                    dragIndex = nil
                    preview = nil
                }
            )
        }
        .focusable(isInteractive)
        .focused($isFocused)
        .onMoveCommand { direction in
            guard isInteractive else { return }
            switch direction {
            case .left, .down: adjust(by: -1)
            case .right, .up: adjust(by: 1)
            @unknown default: break
            }
        }
        .overlay(Capsule().strokeBorder(
            ResetReasoningAppearance.accent(for: activeEffort, theme: theme)
                .opacity(isFocused ? 0.65 : 0), lineWidth: 1
        ).padding(-3))
        .accessibilityRepresentation {
            Slider(value: accessibleIndex, in: 0...Double(max(1, efforts.count - 1)), step: 1) {
                Text(language.text("推理强度", "Reasoning effort"))
            }
            .disabled(!isInteractive)
            .accessibilityValue(selection.capitalized)
            .accessibilityIdentifier("reset-reasoning-slider")
        }
        .help(isInteractive
            ? language.text("拖动或使用方向键调整推理强度", "Drag or use arrow keys to adjust reasoning effort")
            : language.text("当前模型没有可调整的推理档位", "This model has no adjustable reasoning levels"))
        .onChange(of: efforts) { _ in cancelPreview() }
        .onChange(of: selection) { _ in cancelPreview() }
        .onDisappear { cancelPreview() }
    }

    @ViewBuilder private var rail: some View {
        if showsUltraGradient {
            Capsule().fill(LinearGradient(
                colors: [Color(red: 0.44, green: 0.22, blue: 0.19),
                         Color(red: 0.62, green: 0.31, blue: 0.86),
                         ResetReasoningAppearance.ultraAccent,
                         Color(red: 0.68, green: 0.44, blue: 0.86)],
                startPoint: .leading, endPoint: .trailing
            ))
            .opacity(isInteractive ? 0.90 : 0.35)
        } else {
            Capsule().fill(theme.accent.opacity(isInteractive ? 0.62 : 0.16))
        }
    }

    private var accessibleIndex: Binding<Double> {
        Binding(get: { Double(selectedIndex ?? 0) }, set: { value in
            guard isInteractive else { return }
            selection = efforts[max(0, min(efforts.count - 1, Int(value.rounded())))]
        })
    }

    private func index(at x: CGFloat, width: CGFloat) -> Int {
        let length = max(1, width - knobSize)
        let fraction = min(1, max(0, (x - knobSize / 2) / length))
        return min(efforts.count - 1, max(0, Int((fraction * CGFloat(efforts.count - 1)).rounded())))
    }

    private func center(for index: Int, width: CGFloat) -> CGFloat {
        let fraction = efforts.count > 1 ? CGFloat(index) / CGFloat(efforts.count - 1) : 0
        return knobSize / 2 + fraction * max(0, width - knobSize)
    }

    private func adjust(by delta: Int) {
        let current = selectedIndex ?? (delta > 0 ? -1 : efforts.count)
        selection = efforts[min(efforts.count - 1, max(0, current + delta))]
    }

    private func cancelPreview() {
        dragIndex = nil
        preview = nil
    }
}
