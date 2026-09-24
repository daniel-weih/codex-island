import Foundation

enum ResetIntervalUnit: String, Codable, CaseIterable {
    case minutes, hours
}

struct ResetSubscriptionSettings: Codable, Equatable {
    var enabled = false
    var urlString = "https://codex-resets.com/"
    var intervalValue = 12
    var intervalUnit: ResetIntervalUnit = .hours
    var model = "gpt-6-sol"
    var reasoningEffort = "max"
    var fast = false
    var analyzeOnlyChanges = true
    var notifyOnChange = true
    // Missing in the original hourly-default settings. Once migrated, even
    // an explicitly chosen one-hour interval is preserved on future launches.
    var defaultsVersion: Int? = 2

    var interval: TimeInterval {
        TimeInterval(intervalValue) * (intervalUnit == .hours ? 3600 : 60)
    }

    mutating func setAutomaticChecksEnabled(_ enabled: Bool) {
        if enabled && !self.enabled {
            analyzeOnlyChanges = true
            notifyOnChange = true
        }
        self.enabled = enabled
    }

    func migratingLegacyDefaults() -> Self {
        guard defaultsVersion == nil else { return self }
        var value = self
        if intervalUnit == .hours && intervalValue == 1 { value.intervalValue = 12 }
        value.defaultsVersion = 2
        return value
    }

    func validated() throws -> Self {
        var value = self
        value.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.urlString),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw ResetSubscriptionError.invalidSettings("请输入不含用户名或密码的完整 HTTP(S) URL。")
        }
        guard intervalValue > 0, interval >= 60, interval <= 7 * 24 * 3600 else {
            throw ResetSubscriptionError.invalidSettings("检查间隔必须在 1 分钟至 7 天之间。")
        }
        guard !model.isEmpty, !reasoningEffort.isEmpty else {
            throw ResetSubscriptionError.invalidSettings("请选择分析模型及推理强度。")
        }
        return value
    }
}

enum ResetSubscriptionError: LocalizedError {
    case invalidSettings(String)
    case source(String)
    case analysis(String)

    var errorDescription: String? {
        switch self {
        case .invalidSettings(let message), .source(let message), .analysis(let message):
            return message
        }
    }
}

enum ResetSubscriptionPhase: String {
    case idle, fetching, analyzing
    var isBusy: Bool { self != .idle }
}

enum ResetEventKind: String, Codable { case regular, banked, unknown }
enum ResetEventStatus: String, Codable { case announced, scheduled, confirmed, forecast, unknown }
enum ResetEvidenceLevel: String, Codable { case announcement, observed, forecast, inference }

/// Facts supplied by a structured source; account state is deliberately separate.
struct ResetSourceEvent: Codable, Equatable {
    var id: String
    var kind: ResetEventKind
    var status: ResetEventStatus
    var text: String
    var sourceURL: URL
    var publishedAt: Date?
    var scheduledAt: Date?
    var timeDescription: String?
    var expiresAt: Date?
    var evidenceLevel: ResetEvidenceLevel
}

struct ResetSourceSnapshot: Codable, Equatable {
    var url: URL
    var fetchedAt: Date
    var text: String
    var fingerprint: String
    var event: ResetSourceEvent?
}

struct ResetServiceTier: Codable, Equatable, Identifiable {
    var id: String
    var name: String
}

struct ResetAnalysisModel: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var reasoningEfforts: [String]
    var serviceTiers: [ResetServiceTier]
    var defaultServiceTier: String?

    var fastTier: String? {
        serviceTiers.first {
            ["fast", "priority"].contains($0.id.lowercased())
                || $0.name.lowercased() == "fast"
        }?.id
    }
}

struct ResetUsageRecord: Codable, Equatable, Identifiable {
    var id: String // threadID/turnID; updates replace this record, never accumulate counters.
    var recordedAt: Date
    var model: String
    var serviceTier: String?
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var totalTokens: Int64
}

