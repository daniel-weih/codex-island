import AppKit
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: CodexStatusViewModel?
    private var panelController: IslandPanelController?
    private var resetSubscription: ResetSubscriptionService?
    private var subscriptions = Set<AnyCancellable>()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--probe") {
            Task {
                let code = await CodexProbe.run()
                exit(code)
            }
            return
        }

        if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            do {
                let outputDirectory = URL(
                    fileURLWithPath: CommandLine.arguments[flagIndex + 1],
                    isDirectory: true
                )
                let outputs = try CodexPreviewRenderer.render(to: outputDirectory)
                outputs.forEach { print($0.path) }
                exit(EXIT_SUCCESS)
            } catch {
                fputs("preview_error=\(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        let viewModel = CodexStatusViewModel()
        let resetSubscription = ResetSubscriptionService()
        let navigation = IslandNavigation()
        let panelController = IslandPanelController(viewModel: viewModel, subscription: resetSubscription, navigation: navigation)

        self.viewModel = viewModel
        self.panelController = panelController
        self.resetSubscription = resetSubscription
        resetSubscription.$usageRecords.sink { [weak viewModel] records in
            viewModel?.resetSubscriptionUsage = records
        }.store(in: &subscriptions)
        // Notification defaults do not prompt until automatic checks are on.
        resetSubscription.$settings.map { $0.enabled && $0.notifyOnChange }.removeDuplicates().sink { enabled in
            guard enabled, Bundle.main.bundleIdentifier != nil else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }.store(in: &subscriptions)
        resetSubscription.onNewReport = { report in
            guard Bundle.main.bundleIdentifier != nil else { return }
            let content = UNMutableNotificationContent()
            content.title = report.title
            content.body = report.summary
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "codex-island-reset-\(report.id)", content: content, trigger: nil
            ))
        }

        panelController.start()
        viewModel.start()
        resetSubscription.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
        viewModel?.stop()
        resetSubscription?.stop()
    }

}
