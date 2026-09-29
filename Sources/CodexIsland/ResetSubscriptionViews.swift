import AppKit
import SwiftUI

private enum ResetSubscriptionPresentation {
    static func phase(_ phase: ResetSubscriptionPhase, language: IslandInterfaceLanguage) -> String {
        switch phase {
        case .idle: return language.text("已同步", "Up to date")
        case .fetching: return language.text("正在获取", "Fetching")
        case .analyzing: return language.text("正在分析", "Analyzing")
        }
    }

    static func status(_ report: ResetSubscriptionReport, language: IslandInterfaceLanguage) -> String {
        if report.isExpired() { return language.text("预测已过期", "Forecast expired") }
        if report.isAwaitingConfirmation() { return language.text("时间已到 · 待确认", "Time reached · unconfirmed") }
        switch report.status {
        case .announced: return language.text("已公布", "Announced")
        case .scheduled: return language.text("已安排", "Scheduled")
        case .confirmed: return language.text("来源已确认", "Source confirmed")
        case .forecast: return language.text("预计", "Forecast")
        case .unknown: return language.text("时间待定", "Unconfirmed")
        }
    }

    static func evidence(_ level: ResetEvidenceLevel, language: IslandInterfaceLanguage) -> String {
        switch level {
        case .announcement: return language.text("来源公告", "Source announcement")
        case .observed: return language.text("站点记录", "Site observation")
        case .forecast: return language.text("站点预测", "Site forecast")
        case .inference: return language.text("模型推测", "Model inference")
        }
    }

    static func color(_ report: ResetSubscriptionReport, theme: IslandColorTheme) -> Color {
        if report.isExpired() || report.isAwaitingConfirmation() { return .orange }
        return report.status == .forecast || report.evidenceLevel == .inference ? .orange : theme.accent
    }

    static func date(_ value: Date, language: IslandInterfaceLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .chinese ? "zh_CN" : "en_US")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = language == .chinese ? "M月d日 HH:mm zzz" : "MMM d, HH:mm zzz"
        return formatter.string(from: value)
    }

    static func countdown(_ date: Date, language: IslandInterfaceLanguage) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSinceNow / 60)))
        if minutes == 0 { return language.text("时间已到", "Time reached") }
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60), hours = (minutes % (24 * 60)) / 60
            return language.text("约 \(days)天 \(hours)小时", "~\(days)d \(hours)h")
        }
        if minutes >= 60 {
            return language.text("约 \(minutes / 60)小时 \(minutes % 60)分", "~\(minutes / 60)h \(minutes % 60)m")
        }
        return language.text("约 \(minutes)分钟", "~\(minutes)m")
    }

    static func interval(_ settings: ResetSubscriptionSettings, language: IslandInterfaceLanguage) -> String {
        let amount = settings.intervalValue
        switch settings.intervalUnit {
        case .hours: return language.text("每 \(amount) 小时", "Every \(amount) h")
        case .minutes: return language.text("每 \(amount) 分钟", "Every \(amount) min")
        }
    }
}

struct ResetSubscriptionSummaryRow: View {
    @ObservedObject var service: ResetSubscriptionService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 7) {
                Image(systemName: service.isRefreshing ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent.opacity(0.85))
                Text(language.text("重置动态", "Reset updates"))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize()
                Text(summary)
                    .foregroundStyle(summaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.accent.opacity(isHovered ? 0.085 : 0.045)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(language.text("查看网站公告、时间依据和检查记录", "View source updates, timing evidence, and check history"))
        .accessibilityLabel(language.text("重置动态：", "Reset updates: ") + summary)
    }

    private var summary: String {
        if service.isRefreshing { return ResetSubscriptionPresentation.phase(service.phase, language: language) }
        if service.lastError != nil {
            return service.latest == nil
                ? language.text("检查失败 · 点击查看", "Check failed · View details")
                : language.text("更新失败 · 保留上次结果", "Update failed · Last result retained")
        }
        guard let report = service.latest else { return language.text("尚未检查", "Not checked yet") }
        if report.isExpired() || report.isAwaitingConfirmation() {
            return ResetSubscriptionPresentation.status(report, language: language)
        }
        if let date = report.scheduledAt, date > Date(), report.status != .confirmed {
            let prefix = report.status == .forecast ? language.text("预计 · ", "Forecast · ") : ""
            return prefix + ResetSubscriptionPresentation.countdown(date, language: language)
        }
        return report.timeDescription ?? report.title
    }

    private var summaryColor: Color {
        if service.lastError != nil { return .orange.opacity(0.85) }
        return service.latest.map { ResetSubscriptionPresentation.color($0, theme: theme).opacity(0.85) }
            ?? .white.opacity(0.40)
    }
}

