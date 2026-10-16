import Foundation

struct CodexThreadCreditEstimate: Equatable, Sendable {
    var credits: Double
    var assumesStandardTier: Bool = false

    var amountText: String {
        if credits == 0 { return "0" }
        if credits > 0, credits < 0.05 { return "<0.1" }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), credits)
    }

    var displayText: String { amountText + " credits" }

}

/// Prices the cumulative tokens shown in a thread's popover. Unlike daily
/// usage, this includes recorded inherited history when it is part of that
/// cumulative counter. Unattributed counter jumps are never repriced using
/// the current model. Only reduced numeric state is cached between polls.
enum CodexThreadCreditUsageReader {
    private static let cache = ThreadCreditCache()

    static func estimate(
        from rolloutPath: String,
        matching usage: ThreadTokenUsage,
        threadID: String? = nil,
        validatePath: Bool = true
    ) throws -> CodexThreadCreditEstimate? {
        let url = try CodexThreadSettingsReader.rolloutURL(
            from: rolloutPath, threadID: threadID, validatePath: validatePath
        )
        return try cache.estimate(url: url, matching: usage)
    }
}

private struct CreditTokenCounts: Equatable {
    var input: Int64
    var cachedInput: Int64
    var output: Int64
    var total: Int64

    init?(json: JSONObject?) {
        guard let json,
              let input = json.int64("input_tokens"),
              let cachedInput = json.int64("cached_input_tokens"),
              let output = json.int64("output_tokens"),
              let total = json.int64("total_tokens"),
              input >= 0, cachedInput >= 0, cachedInput <= input,
              output >= 0, total >= input, total - input == output else {
            return nil
        }
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.total = total
    }

    func matches(_ usage: ThreadTokenUsage) -> Bool {
        input == usage.inputTokens && cachedInput == usage.cachedInputTokens
            && output == usage.outputTokens && total == usage.totalTokens
    }

    func follows(_ previous: Self, by last: Self) -> Bool {
        total >= previous.total && total - previous.total == last.total
            && input >= previous.input && input - previous.input == last.input
            && cachedInput >= previous.cachedInput
            && cachedInput - previous.cachedInput == last.cachedInput
            && output >= previous.output && output - previous.output == last.output
    }
}

private struct ThreadCreditReducer {
    var model: String?
    var provider = "openai"
    var serviceTier: String?
    var latest: CreditTokenCounts?
    var credits = 0.0
    var fullyPriced = true
    var assumesStandardTier = false

    mutating func consume(_ line: Data) {
        guard line.range(of: Data("token_count".utf8)) != nil
                || line.range(of: Data("turn_context".utf8)) != nil
                || line.range(of: Data("thread_settings_applied".utf8)) != nil
                || line.range(of: Data("session_meta".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              let payload = object.dictionary("payload") else { return }
        switch object.string("type") {
        case "session_meta":
            provider = payload.string("model_provider") ?? provider
            model = payload.string("model") ?? model
        case "turn_context":
            applySettings(payload)
        case "event_msg":
            if payload.string("type") == "thread_settings_applied",
               let settings = payload.dictionary("thread_settings") {
                applySettings(settings, isSettingsSnapshot: true)
            } else if payload.string("type") == "token_count",
                      let info = payload.dictionary("info"),
                      let total = CreditTokenCounts(json: info.dictionary("total_token_usage")) {
                consume(total: total, last: CreditTokenCounts(json: info.dictionary("last_token_usage")))
            }
        default:
            break
        }
    }

    private mutating func applySettings(_ settings: JSONObject, isSettingsSnapshot: Bool = false) {
        model = settings.string("model") ?? model
        provider = settings.string("model_provider_id") ?? provider
        if let tier = CodexThreadSettingsReader.recordedServiceTier(
            in: settings, isSettingsSnapshot: isSettingsSnapshot
        ) {
            serviceTier = tier
        }
    }

    private mutating func consume(total: CreditTokenCounts, last: CreditTokenCounts?) {
        if total == latest { return } // Repeated notifications are not calls.
        if let previous = latest, total.total < previous.total {
            // The popover now displays a reset counter, so its credits must
            // follow that same scope rather than retain the previous total.
            latest = nil
            credits = 0
            fullyPriced = true
            assumesStandardTier = false
        }
        let isAttributed = last.map { last in
            latest.map { total.follows($0, by: last) } ?? (last == total)
        } ?? false
        latest = total
        guard total.total > 0 else { return }
        guard isAttributed, let last,
              provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "openai",
              let cost = CodexCreditRateCard.credits(
                model: model,
                serviceTier: serviceTier,
                inputTokens: last.input,
                cachedInputTokens: last.cachedInput,
                outputTokens: last.output
              ), (credits + cost).isFinite else {
            fullyPriced = false
            return
        }
        credits += cost
        assumesStandardTier = assumesStandardTier || serviceTier == nil
    }

    func estimate(matching usage: ThreadTokenUsage) -> CodexThreadCreditEstimate? {
        guard fullyPriced, latest?.matches(usage) == true else { return nil }
        return CodexThreadCreditEstimate(credits: credits, assumesStandardTier: assumesStandardTier)
    }
}

private final class ThreadCreditCache: @unchecked Sendable {
    private struct Entry {
        var identity: String
        var fileSize: UInt64
        var modifiedAt: Date
        var resumeOffset: UInt64
        var reducer: ThreadCreditReducer
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func estimate(url: URL, matching usage: ThreadTokenUsage) throws -> CodexThreadCreditEstimate? {
        lock.lock()
        defer { lock.unlock() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let identity = [attributes[.systemNumber], attributes[.systemFileNumber]]
            .compactMap { ($0 as? NSNumber)?.stringValue }.joined(separator: ":")
        var entry = entries[url.path]
        if let entry, entry.identity == identity, entry.fileSize == size,
           entry.modifiedAt == modifiedAt {
            return entry.reducer.estimate(matching: usage)
        }
        if entry?.identity != identity || size <= (entry?.fileSize ?? 0) {
            entry = nil
        }
        var reducer = entry?.reducer ?? ThreadCreditReducer()
        let offset = try scan(
            url: url, from: entry?.resumeOffset ?? 0, to: size, reducer: &reducer
        )
        if entries.count >= 64, entries[url.path] == nil, let key = entries.keys.first {
            entries.removeValue(forKey: key)
        }
        entries[url.path] = Entry(
            identity: identity, fileSize: size, modifiedAt: modifiedAt,
            resumeOffset: offset, reducer: reducer
        )
        return reducer.estimate(matching: usage)
    }

    private func scan(
        url: URL, from start: UInt64, to end: UInt64,
        reducer: inout ThreadCreditReducer
    ) throws -> UInt64 {
        try CodexRolloutLineReader.scanCommittedLines(
            url: url, from: start, to: end,
            oversizedKinds: [.sessionMeta, .turnContext, .threadSettings, .tokenCount]
        ) { line, _, _ in
            if let line { reducer.consume(line) }
            return false
        }
    }
}
