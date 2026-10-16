import Foundation
import Darwin

private final class RestartGate: @unchecked Sendable {
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
}

@main struct Check {
  @MainActor static func main() async throws {
    let analyzer = CodexResetAnalyzer(analysisTimeout: 0.2)
    var usage = [ResetUsageRecord]()
    analyzer.onUsage = { usage.append($0) }
    let models = try await analyzer.listModels()
    precondition(models.count == 2 && models.last?.fastTier == "fast")
    let source = ResetSourceSnapshot(
      url: URL(string: "https://fixture.example")!, fetchedAt: Date(),
      text: "source says credit soon", fingerprint: "x", event: nil)
    var settings = ResetSubscriptionSettings()
    settings.fast = true
    let result = try await analyzer.analyze(snapshot: source, settings: settings)
    precondition(
      result.kind == .banked && result.usage?.totalTokens == 150
        && result.usage?.serviceTier == "fast")
    setenv("RESET_FIXTURE_MODE", "explicit-date", 1)
    for quote in ["2026-09-25T14:00:00Z", "2026-09-25 14:00 UTC", "2026-09-25 22:00 +08:00"] {
      var datedSource = source
      datedSource.text = quote
      let dated = try await analyzer.analyze(snapshot: datedSource, settings: settings)
      precondition(dated.scheduledAt == ResetDateParser.date("2026-09-25T14:00:00Z"))
    }
    for quote in ["2026-09-25 14:00", "2026-09-25 15:00 UTC", "2026-09-25 14:00 UTC+invalid"] {
      var datedSource = source
      datedSource.text = quote
      do {
        _ = try await analyzer.analyze(snapshot: datedSource, settings: settings)
        fatalError("Unverifiable date was accepted: \(quote)")
      } catch {
        precondition(error.localizedDescription.contains("带时区时间"))
      }
    }
    let failures = [
      ("failed", "fixture failure"),
      ("approval", "不允许的交互或工具操作"),
      ("reroute", "服务端将模型改为"),
      ("invented", "带时区时间"),
      ("timeout", "分析超时"),
      ("pending", "分析超时")
    ]
    for (mode, expectedMessage) in failures {
      setenv("RESET_FIXTURE_MODE", mode, 1)
      do {
        _ = try await analyzer.analyze(snapshot: source, settings: settings)
        fatalError("Unexpected success \(mode)")
      } catch {
        precondition(error.localizedDescription.contains(expectedMessage),
          "\(mode) failed for an unexpected reason: \(error)")
        print("EXPECTED \(mode): \(error.localizedDescription)")
      }
    }
    setenv("RESET_FIXTURE_MODE", "pending", 1)
    let task = Task { try await analyzer.analyze(snapshot: source, settings: settings) }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    do {
      _ = try await task.value
      fatalError("Unexpected cancellation success")
    } catch is CancellationError {
      print("EXPECTED cancellation")
    } catch CodexAppServerError.serverStopped {
      // The transport may finish its pending request before the actor receives cancellation.
      print("EXPECTED cancellation stopped transport")
    }
    setenv("RESET_FIXTURE_MODE", "success", 1)
    _ = try await analyzer.analyze(snapshot: source, settings: settings)
    precondition(usage.count >= 6)
    let client = CodexAppServerClient()
    try await client.start()
    let request = Task { try await client.request(method: "fixture/hang", timeout: 30) }
    try await Task.sleep(nanoseconds: 50_000_000)
    request.cancel()
    do {
      _ = try await request.value
      fatalError("Unexpected RPC cancellation success")
    } catch is CancellationError { print("EXPECTED RPC cancellation") }
    _ = try await client.request(method: "fixture/ping")
    client.stop()
    try await checkBlockedWrites()
    try await checkResumedWrites()
    try await checkBrokenPipe()
    try await checkExitedConnectionCannotStopReplacement()
    print(
      "PASS catalog pagination, Fast, success usage, failed usage, server approval denial, reroute, explicit and invented dates, timeout, pending cancellation, restart"
    )
  }