struct ResetSubscriptionSettingCard: View {
    @ObservedObject var service: ResetSubscriptionService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let onConfigure: () -> Void
    @State private var error: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accent.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.accent.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(language.text("重置动态追踪", "Reset tracking"))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .fixedSize()
                    Text(language.text("（调用本地 Codex 分析，消耗账户额度）", "(Local Codex analysis · Uses quota)"))
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .help(language.text(
                            "通过本机 Codex CLI 分析来源内容，使用当前登录的 ChatGPT 订阅额度；默认仅在内容变化时调用模型。",
                            "Uses the local Codex CLI to analyze source content with your signed-in ChatGPT subscription quota. By default, analysis runs only when content changes."
                        ))
                }
                Text(error ?? subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(error == nil ? Color.white.opacity(0.32) : .orange)
                    .lineLimit(1)
            }
            Spacer(minLength: 3)
            Button(language.text("配置", "Configure"), action: onConfigure)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.accent.opacity(0.86))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(theme.accent.opacity(0.08)))
                .accessibilityIdentifier("reset-subscription-configure")
            Toggle(language.text("启用重置动态追踪", "Enable reset tracking"), isOn: enabled)
                .labelsHidden()
                .toggleStyle(IslandToggleStyle(tint: theme.accent))
                .accessibilityIdentifier("reset-subscription-enabled")
        }
        .padding(.horizontal, 9)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.028)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.065), lineWidth: 0.5))
    }

    private var subtitle: String {
        service.settings.enabled
            ? ResetSubscriptionPresentation.interval(service.settings, language: language)
                + " · " + CodexDisplayPolicy.displayModelName(service.settings.model)
                + language.text(" 分析", " analysis")
            : language.text("已关闭 · 可先配置", "Off · Configure anytime")
    }

    private var enabled: Binding<Bool> {
        Binding(get: { service.settings.enabled }, set: { value in
            var settings = service.settings
            settings.setAutomaticChecksEnabled(value)
            do { try service.updateSettings(settings); error = nil }
            catch { self.error = error.localizedDescription }
        })
    }
}

private struct ResetPageHeader: View {
    let title: String
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let onBack: () -> Void
    let accessoryTitle: String
    let onAccessory: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.65))
            .help(language.text("返回", "Back"))
            .accessibilityLabel(language.text("返回", "Back"))
            .accessibilityIdentifier("reset-page-back")
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
            Spacer()
            Button(accessoryTitle, action: onAccessory)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.accent.opacity(0.86))
                .padding(.horizontal, 8)
                .frame(height: 28)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}

