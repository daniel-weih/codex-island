import AppKit
import SwiftUI

struct CodexConfigurationUpdateCard: View {
    @ObservedObject var service: CodexConfigurationService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.accent.opacity(0.78))
                .frame(width: 30, height: 30)
                .background(theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("模型与额度配置", "Model data updates"))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(service.error == nil ? .white.opacity(0.28) : .orange)
                    .lineLimit(1)
                    .help(service.error ?? statusText)
            }
            Spacer(minLength: 0)
            Stepper(value: Binding(get: { service.intervalDays }, set: service.setIntervalDays), in: 1...365) {
                Text(language.text("每 \(service.intervalDays) 天", "Every \(service.intervalDays) days"))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(.white.opacity(0.72))
            }
            .fixedSize()
            .accessibilityLabel(language.text("自动更新周期，天", "Automatic update interval, days"))
            .accessibilityIdentifier("model-update-interval")
            Button(action: service.updateNow) {
                Text(service.isRefreshing ? language.text("刷新中", "Refreshing") : language.text("立即刷新", "Refresh now"))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accent.opacity(service.isRefreshing ? 0.4 : 0.82))
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(theme.accent.opacity(0.075), in: Capsule())
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(service.isRefreshing)
            .accessibilityIdentifier("refresh-model-data")
        }
        .padding(.horizontal, 9)
        .frame(height: IslandLayout.settingsRowHeight)
        .background(.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.065), lineWidth: 1 / max(1, displayScale)))
    }

    private var statusText: String {
        if service.isRefreshing { return language.text("正在更新…", "Updating…") }
        if service.error != nil { return language.text("更新失败 · 已保留缓存", "Update failed · Cache retained") }
        return language.text("自动更新 · 不消耗额度", "Auto updates · No credit usage")
    }
}

struct CodexModelInformationPage: View {
    @ObservedObject var service: CodexConfigurationService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let onBack: () -> Void

    var body: some View {
        let olderModelIDs = service.configuration?.supersededModelIDs ?? []
        VStack(spacing: 10) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Text(language.text("模型信息", "Model information")).fontWeight(.semibold)
                Spacer()
            }
            .font(.system(size: 12))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if service.isRefreshing {
                        Text(language.text("正在获取最新配置…", "Fetching latest configuration…")).foregroundStyle(theme.accent)
                    }
                    if let error = service.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(language.text("读取 OpenAI 费率、Codex 目录与 AA 官网评分，不调用模型。失败时保留上次数据。",
                                               "Reads OpenAI pricing, the Codex catalog and AA scores without model calls. Failures keep previous data."))
                                .foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                            metadata(language.text("费率更新", "Pricing updated"), date(service.configuration?.pricingUpdatedAt))
                            metadata(language.text("目录更新", "Catalog updated"), date(service.configuration?.catalogUpdatedAt))
                            metadata(language.text("AA 更新", "AA updated"), date(service.configuration?.aaUpdatedAt))
                            metadata(language.text("下次更新", "Next update"), date(service.nextUpdate))
                            HStack {
                                Link(language.text("官方费率", "Official pricing"), destination: CodexConfigurationRefresh.pricingURL)
                                Link("AA", destination: CodexArtificialAnalysis.modelsURL)
                                Spacer()
                                Button(language.text("显示配置文件", "Show configuration file")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([service.fileURL])
                                }.buttonStyle(.plain)
                            }.foregroundStyle(theme.accent)
                        }.padding(.top, 8)
                    } label: {
                        HStack {
                            Text(language.text("更新详情", "Update details"))
                            Spacer()
                            Text(language.text("自动同步 · 不消耗额度", "Auto sync · No credit usage"))
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .tint(theme.accent)
                    CodexSubscriptionEstimatesCard(service: service, language: language, theme: theme)
                    Divider().overlay(.white.opacity(0.08))
                    Text(language.text("Credits 消耗", "Credit usage")).fontWeight(.semibold)
                    Text(language.text("输入 / 缓存 / 输出（credits / 百万 Token）", "Input / cached / output (credits / 1M tokens)"))
                        .foregroundStyle(.white.opacity(0.45))
                    ForEach(service.configuration?.visibleModelsByOutputCost ?? [], id: \.id) { model in
                        let isOlder = olderModelIDs.contains(model.id)
                        HStack {
                            Text(model.displayName).lineLimit(1)
                                .foregroundStyle(.white.opacity(isOlder ? 0.4 : 0.8))
                            Spacer()
                            Text(rate(model.id)).monospacedDigit()
                                .foregroundStyle(.white.opacity(isOlder ? 0.4 : 0.65))
                        }
                    }
                    if service.configuration?.catalog?.isEmpty != false {
                        Text(language.text("目录将在首次更新后显示", "Catalog appears after the first update")).foregroundStyle(.white.opacity(0.4))
                    }
                    Divider().overlay(.white.opacity(0.08))
                    Text(language.text("AA 评分", "AA scores")).fontWeight(.semibold)
                    Text(language.text("Intelligence Index · 按推理强度 · — 表示暂无评分", "Intelligence Index · by reasoning effort · — means unavailable"))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(service.configuration?.visibleModelsByOutputCost ?? [], id: \.id) { model in
                        let isOlder = olderModelIDs.contains(model.id)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.displayName).lineLimit(1)
                                .foregroundStyle(.white.opacity(isOlder ? 0.4 : 0.8))
                            Text(aaSummary(model)).font(.system(size: 10)).monospacedDigit()
                                .foregroundStyle(.white.opacity(isOlder ? 0.3 : 0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if service.configuration?.catalog?.isEmpty != false {
                        Text(language.text("目录将在首次更新后显示", "Catalog appears after the first update")).foregroundStyle(.white.opacity(0.4))
                    }
                    Divider().overlay(.white.opacity(0.08))
                    Text(language.text("Fast 消耗倍率（订阅内 / 购买额度）", "Fast usage multipliers (included / purchased)"))
                        .foregroundStyle(.white.opacity(0.45))
                    ForEach(service.configuration?.fastModels ?? [], id: \.id) { model in
                        metadata(model.displayName, fastRate(model.id))
                            .opacity(olderModelIDs.contains(model.id) ? 0.5 : 1)
                    }
                    if service.configuration?.fastModels.isEmpty != false {
                        Text(language.text("当前目录暂无提供 Fast 的模型", "No models in this catalog offer Fast"))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                }.font(.system(size: 11))
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(14)
    }
    private func metadata(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.white.opacity(0.5)); Spacer(); Text(value).monospacedDigit() }
    }
    private func number(_ value: Double) -> String { String(format: "%g", value) }
    private func aaSummary(_ model: CodexCreditConfiguration.CatalogModel) -> String {
        let entries = service.configuration?.aaScores?.filter { $0.model == model.id } ?? []
        let versions = Set(entries.map(\.version)).sorted().joined(separator: "/")
        let available = Set((model.reasoningEfforts + entries.map(\.effort)).filter { $0.lowercased() != "ultra" })
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        let efforts = order.filter { available.contains($0) } + available.subtracting(order).sorted()
        let values = efforts.map { effort in
            let score = entries.first { $0.effort == effort }?.score
            return effort + " " + (score.map { String(format: "%.1f", $0) } ?? "—")
        }.joined(separator: " · ")
        let prefix = versions.isEmpty ? "AA" : "AA " + versions
        if service.configuration?.aaUpdatedAt == nil && entries.isEmpty {
            return prefix + language.text(" · 等待首次更新", " · Awaiting first update")
        }
        return prefix + " · " + (values.isEmpty ? "—" : values)
    }
    private func fastRate(_ id: String) -> String {
        guard let policy = service.configuration?.fastPolicy(for: id) else { return "—" }
        return "\(number(policy.includedSubscription))× / \(policy.purchasedCredits.map { number($0) + "×" } ?? "—")"
    }
    private func rate(_ id: String) -> String {
        guard let rate = service.configuration?.rate(for: id) else { return "—" }
        return [rate.input, rate.cachedInput, rate.output].map(number).joined(separator: " / ")
    }
    private func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? language.text("等待首次更新", "Awaiting first update")
    }
}