struct ResetAnalysisResult: Equatable {
    var title: String
    var summary: String
    var applicability: String?
    var kind: ResetEventKind
    var status: ResetEventStatus
    var scheduledAt: Date?
    var timeDescription: String?
    var evidence: String
    var timeEvidence: String?
    var usage: ResetUsageRecord?
}

struct ResetSubscriptionReport: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var fingerprint: String
    var title: String
    var summary: String
    var applicability: String?
    var kind: ResetEventKind
    var status: ResetEventStatus
    var evidenceLevel: ResetEvidenceLevel
    var evidence: String
    var sourceURL: URL
    var sourcePublishedAt: Date?
    var scheduledAt: Date?
    var timeDescription: String?
    var expiresAt: Date?
    var fetchedAt: Date
    var analyzedAt: Date?
    var model: String?
    var reasoningEffort: String?
    var fast = false
    var usage: ResetUsageRecord?

    /// Reaching a scheduled time is never evidence that execution occurred.
    func isAwaitingConfirmation(at now: Date = Date()) -> Bool {
        status == .scheduled && scheduledAt.map { $0 <= now } == true
    }

    func isExpired(at now: Date = Date()) -> Bool {
        status == .forecast && expiresAt.map { $0 <= now } == true
    }
}

enum ResetDateParser {
    // Only fully specified dates with an explicit, unambiguous zone can prove an
    // instant. Do not infer the machine's time zone or interpret words like "soon".
    private static let explicitDate = try! NSRegularExpression(
        pattern: #"(?<![A-Z0-9-])([0-9]{4})-([0-9]{2})-([0-9]{2})[T\h]+([0-9]{2}):([0-9]{2})(?::([0-9]{2})(\.[0-9]+)?)?\h*(Z|(?:UTC|GMT)(?:\h*[+-][0-9]{1,2}(?::?[0-9]{2})?)?|[+-][0-9]{2}:?[0-9]{2})(?![A-Z0-9:+-])(?!\h*[+-])(?!\.[0-9])"#,
        options: .caseInsensitive
    )

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func containsExplicitDate(_ evidence: String, matching target: Date?) -> Bool {
        guard let target else { return false }
        return explicitDate.matches(in: evidence, range: NSRange(evidence.startIndex..., in: evidence)).contains { match in
            func capture(_ index: Int) -> String? {
                Range(match.range(at: index), in: evidence).map { String(evidence[$0]) }
            }
            guard let year = capture(1).flatMap(Int.init), year > 0,
                  let month = capture(2).flatMap(Int.init),
                  let day = capture(3).flatMap(Int.init),
                  let hour = capture(4).flatMap(Int.init), hour < 24,
                  let minute = capture(5).flatMap(Int.init), minute < 60,
                  let zone = capture(8), let offset = zoneOffset(zone) else { return false }
            let second = capture(6).flatMap(Int.init) ?? 0
            guard second < 60 else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            guard let local = calendar.date(from: components) else { return false }
            // Calendar.date normalizes impossible dates such as February 30.
            let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: local)
            guard actual == components else { return false }
            let fraction = capture(7).flatMap(Double.init) ?? 0
            let instant = local.addingTimeInterval(fraction - TimeInterval(offset))
            return abs(instant.timeIntervalSince(target)) < 1
        }
    }

    private static func zoneOffset(_ value: String) -> Int? {
        var zone = value.uppercased().filter { !$0.isWhitespace }
        if zone == "Z" || zone == "UTC" || zone == "GMT" { return 0 }
        if zone.hasPrefix("UTC") || zone.hasPrefix("GMT") { zone.removeFirst(3) }
        let sign = zone.first == "-" ? -1 : 1
        let digits = String(zone.dropFirst()).replacingOccurrences(of: ":", with: "")
        let hours: Int?
        let minutes: Int?
        if digits.count <= 2 {
            hours = Int(digits)
            minutes = 0
        } else {
            hours = Int(digits.dropLast(2))
            minutes = Int(digits.suffix(2))
        }
        guard let hours, let minutes, hours < 24, minutes < 60 else { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }
}
