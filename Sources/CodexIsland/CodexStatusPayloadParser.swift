import Foundation

enum CodexStatusPayloadParser {
    static func parseAccount(_ result: JSONObject) -> AccountSummary {
        let account = result.dictionary("account")
        return AccountSummary(
            authType: account?.string("type"),
            planType: account?.string("planType"),
            requiresOpenAIAuth: result.bool("requiresOpenaiAuth") ?? false
        )
    }

    static func parseRateLimits(_ result: JSONObject) -> (
        bucket: RateLimitBucket?,
        resetCredits: ResetCreditSummary?
    ) {
        let bucketJSON = preferredRateLimitBucket(in: result)
        let bucket = bucketJSON.map { payload in
            RateLimitBucket(
                id: payload.string("limitId") ?? "codex",
                name: payload.string("limitName"),
                planType: payload.string("planType"),
                primary: parseWindow(payload.dictionary("primary")),
                secondary: parseWindow(payload.dictionary("secondary")),
                reachedType: payload.string("rateLimitReachedType")
            )
        }

        let creditsJSON = result.dictionary("rateLimitResetCredits")
        let credits: ResetCreditSummary?
        if let creditsJSON {
            let rows = creditsJSON.array("credits")?.compactMap { $0 as? JSONObject } ?? []
            // Older payloads may omit `status`; keep those rows for backward
            // compatibility, but never count explicitly used/expired credits.
            let availableRows = rows.filter { row in
                guard let status = row.string("status") else { return true }
                return status.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "available"
            }
            let expirations = availableRows.compactMap { row in
                row.unixDate("expiresAt")
            }
            .sorted()
            let reportedCount = max(0, creditsJSON.int("availableCount") ?? 0)
            let availableCount = creditsJSON.int("availableCount") == nil
                ? availableRows.count
                : max(reportedCount, availableRows.count)
            credits = ResetCreditSummary(
                availableCount: availableCount,
                earliestExpiration: expirations.first,
                expirationDates: expirations
            )
        } else {
            credits = nil
        }

        return (bucket, credits)
    }

    static func parseUsage(_ result: JSONObject) -> UsageSummary {
        let summary = result.dictionary("summary")
        let dailyUsageBuckets = result.array("dailyUsageBuckets")?
            .compactMap { item -> DailyUsageBucket? in
                guard let row = item as? JSONObject,
                      let startDate = row.string("startDate"),
                      let tokens = row.int64("tokens") else {
                    return nil
                }
                return DailyUsageBucket(
                    startDate: startDate,
                    tokens: max(0, tokens)
                )
            }
            .sorted(by: { $0.startDate < $1.startDate })
            ?? []

        return UsageSummary(
            lifetimeTokens: summary?.int64("lifetimeTokens"),
            peakDailyTokens: summary?.int64("peakDailyTokens"),
            longestRunningTurnSeconds: summary?.int("longestRunningTurnSec"),
            currentStreakDays: summary?.int("currentStreakDays"),
            longestStreakDays: summary?.int("longestStreakDays"),
            dailyUsageBuckets: dailyUsageBuckets
        )
    }

    static func parseLatestThread(_ result: JSONObject) -> ThreadSummary? {
        parseRecentThreads(result, limit: 1).first
    }

    static func parseRecentThreads(
        _ result: JSONObject,
        limit: Int = 5
    ) -> [ThreadSummary] {
        guard limit > 0 else { return [] }
        let payloads = result.array("data")?
            .compactMap { $0 as? JSONObject }
            .prefix(limit)
            ?? []
        var fallbackIDOccurrences: [String: Int] = [:]

        return payloads.map { payload in
            if let id = explicitThreadID(in: payload) {
                return parseThread(payload, id: id)
            }

            let baseID = fallbackThreadID(for: payload)
            let occurrence = fallbackIDOccurrences[baseID, default: 0]
            fallbackIDOccurrences[baseID] = occurrence + 1
            let uniqueID = occurrence == 0 ? baseID : "\(baseID)-\(occurrence + 1)"
            return parseThread(payload, id: uniqueID)
        }
    }

    static func parseDefaultModel(_ result: JSONObject) -> ModelSummary? {
        let models = result.array("data")?.compactMap { $0 as? JSONObject } ?? []
        let selected = models.first(where: { $0.bool("isDefault") == true }) ?? models.first
        guard let selected, let id = selected.string("id") ?? selected.string("model") else { return nil }
        return ModelSummary(
            id: id,
            displayName: selected.string("displayName") ?? id,
            isDefault: selected.bool("isDefault") ?? false
        )
    }

    /// Resolves the service tier Codex would currently apply for a task directory.
    /// A missing tier means Standard mode; a disabled Fast feature also forces Standard.
    static func parseEffectiveServiceTier(_ result: JSONObject) -> String? {
        guard let config = result.dictionary("config") else { return nil }
        if config.dictionary("features")?.bool("fast_mode") == false {
            return "default"
        }
        return config.string("service_tier") ?? "default"
    }