struct CodexSubscriptionEstimatesCard: View {
    @ObservedObject var service: CodexConfigurationService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme

    private var derivedPlans: [String] {
        let ordered = ["prolite", "pro", "promax"]
        let configured = Set((service.configuration?.subscriptionEstimates ?? [:]).keys)
            .union((service.configuration?.subscriptionMultipliers ?? [:]).keys)
        return ordered + configured.filter { $0 != "plus" && !ordered.contains($0) }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.text("订阅额度", "Subscription allowance"))
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                    .help(language.text("以 Plus 为基准按倍率估算，不代表官方账户余额。修改 Plus 后，Pro 额度会同步更新。",
                                        "Estimates scale from Plus and are not official account balances. Editing Plus updates all Pro allowances."))
                    .accessibilityLabel(language.text("订阅额度估算说明", "About subscription estimates"))
                Spacer()
                Text("credits").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.bottom, 10)

            CodexPlusCreditEditor(service: service, language: language, theme: theme)
            Divider().overlay(.white.opacity(0.04)).padding(.vertical, 8)
            ForEach(derivedPlans, id: \.self) { plan in
                HStack(spacing: 6) {
                    Text(CodexSubscriptionPlan(rawValue: plan)?.displayName ?? plan)
                        .foregroundStyle(.white.opacity(0.65))
                    if let multiplier = service.configuration?.subscriptionMultipliers?[plan] {
                        Text("×" + Self.number(multiplier))
                            .font(.system(size: 9)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer(minLength: 8)
                    Text(service.configuration?.subscriptionCredits(for: plan).map { "≈ " + Self.number($0) } ?? "—")
                        .monospacedDigit().foregroundStyle(.white.opacity(0.75))
                }
                .frame(minHeight: 27)
            }

        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.85))
        .padding(12)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    fileprivate static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.automatic).precision(.fractionLength(0...6)))
    }
}

