import Foundation

/// Standalone integration probe. No settings, reports, or account identifiers are persisted.
/// By default it performs read-only catalog discovery and public-source fetch only.
@main
struct ResetSubscriptionProbe {
  @MainActor
  static func main() async {
    let analyzer = CodexResetAnalyzer()
    do {
      let models = try await analyzer.listModels()
      for model in models {
        let tiers = model.serviceTiers.map { "\($0.id):\($0.name)" }.joined(separator: ",")
        print(
          "MODEL \(model.id) efforts=\(model.reasoningEfforts.joined(separator: ",")) tiers=\(tiers)"
        )
      }
      let source = try await ResetSubscriptionSource.fetch(
        url: URL(string: "https://codex-resets.com/")!)
      print(
        "SOURCE characters=\(source.text.count) kind=\(source.event?.kind.rawValue ?? "none") status=\(source.event?.status.rawValue ?? "none")"
      )
      guard CommandLine.arguments.contains("--analyze") else { return }
      analyzer.onUsage = { usage in
        print(
          "USAGE model=\(usage.model) tier=\(usage.serviceTier ?? "default") input=\(usage.inputTokens) cached=\(usage.cachedInputTokens) output=\(usage.outputTokens) total=\(usage.totalTokens)"
        )
      }
      let result = try await analyzer.analyze(
        snapshot: source, settings: ResetSubscriptionSettings())
      print("RESULT kind=\(result.kind.rawValue) status=\(result.status.rawValue)")
      print("TITLE \(result.title)")
      print("SUMMARY \(result.summary)")
      print("TIME \(result.scheduledAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none")")
    } catch {
      FileHandle.standardError.write(Data("PROBE FAILED: \(error.localizedDescription)\n".utf8))
      analyzer.cancel()
      exit(1)
    }
  }
}

// Keep this probe independent of the SwiftUI app target. These are the same JSON
// accessors the production transport uses from CodexStatusPayloadParser.swift.
typealias JSONObject = [String: Any]
extension Dictionary where Key == String, Value == Any {
  func dictionary(_ key: String) -> JSONObject? { self[key] as? JSONObject }
  func array(_ key: String) -> [Any]? { self[key] as? [Any] }
  func string(_ key: String) -> String? {
    guard let value = self[key] as? String, !value.isEmpty else { return nil }
    return value
  }
  func bool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
  func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
  func int64(_ key: String) -> Int64? { (self[key] as? NSNumber)?.int64Value }
}
