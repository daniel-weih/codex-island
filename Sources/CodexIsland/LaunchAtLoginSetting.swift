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
        let plistURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
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

    static let previewDisabled = LaunchAtLoginBackend(
        readStatus: { .notRegistered },
        register: {},
        unregister: {}
    )

    static func launchAgent(
        plistURL: URL,
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
        let legacyKeys: Set<String> = [
            "Label",
            "ProgramArguments",
            "RunAtLoad"
        ]

        return LaunchAtLoginBackend(
            readStatus: {
                guard
                    let data = try? Data(contentsOf: plistURL),
                    let propertyList = try? PropertyListSerialization.propertyList(
                        from: data,
                        options: [],
                        format: nil
                    ),
                    let dictionary = propertyList as? [String: Any],
                    dictionary["Label"] as? String == launchAgentLabel,
                    dictionary["RunAtLoad"] as? Bool == true
                else {
                    return .notRegistered
                }

                if Set(dictionary.keys) == expectedKeys,
                   dictionary["ProgramArguments"] as? [String]
                    == programArguments,
                   dictionary["AssociatedBundleIdentifiers"] as? [String]
                    == [bundleIdentifier] {
                    return .enabled
                }

                if Set(dictionary.keys) == legacyKeys,
                   dictionary["ProgramArguments"] as? [String]
                    == legacyProgramArguments {
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
            },
            unregister: {
                guard fileManager.fileExists(atPath: plistURL.path) else {
                    return
                }
                try fileManager.removeItem(at: plistURL)
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

        switch (shouldEnable, currentStatus) {
        case (true, .enabled):
            state = .enabled
            return
        case (false, .notRegistered):
            state = .disabled
            return
        default:
            break
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