struct CodexPlusCreditEditor: View {
    @ObservedObject var service: CodexConfigurationService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    @State private var isEditing = false
    @State private var saved = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Plus").fontWeight(.medium)
            Text(language.text("基准", "Base"))
                .font(.system(size: 9)).foregroundStyle(theme.accent.opacity(0.85))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 3))
            Spacer(minLength: 8)
            Button {
                saved = false
                isEditing = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saved ? "checkmark" : "pencil")
                        .font(.system(size: 10)).foregroundStyle(theme.accent)
                        .opacity(saved || isHovering || isEditing ? 1 : 0)
                    Text(service.configuration?.subscriptionCredits(for: "plus")
                        .map { "≈ " + CodexSubscriptionEstimatesCard.number($0) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(isHovering || isEditing ? theme.accent : .white.opacity(0.9))
                }
                .frame(minHeight: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(language.text("修改 Plus 基准额度", "Edit the Plus baseline"))
            .accessibilityLabel(language.text("修改 Plus 基准额度", "Edit the Plus baseline"))
            .accessibilityIdentifier("edit-plus-credits")
            .background(IslandPopoverAnchor(isPresented: $isEditing) {
                CodexPlusCreditPopover(service: service, language: language, theme: theme,
                    onCancel: { isEditing = false }, onSave: {
                        isEditing = false
                        saved = true
                    })
            })
        }
        .task(id: saved) {
            guard saved else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            saved = false
        }
    }
}

struct CodexPlusCreditPopover: View {
    @ObservedObject var service: CodexConfigurationService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var draft: String
    @State private var saveError: String?
    @FocusState private var inputFocused: Bool

    init(service: CodexConfigurationService, language: IslandInterfaceLanguage, theme: IslandColorTheme,
         initialDraft: String? = nil, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.service = service
        self.language = language
        self.theme = theme
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft ?? service.configuration?.subscriptionCredits(for: "plus").map(Self.format) ?? "")
    }

    private var parsedCredits: Double? { Double(draft.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var hasChanges: Bool { parsedCredits != service.configuration?.subscriptionCredits(for: "plus") }
    private var validCredits: Double? {
        guard let credits = parsedCredits, credits.isFinite, credits > 0,
              (service.configuration?.subscriptionMultipliers ?? [:]).values.allSatisfy({
                  (credits * $0).isFinite && credits * $0 > 0
              }) else { return nil }
        return credits
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.text("Plus 基准额度", "Plus baseline"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5)).frame(width: 22, height: 22)
                        .background(.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help(language.text("取消 · Esc", "Cancel · Esc"))
                .accessibilityLabel(language.text("取消编辑", "Cancel editing"))
                .accessibilityIdentifier("cancel-plus-credits")
            }
            HStack(spacing: 8) {
                TextField(language.text("额度", "Credits"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium)).monospacedDigit()
                    .focused($inputFocused)
                    .accessibilityLabel(language.text("Plus 额度基准", "Plus credit baseline"))
                    .accessibilityIdentifier("plus-credit-baseline")
                    .onSubmit(save)
                    .onChange(of: draft) { _ in saveError = nil }
                Text("credits").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(saveError != nil ? Color.orange.opacity(0.7) : theme.accent.opacity(inputFocused ? 0.65 : 0.2), lineWidth: 1))

            VStack(spacing: 9) {
                HStack {
                    Text(language.text("Pro 同步预览", "Pro allowance preview"))
                    Spacer()
                    Text(language.text("尚未保存", "Not saved"))
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                ForEach([CodexSubscriptionPlan.prolite, .pro, .promax], id: \.rawValue) { plan in
                    HStack {
                        Text(plan.displayName).foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text(previewCredits(for: plan.rawValue)).monospacedDigit()
                    }
                }
            }
            .padding(10)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(language.text("仅用于估算，非官方余额", "Estimates only, not official balances"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if hasChanges {
                    Button(action: save) {
                        Text(language.text("保存 ↵", "Save ↵")).fontWeight(.medium)
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("save-plus-credits")
                }
            }
            .frame(minHeight: 28)
        }
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
        .padding(16).frame(width: 320)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.065, alpha: 1)))
        .onExitCommand(perform: onCancel)
        .onAppear { inputFocused = true }
    }

    private func previewCredits(for plan: String) -> String {
        guard let credits = validCredits,
              let multiplier = service.configuration?.subscriptionMultipliers?[plan] else { return "—" }
        return "≈ " + CodexSubscriptionEstimatesCard.number(credits * multiplier)
    }

    private func save() {
        guard hasChanges else { onCancel(); return }
        guard let credits = validCredits else {
            saveError = language.text("请输入大于 0 且未超出计算范围的额度", "Enter a positive amount within the supported range")
            return
        }
        do {
            try service.setPlusCredits(credits)
            onSave()
        } catch CodexConfigurationService.EditError.unavailable {
            saveError = language.text("配置不可用，暂时无法保存", "Configuration unavailable; unable to save")
        } catch {
            saveError = language.text("保存失败：", "Save failed: ") + error.localizedDescription
        }
    }

    private static func format(_ value: Double) -> String {
        let text = String(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