  @MainActor private static func checkBlockedWrites() async throws {
    for action in ["timeout", "cancel", "stop"] {
      let client = CodexAppServerClient()
      defer { client.stop() }
      try await client.start()
      let paused = try await client.request(method: "fixture/pause-input", params: [
        "seconds": 5, "ignoreTerm": action == "stop"
      ])
      guard let pid = paused.int("pid") else { fatalError("Missing paused fixture PID") }
      // A regression must fail in bounded time, even if the transport queue
      // gets stuck again. This watchdog only terminates this test's child.
      let watchdog = DispatchWorkItem { kill(pid_t(pid), SIGKILL) }
      DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
      defer { watchdog.cancel() }
      let began = ProcessInfo.processInfo.systemUptime
      let request = Task {
        try await client.request(method: "fixture/echo", params: [
          "label": "blocked", "text": String(repeating: "字", count: 75_000)
        ], timeout: action == "timeout" ? 0.2 : 30)
      }
      try await Task.sleep(nanoseconds: 100_000_000)
      if action == "cancel" { request.cancel() }
      if action == "stop" { client.stop() }
      var expectedError = false
      do {
        _ = try await request.value
      } catch CodexAppServerError.requestTimedOut(let method) {
        expectedError = action == "timeout" && method == "fixture/echo"
      } catch is CancellationError {
        expectedError = action == "cancel"
      } catch CodexAppServerError.serverStopped {
        expectedError = action == "stop"
      }
      let elapsed = ProcessInfo.processInfo.systemUptime - began
      client.stop()
      let exitDeadline = ProcessInfo.processInfo.systemUptime + 2.5
      while kill(pid_t(pid), 0) == 0, ProcessInfo.processInfo.systemUptime < exitDeadline {
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      let childExited = kill(pid_t(pid), 0) == -1 && errno == ESRCH
      watchdog.cancel()
      precondition(expectedError && elapsed < 1,
        "Blocked write must honor \(action) promptly (elapsed \(elapsed))")
      precondition(childExited, "Blocked fixture must exit after \(action), including TERM-resistant children")
      try await client.start()
      _ = try await client.request(method: "fixture/ping")
    }
    print("PASS blocked writes honor timeout, cancellation, stop, forced termination, and restart")
  }

  @MainActor private static func checkResumedWrites() async throws {
    let client = CodexAppServerClient()
    defer { client.stop() }
    try await client.start()
    _ = try await client.request(method: "fixture/pause-input", params: ["seconds": 0.4])
    let large = Task {
      try await client.request(method: "fixture/echo", params: [
        "label": "large", "text": String(repeating: "字", count: 75_000)
      ], timeout: 2)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    let cancelled = Task {
      try await client.request(method: "fixture/echo", params: ["label": "cancelled", "text": "discard me"])
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      fatalError("An unsent request should be cancellable")
    } catch is CancellationError {}
    let tail = Task {
      try await client.request(method: "fixture/echo", params: ["label": "tail", "text": "after large"])
    }
    let largeResult = try await large.value
    let tailResult = try await tail.value
    precondition(largeResult.int("characters") == 75_000 && tailResult.int("characters") == 11)
    let received = try await client.request(method: "fixture/received")
    precondition(received["labels"] as? [String] == ["large", "tail"],
      "Resumed writes preserve complete JSON frames and order, and never send cancelled queued requests")
    print("PASS backpressure resumes complete Unicode messages in order and drops unsent cancellations")
  }

  @MainActor private static func checkBrokenPipe() async throws {
    let previousSIGPIPE = signal(SIGPIPE, SIG_DFL)
    defer { signal(SIGPIPE, previousSIGPIPE) }
    let client = CodexAppServerClient()
    defer { client.stop() }
    try await client.start()
    _ = try await client.request(method: "fixture/close-input")
    do {
      _ = try await client.request(method: "fixture/ping", timeout: 1)
      fatalError("A closed input pipe must fail the request")
    } catch let error as NSError {
      precondition(error.domain == NSPOSIXErrorDomain && error.code == Int(EPIPE),
        "A disconnected nonblocking write must report EPIPE without terminating the client: \(error)")
    }
    try await client.start()
    _ = try await client.request(method: "fixture/ping")
    print("PASS nonblocking writes survive SIGPIPE and reconnect after a broken pipe")
  }

  @MainActor private static func checkExitedConnectionCannotStopReplacement() async throws {
    // Keep the transport occupied while a restart is queued ahead of the old
    // child's exit callback. Only the isolated fixture process is terminated.
    // Inherited SIG_IGN must not hide a broken-pipe crash in the client.
    let previousSIGPIPE = signal(SIGPIPE, SIG_DFL)
    defer { signal(SIGPIPE, previousSIGPIPE) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-island-reconnect-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let releaseFile = directory.appendingPathComponent("exit-old-server")
    let gate = RestartGate()
    let client = CodexAppServerClient()
    defer { gate.release.signal(); client.stop() }
    client.onServerRequest = { method, _ in
      guard method == "fixture/hold" else { return nil }
      gate.entered.signal()
      _ = gate.release.wait(timeout: .now() + 5)
      return [:]
    }
    try await client.start()
    let result = try await client.request(method: "fixture/restart-race", params: ["releaseFile": releaseFile.path])
    guard let pid = result.int("pid") else { fatalError("Missing fixture process ID") }
    precondition(gate.entered.wait(timeout: .now() + 2) == .success, "Old transport did not enter its callback")
    let restart = Task { try await client.start() }
    // The child cannot exit yet. Allow start() to enqueue on the occupied queue.
    try await Task.sleep(nanoseconds: 100_000_000)
    try Data().write(to: releaseFile)
    let deadline = Date().addingTimeInterval(2)
    while kill(pid_t(pid), 0) == 0, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    precondition(kill(pid_t(pid), 0) != 0 && errno == ESRCH, "Old fixture process did not exit")
    gate.release.signal()
    try await restart.value
    _ = try await client.request(method: "fixture/ping")
    print("PASS a disconnected write survives SIGPIPE and an old exit cannot tear down its replacement")
  }
}
