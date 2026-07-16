import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: CodexStatusViewModel?
    private var panelController: IslandPanelController?

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
        let panelController = IslandPanelController(viewModel: viewModel)

        self.viewModel = viewModel
        self.panelController = panelController

        panelController.start()
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
        viewModel?.stop()
    }

}
