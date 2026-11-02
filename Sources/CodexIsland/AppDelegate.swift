import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: CodexStatusViewModel?
    private var panelController: IslandPanelController?
    private var configurationService: CodexConfigurationService?

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
        let configurationService = CodexConfigurationService()
        let navigation = IslandNavigation()
        let panelController = IslandPanelController(viewModel: viewModel, configurationService: configurationService, navigation: navigation)

        self.viewModel = viewModel
        self.panelController = panelController
        self.configurationService = configurationService
        configurationService.onUpdate = { [weak viewModel] in viewModel?.refresh() }

        panelController.start()
        viewModel.start()
        configurationService.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
        viewModel?.stop()
        configurationService?.stop()
    }

}
