import Foundation

enum LaunchAtLoginServiceStatus: Equatable {
    case notRegistered
    case enabled
    case legacyRegistered
}

enum LaunchAtLoginPresentationState: Equatable {
    case disabled
    case enabled
    case updateFailed(isEnabled: Bool)

    var isEnabled: Bool {
        switch self {
        case .enabled:
            return true
        case .updateFailed(let isEnabled):
            return isEnabled
        case .disabled:
            return false
        }
    }
}

struct LaunchAtLoginBackend {
    private static let appBundleIdentifier = "com.codexisland.app"
    private static let launchAgentLabel = "\(appBundleIdentifier).login-item"

    let readStatus: () -> LaunchAtLoginServiceStatus
    let register: () throws -> Void
    let unregister: () throws -> Void

    static var live: LaunchAtLoginBackend {
        let fileManager = FileManager.default
        let appBundleURL = Bundle.main.bundleURL
        let appExecutableURL = Bundle.main.executableURL
            ?? appBundleURL.appendingPathComponent(
                "Contents/MacOS/Codex Island"
            )
        let launchAgentsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDirectory
            .appendingPathComponent("\(launchAgentLabel).plist")
        return launchAgent(
            plistURL: plistURL,
            appBundleURL: appBundleURL,
            appExecutableURL: appExecutableURL,
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? appBundleIdentifier,
            fileManager: fileManager
        )
    }