struct ResetSubscriptionDetailsPage: View {
    @ObservedObject var service: ResetSubscriptionService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let onBack: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ResetPageHeader(
                title: language.text("重置动态", "Reset updates"), language: language, theme: theme,
                onBack: onBack, accessoryTitle: language.text("追踪设置", "Tracking settings"), onAccessory: onConfigure
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !service.settings.enabled {
                        notice(language.text("追踪已暂停，保留上次结果。", "Tracking paused. The last result is retained."), color: .white.opacity(0.48))
                    }
                    if let error = service.lastError { notice(error, color: .orange) }
                    if let report = service.latest {
                        reportContent(report)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language.text("等待第一条重置动态", "Waiting for the first update"))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.76))
                            Text(language.text("获取并分析来源网站的信息后，这里会显示公告、预计时间和来源依据。", "After checking and analyzing your source, announcements, expected timing, and supporting evidence appear here."))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        .padding(.vertical, 12)
                    }
                    checkMetadata
                    if !service.history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(language.text("最近变化", "Recent changes"))
                            ForEach(Array(service.history.filter { $0.id != service.latest?.id }.prefix(5))) { report in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(ResetSubscriptionPresentation.date(report.fetchedAt, language: language))
                                        .foregroundStyle(.white.opacity(0.30))
                                        .frame(width: 125, alignment: .leading)
                                    Text(report.title).foregroundStyle(.white.opacity(0.55))
                                }
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                        }
                    }
                }
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func reportContent(_ report: ResetSubscriptionReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                tag(ResetSubscriptionPresentation.status(report, language: language), color: ResetSubscriptionPresentation.color(report, theme: theme))
                tag(ResetSubscriptionPresentation.evidence(report.evidenceLevel, language: language), color: .white.opacity(0.5))
                Spacer()
            }
            Text(report.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            if let date = report.scheduledAt {
                if date > Date(), report.status != .confirmed, !report.isExpired() {
                    Text(ResetSubscriptionPresentation.countdown(date, language: language))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ResetSubscriptionPresentation.color(report, theme: theme))
                }
                Text(ResetSubscriptionPresentation.date(date, language: language))
                    .foregroundStyle(.white.opacity(0.52))
            } else if let time = report.timeDescription {
                Text(time).foregroundStyle(theme.accent.opacity(0.85))
            }
            Text(report.summary)
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let applicability = report.applicability, !applicability.isEmpty {
                Text(applicability).foregroundStyle(.white.opacity(0.43))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(theme.accent.opacity(0.045)))
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(language.text("来源与依据", "Source and evidence"))
            Text(report.evidence)
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Link(destination: report.sourceURL) {
                Label(report.sourceURL.host ?? report.sourceURL.absoluteString, systemImage: "arrow.up.right")
                    .foregroundStyle(theme.accent.opacity(0.8))
            }
            if let subscriptionURL = URL(string: service.settings.urlString), subscriptionURL != report.sourceURL {
                Link(destination: subscriptionURL) {
                    Text(language.text("信息来源：", "Information source: ") + (subscriptionURL.host ?? subscriptionURL.absoluteString))
                        .foregroundStyle(theme.accent.opacity(0.65))
                }
            }
            if let published = report.sourcePublishedAt {
                metadataRow(language.text("来源发布时间", "Published"), ResetSubscriptionPresentation.date(published, language: language))
            }
            if let expires = report.expiresAt {
                metadataRow(language.text("预测有效期至", "Forecast valid until"), ResetSubscriptionPresentation.date(expires, language: language))
            }
        }
    }

    private var checkMetadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(language.text("追踪状态", "Tracking status"))
            if let checked = service.lastCheckedAt {
                metadataRow(language.text("最近检查", "Last checked"), ResetSubscriptionPresentation.date(checked, language: language))
            }
            if let analyzed = service.lastAnalyzedAt {
                metadataRow(language.text("最近分析", "Last analyzed"), ResetSubscriptionPresentation.date(analyzed, language: language))
            }
            if service.settings.enabled, let next = service.nextCheckAt {
                metadataRow(language.text("下次检查", "Next check"), ResetSubscriptionPresentation.date(next, language: language))
            }
            if let report = service.latest, let model = report.model {
                metadataRow(language.text("本次分析模型", "Result model"), model + " · " + (report.reasoningEffort ?? "—").capitalized + (report.fast ? " · Fast" : ""))
            }
            if let usage = service.latest?.usage {
                metadataRow(language.text("本次分析消耗", "Analysis usage"), "\(usage.totalTokens.formatted()) tokens")
            }
        }
    }

    private var footer: some View {
        ResetSubscriptionFooter(
            service: service, language: language, theme: theme,
            idleMessage: language.text("网站动态独立于账号配额", "Source updates are separate from account limits"),
            onCheck: { service.checkNow() }
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.70))
    }
    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).foregroundStyle(.white.opacity(0.32)).frame(width: 104, alignment: .leading)
            Text(value).foregroundStyle(.white.opacity(0.52)).textSelection(.enabled)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }
    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.10)))
    }
    private func notice(_ text: String, color: Color) -> some View {
        Text(text).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.065)))
    }
}

/// Both tracking pages share the same action and progress/error feedback.
private struct ResetSubscriptionFooter: View {
    @ObservedObject var service: ResetSubscriptionService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let idleMessage: String
    var settingsError: String? = nil
    var isCheckDisabled = false
    let onCheck: () -> Void

