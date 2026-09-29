import AppKit

@main
enum CodexIslandApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            exit(CodexResourceProbe.run())
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        // All UI is hosted by IslandPanelController, including settings.
        // A placeholder SwiftUI Settings scene creates a blank window on macOS 27.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