    static func launchAgent(
        plistURL: URL,
        legacyPlistURLs: [URL] = [],
        appBundleURL: URL,
        appExecutableURL: URL,
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) -> LaunchAtLoginBackend {
        let normalizedAppURL = appBundleURL.standardizedFileURL
        let normalizedExecutableURL = appExecutableURL.standardizedFileURL
        let programArguments = [normalizedExecutableURL.path]
        let legacyProgramArguments = [
            "/usr/bin/open",
            "-g",
            normalizedAppURL.path
        ]
        let expectedPropertyList: [String: Any] = [
            "AssociatedBundleIdentifiers": [bundleIdentifier],
            "Label": launchAgentLabel,
            "ProgramArguments": programArguments,
            "RunAtLoad": true
        ]
        let expectedKeys = Set(expectedPropertyList.keys)

        func legacyCandidates() -> [URL] {
            // Older builds may add a registration while this app is running.
            // Take a fresh inventory for every status check and mutation.
            let discovered = (try? fileManager.contentsOfDirectory(
                at: plistURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            return Array(Set((legacyPlistURLs + discovered).map(\.standardizedFileURL)))
                .filter { $0 != plistURL.standardizedFileURL && $0.pathExtension == "plist" }
        }

        func propertyList(at url: URL) -> [String: Any]? {
            guard
                let data = try? Data(contentsOf: url),
                let propertyList = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                )
            else {
                return nil
            }
            return propertyList as? [String: Any]
        }

        func isLegacyCodexIslandAgent(at url: URL) -> Bool {
            guard let dictionary = propertyList(at: url) else { return false }
            let label = dictionary["Label"] as? String ?? ""
            // The dedicated label establishes ownership even after both the
            // application and the plist have moved or been renamed.
            if label == launchAgentLabel { return true }
            guard let arguments = dictionary["ProgramArguments"] as? [String] else { return false }

            func targetsApplication() -> Bool {
                if arguments == programArguments || arguments == legacyProgramArguments { return true }
                let bundleNames: Set<String> = [
                    normalizedAppURL.lastPathComponent.lowercased(),
                    "codex island.app", "codex-island.app", "codexisland.app"
                ]
                if arguments.count == 3, arguments[0] == "/usr/bin/open", arguments[1] == "-g",
                   arguments[2].hasPrefix("/") {
                    return bundleNames.contains(URL(fileURLWithPath: arguments[2]).lastPathComponent.lowercased())
                }
                guard arguments.count == 1, arguments[0].hasPrefix("/") else { return false }
                let target = URL(fileURLWithPath: arguments[0]).standardizedFileURL
                let executableNames: Set<String> = [
                    normalizedExecutableURL.lastPathComponent.lowercased(),
                    "codex island", "codex-island", "codexisland"
                ]
                return executableNames.contains(target.lastPathComponent.lowercased())
                    && target.deletingLastPathComponent().lastPathComponent == "MacOS"
                    && target.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents"
                    && bundleNames.contains(target.deletingLastPathComponent().deletingLastPathComponent()
                        .deletingLastPathComponent().lastPathComponent.lowercased())
            }
            let identifiers = dictionary["AssociatedBundleIdentifiers"] as? [String] ?? []
            let legacyName = [label, url.deletingPathExtension().lastPathComponent].contains {
                $0.lowercased().split(separator: ".").contains("codex-island")
            }
            // Legacy names alone are insufficient: also require the known
            // direct-exec/open shape and an app target, without requiring that
            // the previous installation still exists. RunAtLoad is deliberately
            // not an ownership condition; explicit disable cleans inactive rows.
            return targetsApplication() && (legacyName || identifiers.contains(bundleIdentifier))
        }

        return LaunchAtLoginBackend(
            readStatus: {
                let legacy = legacyCandidates().filter(isLegacyCodexIslandAgent)
                if let dictionary = propertyList(at: plistURL),
                   dictionary["Label"] as? String == launchAgentLabel,
                   dictionary["RunAtLoad"] as? Bool == true {
                    if Set(dictionary.keys) == expectedKeys,
                       dictionary["ProgramArguments"] as? [String]
                        == programArguments,
                       dictionary["AssociatedBundleIdentifiers"] as? [String]
                        == [bundleIdentifier] {
                        return legacy.isEmpty ? .enabled : .legacyRegistered
                    }

                    // The app-owned label survives relocation. Rewrite older
                    // registrations even when their executable path has moved.
                    return .legacyRegistered
                }

                if legacy.contains(where: { propertyList(at: $0)?["RunAtLoad"] as? Bool == true }) {
                    return .legacyRegistered
                }

                return .notRegistered
            },
            register: {
                try fileManager.createDirectory(
                    at: plistURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try PropertyListSerialization.data(
                    fromPropertyList: expectedPropertyList,
                    format: .xml,
                    options: 0
                )
                try data.write(to: plistURL, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: plistURL.path
                )
                for legacyURL in legacyCandidates()
                    where isLegacyCodexIslandAgent(at: legacyURL) {
                    try fileManager.removeItem(at: legacyURL)
                }
            },
            unregister: {
                if fileManager.fileExists(atPath: plistURL.path) {
                    try fileManager.removeItem(at: plistURL)
                }
                for legacyURL in legacyCandidates()
                    where isLegacyCodexIslandAgent(at: legacyURL) {
                    try fileManager.removeItem(at: legacyURL)
                }
            }
        )
    }
}

struct LaunchAtLoginSettingModel {
    private let backend: LaunchAtLoginBackend
    private(set) var state: LaunchAtLoginPresentationState

    init(backend: LaunchAtLoginBackend = .live) {
        self.backend = backend
        state = Self.refreshedState(using: backend)
    }

    mutating func refresh() {
        state = Self.refreshedState(using: backend)
    }

    mutating func setEnabled(_ shouldEnable: Bool) {
        let currentStatus = backend.readStatus()

        if shouldEnable, currentStatus == .enabled {
            state = .enabled
            return
        }

        do {
            if shouldEnable {
                try backend.register()
            } else {
                try backend.unregister()
            }
        } catch {
            // The file on disk remains the source of truth. Always reread it
            // because an operation may have partially or concurrently landed.
        }

        let resolvedStatus = backend.readStatus()
        switch resolvedStatus {
        case .enabled:
            state = shouldEnable
                ? .enabled
                : .updateFailed(isEnabled: true)
        case .legacyRegistered:
            state = .updateFailed(isEnabled: true)
        case .notRegistered:
            state = shouldEnable
                ? .updateFailed(isEnabled: false)
                : .disabled
        }
    }

    private static func refreshedState(
        using backend: LaunchAtLoginBackend
    ) -> LaunchAtLoginPresentationState {
        switch backend.readStatus() {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .legacyRegistered:
            do {
                try backend.register()
            } catch {
                // Reread below so a partial or concurrent migration is never
                // represented by a guessed switch state.
            }

            switch backend.readStatus() {
            case .enabled:
                return .enabled
            case .legacyRegistered:
                return .updateFailed(isEnabled: true)
            case .notRegistered:
                return .updateFailed(isEnabled: false)
            }
        }
    }
}
