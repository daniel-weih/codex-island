import Darwin
import Foundation

enum CodexExecutableLocator {
    struct LaunchConfiguration {
        let executableURL: URL
        let environment: [String: String]
    }

    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loginShellTimeout: TimeInterval = 3
    ) -> LaunchConfiguration? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let candidates: [String?] = [
            environment["CODEX_CLI_PATH"],
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex"
        ]

        for candidate in candidates.compactMap({ $0 }) where FileManager.default.isExecutableFile(atPath: candidate) {
            let executableURL = URL(fileURLWithPath: candidate)
            var launchEnvironment = augmentedEnvironment(environment: environment)
            if needsInterpreterPath(executableURL, environment: launchEnvironment),
               let shell = readLoginShell(environment: environment, timeout: loginShellTimeout, locateCLI: false) {
                launchEnvironment["PATH"] = shell.path
            }
            return LaunchConfiguration(executableURL: executableURL, environment: launchEnvironment)
        }

        return locateWithLoginShell(environment: environment, timeout: loginShellTimeout)
    }

    static func augmentedEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin"
        ]
        let existing = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (additions + [existing]).joined(separator: ":")
        return environment
    }

    private static func needsInterpreterPath(_ executable: URL, environment: [String: String]) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 4096), prefix.starts(with: [35, 33]) else { return false }
        let line = String(decoding: prefix, as: UTF8.self).split(separator: "\n", maxSplits: 1)[0]
        var words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard words.first == "/usr/bin/env" || words.first == "/bin/env" else { return false }
        words.removeFirst()
        if words.first == "-S" { words.removeFirst() }
        // Unusual env options/quoting may also depend on shell PATH. Recover it
        // without trying to execute the CLI or interpret its shebang ourselves.
        guard let command = words.first,
              !command.hasPrefix("-"), !command.contains("="),
              !command.contains("\""), !command.contains("'") else { return true }
        if command.hasPrefix("/") { return false }
        let paths = (environment["PATH"] ?? "").split(separator: ":")
        return !paths.contains { directory in
            directory.hasPrefix("/") && FileManager.default.isExecutableFile(
                atPath: URL(fileURLWithPath: String(directory)).appendingPathComponent(String(command)).path
            )
        }
    }

    static func locateWithLoginShell(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 3
    ) -> LaunchConfiguration? {
        guard let shell = readLoginShell(environment: environment, timeout: timeout, locateCLI: true),
              shell.executable.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: shell.executable) else { return nil }
        var launchEnvironment = environment
        launchEnvironment["PATH"] = shell.path
        return LaunchConfiguration(executableURL: URL(fileURLWithPath: shell.executable), environment: launchEnvironment)
    }

    private static func readLoginShell(
        environment: [String: String], timeout: TimeInterval, locateCLI: Bool
    ) -> (executable: String, path: String)? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        let fm = FileManager.default
        let resultURL = fm.temporaryDirectory.appendingPathComponent("codex-island-cli-\(UUID().uuidString)")
        guard fm.createFile(atPath: resultURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            return nil
        }
        defer { try? fm.removeItem(at: resultURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login profiles can print arbitrarily much output. Only capture the
        // lookup result and its PATH; npm's /usr/bin/env node shebang needs the
        // same interpreter search path that made the CLI discoverable.
        // NUL separators preserve spaces and newlines without parsing a banner.
        // An explicitly selected CLI may not be on the shell PATH at all.
        let command = locateCLI
            ? #"cli_path=$(command -v codex) || exit 1; builtin printf '%s\0%s\0' "$cli_path" "$PATH" > "$1""#
            : #"builtin printf '\0%s\0' "$PATH" > "$1""#
        process.arguments = ["-lc", command,
                             "codex-island-locate", resultURL.path]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                let pid = process.processIdentifier
                // Only signal a group whose leader is our lookup child. A
                // profile's subprocess can ignore TERM after the shell exits.
                let ownsGroup = getpgid(pid) == pid && getpgrp() != pid
                func lookupIsRunning() -> Bool {
                    ownsGroup ? kill(-pid, 0) == 0 : process.isRunning
                }
                process.terminate()
                let terminationDeadline = ProcessInfo.processInfo.systemUptime + 0.2
                while lookupIsRunning(), ProcessInfo.processInfo.systemUptime < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if lookupIsRunning() { kill(ownsGroup ? -pid : pid, SIGKILL) }
                process.waitUntilExit()
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }
            let data = try Data(contentsOf: resultURL)
            let fields = data.split(separator: 0, omittingEmptySubsequences: false)
            guard fields.count == 3, fields[2].isEmpty,
                  let path = String(data: fields[0], encoding: .utf8),
                  let shellPath = String(data: fields[1], encoding: .utf8) else { return nil }
            return (path, shellPath)
        } catch {
            return nil
        }
    }
}