    private static func parseWindow(_ payload: JSONObject?) -> RateLimitWindow? {
        guard let payload, let usedPercent = payload.double("usedPercent") else { return nil }
        return RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: payload.int("windowDurationMins"),
            resetsAt: payload.unixDate("resetsAt")
        )
    }

    private static func parseThread(_ payload: JSONObject, id: String) -> ThreadSummary {
        let status = payload.dictionary("status")?.string("type") ?? "unknown"
        let title = payload.string("name")
            ?? payload.string("preview")
            ?? "未命名会话"
        let serviceTier = payload.string("serviceTier") ?? payload.string("service_tier")

        return ThreadSummary(
            id: id,
            title: title,
            status: status,
            clientSource: parseThreadClientSource(payload),
            model: payload.string("model"),
            reasoningEffort: nil,
            serviceTier: serviceTier,
            serviceTierSource: serviceTier == nil ? nil : .recorded,
            tokenUsage: nil,
            executionState: .unknown,
            cwd: payload.string("cwd"),
            rolloutPath: payload.string("path"),
            updatedAt: payload.unixDate("updatedAt")
        )
    }

    /// `thread/list` uses the historical `vscode` source for Codex Desktop.
    /// Keep every other SessionSource unlabelled instead of guessing its UI.
    private static func parseThreadClientSource(
        _ payload: JSONObject
    ) -> ThreadClientSource? {
        switch payload.string("source")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "cli": return .tui
        case "vscode": return .app
        default: return nil
        }
    }

    private static func explicitThreadID(in payload: JSONObject) -> String? {
        for key in ["id", "threadId", "thread_id", "sessionId", "session_id"] {
            if let id = payload.string(key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !id.isEmpty {
                return id
            }
        }
        return nil
    }

    /// Produces a deterministic synthetic identity for older thread-list payloads
    /// that omit every supported ID field. Prefer the rollout path because it is
    /// stable when mutable metadata such as the title, status, or updated time
    /// changes. The caller adds a deterministic occurrence suffix only when the
    /// same fallback identity appears more than once in a response.
    private static func fallbackThreadID(for payload: JSONObject) -> String {
        let path = ["path", "rolloutPath", "rollout_path"]
            .lazy
            .compactMap { payload.string($0) }
            .first

        let seed: String
        if let path {
            seed = encodedFallbackField("path", path)
        } else {
            let fields: [(String, String?)] = [
                ("createdAt", timestampSeed(payload, keys: ["createdAt", "created_at"])),
                ("cwd", payload.string("cwd")),
                ("name", payload.string("name")),
                ("preview", payload.string("preview")),
                ("model", payload.string("model")),
                ("updatedAt", timestampSeed(payload, keys: ["updatedAt", "updated_at"])),
                ("status", payload.dictionary("status")?.string("type"))
            ]
            seed = fields
                .map { encodedFallbackField($0.0, $0.1 ?? "") }
                .joined(separator: "|")
        }

        return "fallback-\(stableHash(seed))"
    }

    private static func timestampSeed(_ payload: JSONObject, keys: [String]) -> String? {
        for key in keys {
            if let value = payload.double(key), value.isFinite {
                return String(value.bitPattern, radix: 16)
            }
        }
        return nil
    }

    private static func encodedFallbackField(_ key: String, _ value: String) -> String {
        "\(key):\(value.utf8.count):\(value)"
    }

    /// FNV-1a has fixed cross-process behavior, unlike Swift's randomized Hasher.
    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hexadecimal = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hexadecimal.count) + hexadecimal
    }

    private static func preferredRateLimitBucket(in result: JSONObject) -> JSONObject? {
        if let buckets = result.dictionary("rateLimitsByLimitId") {
            if let codex = buckets["codex"] as? JSONObject { return codex }
            if let exact = buckets.values
                .compactMap({ $0 as? JSONObject })
                .first(where: { $0.string("limitId")?.lowercased() == "codex" }) {
                return exact
            }
            if let firstCodex = buckets
                .sorted(by: { $0.key < $1.key })
                .first(where: { $0.key.lowercased().contains("codex") })?.value as? JSONObject {
                return firstCodex
            }
        }
        return result.dictionary("rateLimits")
    }
}

extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> JSONObject? {
        self[key] as? JSONObject
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func string(_ key: String) -> String? {
        if let value = self[key] as? String, !value.isEmpty { return value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let value = self[key] as? Int64 { return value }
        if let value = self[key] as? NSNumber { return value.int64Value }
        if let value = self[key] as? String { return Int64(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? NSNumber { return value.doubleValue }
        if let value = self[key] as? String { return Double(value) }
        return nil
    }

    func unixDate(_ key: String) -> Date? {
        guard let seconds = double(key), seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
