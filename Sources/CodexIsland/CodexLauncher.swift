import AppKit
import Foundation

enum CodexLauncher {
    static var settingsURL: URL? {
        URL(string: "codex://settings")
    }

    static func threadURL(threadID: String) -> URL? {
        let normalizedID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty,
              !normalizedID.hasPrefix("fallback-") else { return nil }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(normalizedID)"
        return components.url
    }

    @discardableResult
    static func openThread(threadID: String) -> Bool {
        guard let url = threadURL(threadID: threadID) else { return false }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    static func openSettings() -> Bool {
        guard let url = settingsURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    static func openCodex() -> Bool {
        guard let routeURL = settingsURL,
              let resolvedURL = NSWorkspace.shared.urlForApplication(toOpen: routeURL)
        else { return false }

        let applicationURL = resolvedURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { _, _ in }
        return true
    }
}