    private var isDisabled: Bool { service.isRefreshing || isCheckDisabled }
    private var message: String {
        if service.isRefreshing { return ResetSubscriptionPresentation.phase(service.phase, language: language) }
        if settingsError != nil { return language.text("设置有误 · 尚未保存", "Settings need attention · Not saved") }
        if service.lastError != nil { return language.text("检查失败 · 可重试", "Check failed · Try again") }
        return idleMessage
    }
    private var actionTitle: String {
        if service.isRefreshing { return language.text("检查中…", "Checking…") }
        return service.lastError == nil
            ? language.text("立即检查", "Check now") : language.text("重试检查", "Retry check")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(!service.isRefreshing && (settingsError != nil || service.lastError != nil)
                    ? Color.orange.opacity(0.80) : .white.opacity(0.32))
                .lineLimit(1)
                .help(settingsError ?? service.lastError ?? message)
                .accessibilityIdentifier("reset-check-status")
            Spacer(minLength: 0)
            Button(action: onCheck) {
                Label(actionTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.accent.opacity(isDisabled ? 0.4 : 0.9))
            .fixedSize()
            .disabled(isDisabled)
            .accessibilityIdentifier("reset-check-now")
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
    }
}

struct ResetSubscriptionSettingsPage: View {
    @ObservedObject var service: ResetSubscriptionService
    let language: IslandInterfaceLanguage
    let theme: IslandColorTheme
    let allowsNetworkRequests: Bool
    let previewIntervalPickerPresentation: Bool?
    let previewModelPickerPresentation: Bool?
    let previewEffortHoverIndex: Int?
    let onBack: () -> Void
    let onDetails: () -> Void
    @State private var draft: ResetSubscriptionSettings
    @State private var intervalText: String
    @State private var saveError: String?
    @State private var pendingSave: Task<Void, Never>?
    @State private var isModelMenuPresented = false
    @State private var isIntervalMenuPresented = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case url, interval }

    init(service: ResetSubscriptionService, language: IslandInterfaceLanguage, theme: IslandColorTheme,
         allowsNetworkRequests: Bool, previewIntervalPickerPresentation: Bool? = nil,
         previewModelPickerPresentation: Bool? = nil, previewEffortHoverIndex: Int? = nil,
         onBack: @escaping () -> Void, onDetails: @escaping () -> Void) {
        self.service = service
        self.language = language
        self.theme = theme
        self.allowsNetworkRequests = allowsNetworkRequests
        self.previewIntervalPickerPresentation = previewIntervalPickerPresentation
        self.previewModelPickerPresentation = previewModelPickerPresentation
        self.previewEffortHoverIndex = previewEffortHoverIndex
        self.onBack = onBack
        self.onDetails = onDetails
        _draft = State(initialValue: service.settings)
        _intervalText = State(initialValue: String(service.settings.intervalValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            ResetPageHeader(
                title: language.text("追踪设置", "Tracking settings"), language: language, theme: theme,
                onBack: { commit(); onBack() }, accessoryTitle: language.text("查看动态", "View updates"),
                onAccessory: { commit(); onDetails() }
            )
            VStack(spacing: 8) {
                sourceRow
                ResetModelPicker(
                    settings: $draft, models: service.models, isLoadingModels: service.isLoadingModels,
                    language: language, theme: theme,
                    previewPresentation: previewModelPickerPresentation,
                    previewHoverIndex: previewEffortHoverIndex,
                    onPresentationChange: { isModelMenuPresented = $0 }
                )
                .frame(maxWidth: .infinity)
                .frame(height: ResetModelPicker.height)
                .zIndex((previewModelPickerPresentation ?? isModelMenuPresented) ? 2 : 1)
                scheduleRow
                    .zIndex((previewIntervalPickerPresentation ?? isIntervalMenuPresented) ? 2 : 0)
                optionsRow
                if let error = displayedError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(error)
                        .accessibilityIdentifier("reset-settings-validation")
                }
            }
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 18)
            .padding(.top, 4)
            Spacer(minLength: 0)
            settingsFooter

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onAppear { if allowsNetworkRequests { service.loadModels() } }
        .onChange(of: draft) { _ in scheduleSave() }
        .onChange(of: intervalText) { _ in scheduleSave() }
        .onDisappear { pendingSave?.cancel(); commit() }
        .onSubmit { commit() }
    }

