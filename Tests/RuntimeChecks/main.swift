import Darwin
import Foundation

@main
@MainActor
struct RuntimeChecks {
    private static var failures = 0

    static func main() async {
        if CommandLine.arguments.contains("--shutdown-child-fixture") {
            // Exercise actual process exit; keeping this test process alive
            // would let the old delayed kill hide the orphan regression.
            atexit { CodexAppServerClient.shutdownAll() }
            do {
                let client = CodexAppServerClient()
                try await client.start()
                _ = try await client.request(method: "fixture/pause-for-shutdown")
                if CommandLine.arguments.contains("--stop-first") {
                    client.stop()
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                exit(EXIT_SUCCESS)
            } catch { exit(EXIT_FAILURE) }
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-runtime-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            setenv("ISLAND_RUNTIME_FIXTURE", directory.path, 1)
            // Local rollout discovery stays inside the disposable fixture too.
            setenv("CODEX_HOME", directory.path, 1)
            defer { try? FileManager.default.removeItem(at: directory) }
            try await checkOutputEOF(directory)
            try await checkStoppedRefresh(directory)
            try await checkStoppedActivity(directory)
            try await checkAccountChange(directory)
            await checkProfileDownloadLimits()
            try await checkApplicationShutdown(directory)
            try await checkLauncherTermination(directory)
        } catch {
            expect(false, "unexpected error: \(error)")
        }
        guard failures == 0 else {
            fputs("\(failures) runtime check(s) failed\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("All runtime checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; fputs("FAIL: \(message)\n", stderr) }
    }

    private static func configure(_ directory: URL, _ configuration: JSONObject = [:]) throws {
        try JSONSerialization.data(withJSONObject: configuration)
            .write(to: directory.appendingPathComponent("config.json"), options: .atomic)
    }

    private static func events(_ directory: URL) -> [String] {
        ((try? String(contentsOf: directory.appendingPathComponent("events"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private static func waitUntil(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(condition(), description)
    }

    private static func checkOutputEOF(_ directory: URL) async throws {
        try configure(directory)
        let client = CodexAppServerClient()
        defer { client.stop() }
        try await client.start()
        _ = try await client.request(method: "fixture/close-output")
        do {
            _ = try await client.request(method: "fixture/ping", timeout: 0.3)
            expect(false, "closed stdout must reject requests")
        } catch CodexAppServerError.requestTimedOut {
            expect(false, "stdout EOF must immediately invalidate a still-running child")
        } catch { }
        try await client.start()
        do {
            let result = try await client.request(method: "fixture/ping", timeout: 0.3)
            expect(result.bool("ok") == true, "a connection with closed stdout can restart")
        } catch {
            expect(false, "a connection with closed stdout can restart: \(error)")
        }
    }

    private static func checkStoppedRefresh(_ directory: URL) async throws {
        try configure(directory, ["stallAccount": true])
        let before = events(directory)
        let model = CodexStatusViewModel()
        model.refresh()
        try await waitUntil("full refresh reaches account/read") {
            events(directory).filter { $0 == "account/read" }.count
                > before.filter { $0 == "account/read" }.count
        }
        model.refresh() // Coalesce a second refresh while the first one awaits its RPC.
        model.stop()
        try await Task.sleep(nanoseconds: 250_000_000)
        expect(!model.isRefreshing, "stop immediately clears the refreshing indicator")
        expect(events(directory).filter { $0 == "launch" }.count
               == before.filter { $0 == "launch" }.count + 1,
               "a queued refresh must not restart the server after stop")
        expect(model.snapshot.lastUpdated == nil, "stopped refresh cannot publish a stale snapshot")
        model.stop()
        try configure(directory)
        model.start()
        try await waitUntil("the model can start again after stop") {
            model.snapshot.lastUpdated != nil && !model.isRefreshing
        }
        model.stop()
    }

    private static func checkAccountChange(_ directory: URL) async throws {
        try configure(directory, ["account": ["type": "chatgpt", "email": "old@fixture.invalid"], "tokens": 111])
        var initial = CodexSnapshot.initial
        initial.account = AccountSummary(authType: "chatgpt", planType: nil, requiresOpenAIAuth: false)
        initial.profileIdentity = ProfileIdentitySummary(displayName: "Previous account", avatarData: Data([1]))
        let model = CodexStatusViewModel(initialSnapshot: initial)
        defer { model.stop() }
        model.refresh()
        try await waitUntil("initial account refresh completes") { !model.isRefreshing }
        expect(model.snapshot.usage.lifetimeTokens == 111, "initial account usage loads")
        try configure(directory, ["account": ["type": "chatgpt", "email": "new@fixture.invalid"], "tokens": 222])
        model.refresh()
        try await waitUntil("switched account refresh completes") { !model.isRefreshing }
        expect(model.snapshot.usage.lifetimeTokens == 222,
               "account/read identity changes invalidate the previous account usage cache without a notification")
        expect(model.snapshot.profileIdentity == .empty,
               "a changed account cannot retain another account's name or avatar after a profile failure")
        try configure(directory, ["account": NSNull()])
        model.refresh()
        try await waitUntil("logout refresh completes") { !model.isRefreshing }
        expect(model.snapshot.account == .empty && model.snapshot.profileIdentity == .empty,
               "logout clears account identity")
    }

    private static func checkStoppedActivity(_ directory: URL) async throws {
        try configure(directory, ["stallThreadAfter": 1])
        let initialThreadRequests = events(directory).filter { $0 == "thread/list" }.count
        let model = CodexStatusViewModel()
        model.start()
        defer { model.stop() }
        try await waitUntil("the activity poll waits for thread/list after the initial refresh") {
            events(directory).filter { $0 == "thread/list" }.count == initialThreadRequests + 2
        }
        expect(model.snapshot.todayThreadTokens == nil, "activity fixture has not scanned local usage yet")
        model.stop()
        try await Task.sleep(nanoseconds: 250_000_000)
        expect(model.snapshot.todayThreadTokens == nil,
               "cancelling a pending activity RPC must not begin a detached usage scan after stop")
        await model.refreshDailyThreadTokens()
        expect(model.snapshot.todayThreadTokens == nil,
               "direct local usage refresh also respects an explicit stop")
    }

    private static func checkProfileDownloadLimits() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileResponseFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let account = Data(#"{"chatgpt_account_id":"fixture"}"#.utf8).base64EncodedString()
        let token = "e30.\(account).fixture"
        for avatar in [false, true] {
            ProfileResponseFixture.configure(avatar ? .oversizedAvatar : .oversizedProfile)
            let result = await CodexProfileIdentityProvider.load(authToken: token, session: session)
            expect(result.retrySoon && result.identity.avatarData == nil,
                   "oversized \(avatar ? "avatar" : "profile") response fails without an image")
            expect(ProfileResponseFixture.bytesSent < ProfileResponseFixture.responseSize,
                   "\(avatar ? "avatar" : "profile") size limit cancels the download before receiving its entire body")
        }
        ProfileResponseFixture.configure(.unauthorized)
        let unauthorized = await CodexProfileIdentityProvider.load(authToken: token, session: session)
        expect(unauthorized.authorizationRejected,
               "authentication rejection is detected without downloading even a large error body")
        ProfileResponseFixture.configure(.success)
        let success = await CodexProfileIdentityProvider.load(authToken: token, session: session)
        expect(success.isRemoteProfile && !success.retrySoon && success.identity.displayName == "Fixture"
               && success.identity.avatarData != nil, "bounded downloads preserve valid profiles and avatars")
    }

    private static func checkApplicationShutdown(_ directory: URL) async throws {
        let pidURL = directory.appendingPathComponent("shutdown-child-pid")
        let descendantURL = directory.appendingPathComponent("shutdown-grandchild-pid")
        for (stopFirst, fork) in [(false, false), (true, false), (false, true), (true, true)] {
            try configure(directory, ["shutdownFork": fork])
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: descendantURL)
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            helper.arguments = ["--shutdown-child-fixture"] + (stopFirst ? ["--stop-first"] : [])
            helper.standardInput = FileHandle.nullDevice
            helper.standardOutput = FileHandle.nullDevice
            helper.standardError = FileHandle.nullDevice
            try helper.run()
            defer { if helper.isRunning { kill(helper.processIdentifier, SIGKILL) } }
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while helper.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            expect(!helper.isRunning, "application shutdown finishes within its bounded grace period")
            if !helper.isRunning { expect(helper.terminationStatus == 0, "shutdown fixture exits successfully") }
            let pid = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let child = Int32(pid) else { throw CodexAppServerError.invalidResponse }
            let exited = kill(child, 0) == -1 && errno == ESRCH
            if !exited { kill(child, SIGKILL) }
            expect(exited, "parent exit reaps a TERM-resistant \(stopFirst ? "already-stopping" : "active") app-server")
            if fork {
                let text = try String(contentsOf: descendantURL, encoding: .utf8)
                guard let descendant = Int32(text) else { throw CodexAppServerError.invalidResponse }
                let deadline = ProcessInfo.processInfo.systemUptime + 1
                while kill(descendant, 0) == 0, ProcessInfo.processInfo.systemUptime < deadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let exited = kill(descendant, 0) == -1 && errno == ESRCH
                if !exited { kill(descendant, SIGKILL) }
                expect(exited, "shutdown also terminates a server whose launcher exited first (stopping=\(stopFirst))")
            }
        }
    }

    private static func checkLauncherTermination(_ directory: URL) async throws {
        try configure(directory, ["shutdownFork": true])
        let pidURL = directory.appendingPathComponent("shutdown-grandchild-pid")
        try? FileManager.default.removeItem(at: pidURL)
        let client = CodexAppServerClient()
        defer { client.stop() }
        try await client.start()
        _ = try await client.request(method: "fixture/pause-for-shutdown")
        guard let descendant = Int32(try String(contentsOf: pidURL, encoding: .utf8)) else {
            throw CodexAppServerError.invalidResponse
        }
        defer { if kill(descendant, 0) == 0 { kill(descendant, SIGKILL) } }
        client.stop()
        try await client.start()
        _ = try await client.request(method: "fixture/ping")
        try await waitUntil("stop terminates the launcher and its remaining server") {
            kill(descendant, 0) == -1 && errno == ESRCH
        }
        let ping = try await client.request(method: "fixture/ping")
        expect(ping.bool("ok") == true, "retiring the old process group preserves the replacement connection")
    }
}

/// Delivers a response without Content-Length in small chunks, so a limit
/// checked only after URLSession.data(for:) finishes cannot pass this check.
private final class ProfileResponseFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    enum Mode { case oversizedProfile, oversizedAvatar, success, unauthorized }
    private static var mode = Mode.oversizedProfile
    private static var sent = 0
    static let responseSize = 8 * 1_024 * 1_024
    static var bytesSent: Int { lock.withLock { sent } }
    static func configure(_ newMode: Mode) { lock.withLock { mode = newMode; sent = 0 } }
    private let stateLock = NSLock()
    private var stopped = false
    private var sentForRequest = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = Self.lock.withLock { Self.mode }
        let isProfile = request.url!.path.contains("profiles")
        var headers = ["Content-Type": isProfile ? "application/json" : "image/png"]
        if mode == .unauthorized { headers["Content-Length"] = String(Self.responseSize) }
        let response = HTTPURLResponse(url: request.url!, statusCode: mode == .unauthorized ? 401 : 200,
            httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if mode == .unauthorized {
            sendChunk()
        } else if mode != .oversizedProfile && isProfile {
            client?.urlProtocol(self, didLoad: Data(#"{"profile":{"display_name":"Fixture","profile_picture_url":"https://fixture.invalid/avatar"}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } else if mode == .success {
            let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6X8AAAAASUVORK5CYII=")!
            client?.urlProtocol(self, didLoad: pixel)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            sendChunk()
        }
    }
    override func stopLoading() { stateLock.withLock { stopped = true } }
    private func sendChunk() {
        guard !stateLock.withLock({ stopped }) else { return }
        let size = min(64 * 1_024, Self.responseSize - sentForRequest)
        guard size > 0 else { client?.urlProtocolDidFinishLoading(self); return }
        sentForRequest += size
        Self.lock.withLock { Self.sent += size }
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: size))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { self.sendChunk() }
    }
}
