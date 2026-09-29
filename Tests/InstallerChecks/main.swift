import Darwin
import Foundation

@main
enum InstallerChecks {
    static func main() throws {
        let fm = FileManager.default
        guard CommandLine.arguments.count == 2 else { print("Expected a temporary fixture directory"); exit(1) }
        // The shell runner owns this directory and removes it even if a check exits early.
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var passed = 0

        func fixture(_ app: URL, marker: String, id: String = AppInstaller.bundleIdentifier) throws {
            let macOS = app.appendingPathComponent("Contents/MacOS")
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": id, "CFBundlePackageType": "APPL", "CFBundleExecutable": "Codex Island"
            ], format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
            let executable = macOS.appendingPathComponent("Codex Island")
            try Data(marker.utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        func marker(_ app: URL) -> String? {
            try? String(contentsOf: app.appendingPathComponent("Contents/MacOS/Codex Island"), encoding: .utf8)
        }
        func require(_ condition: Bool, _ message: String) {
            guard condition else { print("FAIL: \(message)"); exit(1) }
        }
        func expectFailure(_ body: () throws -> Void) {
            do { try body(); print("FAIL: Expected installation to fail"); exit(1) } catch {}
        }
        func scenario(_ name: String, existing: Bool = true,
                      _ test: (URL, URL, inout AppInstaller) throws -> Void) throws {
            print("Checking \(name)")
            let directory = root.appendingPathComponent(name)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("source/Codex Island.app")
            let destination = directory.appendingPathComponent(AppInstaller.appName)
            try fixture(source, marker: "new")
            if existing { try fixture(destination, marker: "old") }
            var installer = AppInstaller()
            installer.validate = { _ = try AppInstaller.bundleExecutable($0) }
            try test(source, destination, &installer)
            passed += 1
        }
        let injected = InstallationError(message: "Injected failure")
        try scenario("fresh", existing: false) { source, destination, installer in
            try installer.install(from: source, to: destination)
            require(marker(destination) == "new", "fresh installation")
            require(marker(source) == "new", "source is untouched")
        }
        try scenario("update") { source, destination, installer in
            var stopped = false
            installer.stopApplication = { _ in
                require(marker(destination) == "old", "old app stays installed until termination")
                stopped = true
            }
            try installer.install(from: source, to: destination)
            require(stopped && marker(destination) == "new", "update stops and replaces old app")
            installer.stopApplication = { _ in }
            try installer.install(from: source, to: destination)
        }
        try scenario("repair-missing-executable") { source, destination, installer in
            try fm.removeItem(at: destination.appendingPathComponent("Contents/MacOS/Codex Island"))
            try installer.install(from: source, to: destination)
            require(marker(destination) == "new", "repairs an incomplete previous installation")
        }
        try scenario("invalid-source") { source, destination, installer in
            installer.validate = { _ in throw injected }
            installer.stopApplication = { _ in fatalError("Invalid payload must not stop the app") }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "old", "invalid payload preserves old app")
        }
        try scenario("invalid-copy") { source, destination, installer in
            installer.validate = { if $0.resolvingSymlinksInPath().path != source.resolvingSymlinksInPath().path { throw injected } }
            installer.stopApplication = { _ in fatalError("Invalid staged payload must not stop the app") }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "old", "invalid copy preserves old app")
        }
        try scenario("cannot-quit") { source, destination, installer in
            installer.stopApplication = { _ in throw injected }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "old", "quit failure preserves old app")
        }
        try scenario("cannot-swap") { source, destination, installer in
            installer.rename = { _, _, _ in throw injected }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "old", "commit failure preserves old app")
        }
        try scenario("rollback") { source, destination, installer in
            installer.validate = { if $0.resolvingSymlinksInPath().path == destination.resolvingSymlinksInPath().path { throw injected } }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "old", "post-install failure rolls back")
        }
        try scenario("fresh-rollback", existing: false) { source, destination, installer in
            installer.validate = { if $0.resolvingSymlinksInPath().path == destination.resolvingSymlinksInPath().path { throw injected } }
            expectFailure { try installer.install(from: source, to: destination) }
            require(!fm.fileExists(atPath: destination.path), "fresh install rolls back invalid app")
        }
        try scenario("target-race", existing: false) { source, destination, installer in
            installer.rename = { from, to, flags in
                try fixture(destination, marker: "other")
                try AppInstaller.renameItem(from, to, flags)
            }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "other", "no-clobber commit preserves an intervening app")
        }
        try scenario("target-changed") { source, destination, installer in
            installer.stopApplication = { _ in
                try fm.moveItem(at: destination, to: destination.appendingPathExtension("moved"))
                try fixture(destination, marker: "other")
            }
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "other", "identity check detects a concurrent update")
        }
        try scenario("unrelated-target") { source, destination, installer in
            try fixture(destination, marker: "other", id: "com.example.other")
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(destination) == "other", "unrelated bundle preserved")
        }
        try scenario("symlink-target", existing: false) { source, destination, installer in
            try fm.createSymbolicLink(at: destination, withDestinationURL: source)
            expectFailure { try installer.install(from: source, to: destination) }
            require(marker(source) == "new", "symlink target preserved")
        }
        try scenario("symlink-source") { source, destination, installer in
            let link = source.deletingLastPathComponent().appendingPathComponent("link.app")
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            expectFailure { try installer.install(from: link, to: destination) }
            require(marker(destination) == "old", "symlink source refused")
        }
        // Every normal success/failure above must remove its own staging directory.
        let leftovers = fm.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        require(!leftovers.contains { $0.lastPathComponent.hasPrefix(".codex-island-install-") }, "temporary files cleaned")

        try scenario("rollback-failed") { source, destination, installer in
            installer.validate = { if $0.resolvingSymlinksInPath().path == destination.resolvingSymlinksInPath().path { throw injected } }
            var renames = 0
            installer.rename = { from, to, flags in
                renames += 1
                if renames == 2 { throw injected }
                try AppInstaller.renameItem(from, to, flags)
            }
            expectFailure { try installer.install(from: source, to: destination) }
            let staging = try fm.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix(".codex-island-install-") }
            require(staging != nil && marker(staging!.appendingPathComponent(AppInstaller.appName)) == "old",
                    "failed recovery retains the old app")
        }
        print("All \(passed) installer checks passed (replacement, validation, rollback, races, cleanup)")
    }
}