    private var sourceRow: some View {
        HStack(spacing: 10) {
            fieldTitle(language.text("信息来源", "Source"))
                .frame(width: 64, alignment: .leading)
            TextField("https://codex-resets.com/", text: $draft.urlString)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .url)
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(fieldBackground)
                .help(language.text("HTTP / HTTPS；默认 codex-resets.com", "HTTP / HTTPS · Default: codex-resets.com"))
                .accessibilityLabel(language.text("信息来源 URL", "Source URL"))
                .accessibilityIdentifier("reset-source-url")
        }
        .frame(height: 30)
    }

    private var scheduleRow: some View {
        HStack(spacing: 10) {
            fieldTitle(language.text("检查频率", "Interval"))
                .frame(width: 64, alignment: .leading)
            TextField("12", text: $intervalText)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .interval)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(fieldBackground)
                .help(language.text("检查间隔：1 分钟至 7 天", "Check interval: 1 minute to 7 days"))
                .accessibilityLabel(language.text("检查间隔", "Check interval"))
                .accessibilityIdentifier("reset-check-interval")
            ResetIntervalUnitPicker(
                selection: $draft.intervalUnit, language: language, theme: theme,
                previewPresentation: previewIntervalPickerPresentation,
                onPresentationChange: { isIntervalMenuPresented = $0 }
            )
                .frame(maxWidth: .infinity)
                .frame(height: ResetIntervalUnitPicker.height)
        }
        .frame(height: 30)
    }

    private var optionsRow: some View {
        HStack(spacing: 8) {
            compactToggle(language.text("自动检查", "Auto-check"), isOn: automaticChecks)
                .help(language.text("按设定频率自动检查来源网站；开启时默认启用变化分析与通知", "Check automatically at this interval; enabling also turns on change analysis and notifications"))
                .accessibilityIdentifier("reset-automatic-checks")
            compactToggle(language.text("仅变化时分析", "Only changes"), isOn: $draft.analyzeOnlyChanges)
                .help(language.text("每次照常获取；内容不变时复用分析结果", "Fetch every time; reuse the analysis when content is unchanged"))
                .accessibilityIdentifier("reset-analyze-only-changes")
            compactToggle(language.text("重要变化通知", "Notifications"), isOn: $draft.notifyOnChange)
                .help(language.text("出现新公告或重置时间变化时提醒", "Notify when a new update or a timing change appears"))
                .accessibilityIdentifier("reset-notify-on-change")
        }
    }

    private var automaticChecks: Binding<Bool> {
        Binding(get: { draft.enabled }, set: { draft.setAutomaticChecksEnabled($0) })
    }

    private func compactToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            fieldTitle(title).lineLimit(1)
            Spacer(minLength: 2)
            Toggle(title, isOn: isOn)
                .labelsHidden().toggleStyle(IslandToggleStyle(tint: theme.accent))
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(fieldBackground)
    }

    private var settingsFooter: some View {
        ResetSubscriptionFooter(
            service: service, language: language, theme: theme,
            idleMessage: language.text("设置自动保存", "Settings save automatically"),
            settingsError: validationError ?? saveError,
            isCheckDisabled: validationError != nil
        ) {
            commit()
            if validationError == nil && saveError == nil { service.checkNow() }
        }
    }

    private var displayedError: String? {
        validationError ?? saveError ?? (service.models.isEmpty ? service.modelError : nil)
    }

    private var selectedModel: ResetAnalysisModel? { service.models.first { $0.id == draft.model } }
    private var modelValidationError: String? {
        if !service.models.isEmpty, selectedModel == nil {
            return language.text("当前账号未提供所选模型，请重新选择。", "The selected model is unavailable to this account. Choose another model.")
        }
        if let model = selectedModel, !model.reasoningEfforts.contains(draft.reasoningEffort) {
            return model.reasoningEfforts.isEmpty
                ? language.text("此模型未返回可用的推理档位。", "This model returned no available reasoning levels.")
                : language.text("请选择该模型支持的推理强度。", "Choose a reasoning effort supported by this model.")
        }
        if let model = selectedModel, draft.fast, model.fastTier == nil {
            return language.text("此模型不支持 Fast，请关闭 Fast。", "Fast is unavailable for this model. Turn Fast off.")
        }
        return nil
    }
    private var validationError: String? {
        let trimmed = draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else {
            return language.text("请输入完整的 HTTP(S) URL，且不要包含用户名或密码。", "Enter a complete HTTP(S) URL without a username or password.")
        }
        guard let amount = Int(intervalText), amount > 0 else {
            return language.text("检查间隔请输入正整数。", "Enter a positive whole number for the interval.")
        }
        let seconds = Double(amount) * (draft.intervalUnit == .hours ? 3600 : 60)
        guard seconds >= 60 && seconds <= 7 * 24 * 3600 else {
            return language.text("检查间隔必须在 1 分钟至 7 天之间。", "The interval must be between 1 minute and 7 days.")
        }
        return modelValidationError
    }
    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.055))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
    }
    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.74))
    }
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            commit()
        }
    }
    private func commit() {
        pendingSave?.cancel()
        guard validationError == nil, let interval = Int(intervalText) else { return }
        var value = draft
        value.intervalValue = interval
        do {
            try service.updateSettings(value)
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }
}
