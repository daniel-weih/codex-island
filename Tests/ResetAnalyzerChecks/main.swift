import Foundation

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
    print(
      "PASS catalog pagination, Fast, success usage, failed usage, server approval denial, reroute, explicit and invented dates, timeout, pending cancellation, restart"
    )
  }
}
