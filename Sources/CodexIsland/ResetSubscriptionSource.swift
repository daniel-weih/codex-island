import CryptoKit
import Foundation

enum ResetSubscriptionSource {
    static let maximumResponseBytes = 1_048_576
    static let maximumTextCharacters = 80_000
    private static let fetcher = ResetSourceFetcher()

    static func fetch(url: URL) async throws -> ResetSourceSnapshot {
        try await fetcher.fetch(url: url)
    }

    static func requestURL(for url: URL) throws -> URL {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else {
            throw ResetSubscriptionError.source("来源地址必须是完整的 HTTP(S) URL，且不能包含用户名或密码。")
        }
        if ["codex-resets.com", "www.codex-resets.com"].contains(url.host?.lowercased() ?? ""),
           url.path.isEmpty || url.path == "/" {
            return URL(string: "https://codex-resets.com/api/v1/status")!
        }
        return url
    }

    static func parse(
        data: Data,
        url: URL,
        contentType: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> ResetSourceSnapshot {
        guard data.count <= maximumResponseBytes else {
            throw ResetSubscriptionError.source("来源内容超过 1 MB，请配置具体的资讯或 API 地址。")
        }
        let isOfficial = ["codex-resets.com", "www.codex-resets.com"].contains(url.host?.lowercased() ?? "")
        let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var event: ResetSourceEvent?
        let text: String
        if let json {
            var content = json
            if isOfficial, let object = json as? [String: Any],
               let payload = object["data"] as? [String: Any],
               payload.keys.contains("latest_reset") {
                // Counters and generated_at change without a new announcement.
                var stable: [String: Any] = [:]
                for key in ["latest_reset", "scheduled_reset", "active_watch"] {
                    stable[key] = payload[key] ?? NSNull()
                }
                content = stable
                event = sourceEvent(payload: payload, fallbackURL: url, now: fetchedAt)
            }
            guard JSONSerialization.isValidJSONObject(content),
                  let canonical = try? JSONSerialization.data(withJSONObject: content, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let value = String(data: canonical, encoding: .utf8) else {
                throw ResetSubscriptionError.source("来源 JSON 必须包含对象或数组。")
            }
            text = value
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw ResetSubscriptionError.source("来源内容不是可读取的 UTF-8 文本。")
            }
            let type = contentType?.lowercased() ?? ""
            guard type.isEmpty || type.contains("text/") || type.contains("xml") || type.contains("html") else {
                throw ResetSubscriptionError.source("来源地址需要返回网页、RSS 或 JSON 内容。")
            }
            text = plainText(decoded)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResetSubscriptionError.source("来源页面没有可分析的正文，可能需要登录或由 JavaScript 加载。")
        }
        guard text.count <= maximumTextCharacters else {
            // Do not silently truncate an event time or the evidence supporting it.
            throw ResetSubscriptionError.source("正文超过 80,000 字符，请配置更具体的资讯或 API 地址。")
        }
        // A watch expiring can change the selected event even if the API body is cached.
        let selectedEvent = event.map { "\($0.id):\($0.status.rawValue)" } ?? "none"
        let fingerprintInput = url.absoluteString + "\n" + text + "\n" + selectedEvent
        let fingerprint = SHA256.hash(data: Data(fingerprintInput.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return ResetSourceSnapshot(url: url, fetchedAt: fetchedAt, text: text, fingerprint: fingerprint, event: event)
    }

    static func sourceEvent(payload: [String: Any], fallbackURL: URL, now: Date) -> ResetSourceEvent? {
        if let scheduled = payload["scheduled_reset"] as? [String: Any] {
            return event(from: scheduled, fallbackURL: fallbackURL, status: .scheduled, evidence: .announcement)
        }
        if let watch = payload["active_watch"] as? [String: Any],
           let expiresAt = ResetDateParser.date(watch["expires_at"] as? String), expiresAt > now {
            return event(from: watch, fallbackURL: fallbackURL, status: .forecast, evidence: .forecast)
        }
        if let latest = payload["latest_reset"] as? [String: Any] {
            let source = latest["source"] as? [String: Any]
            let isBanked = latest["reset_type"] as? String == "banked"
            return event(from: latest, fallbackURL: fallbackURL,
                         status: isBanked ? .announced : .confirmed,
                         evidence: source?["type"] as? String == "observed" ? .observed : .announcement)
        }
        return nil
    }

    private static func event(
        from value: [String: Any], fallbackURL: URL,
        status: ResetEventStatus, evidence: ResetEvidenceLevel
    ) -> ResetSourceEvent {
        let source = value["source"] as? [String: Any]
        let safeURL = (source?["url"] as? String).flatMap(URL.init(string:)).flatMap { candidate in
            ["http", "https"].contains(candidate.scheme?.lowercased() ?? "")
                && candidate.host?.isEmpty == false && candidate.user == nil && candidate.password == nil ? candidate : nil
        }
        let text = value["text"] as? String ?? ""
        return ResetSourceEvent(
            id: value["id"] as? String ?? "forecast-\(value["observed_at"] as? String ?? "unknown")",
            kind: ResetEventKind(rawValue: value["reset_type"] as? String ?? "") ?? .unknown,
            status: status, text: text, sourceURL: safeURL ?? fallbackURL,
            publishedAt: ResetDateParser.date(value["announced_at"] as? String ?? value["observed_at"] as? String),
            scheduledAt: status == .scheduled ? ResetDateParser.date(value["scheduled_for"] as? String) : nil,
            timeDescription: value["forecast_window"] as? String,
            expiresAt: ResetDateParser.date(value["expires_at"] as? String),
            evidenceLevel: evidence
        )
    }

    static func plainText(_ html: String) -> String {
        var value = html
        for pattern in ["(?is)<!--.*?-->", "(?is)<(script|style|noscript|svg)\\b[^>]*>.*?</\\1\\s*>", "(?is)<[^>]+>"] {
            value = value.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        for (entity, replacement) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);") {
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: value),
                      let fullRange = Range(match.range, in: value) else { continue }
                let number = String(value[numberRange])
                let code = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                if let code, let scalar = UnicodeScalar(code) { value.replaceSubrange(fullRange, with: String(scalar)) }
            }
        }
        return value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor ResetSourceFetcher {
    private struct CachedResponse {
        var data: Data
        var contentType: String?
        var etag: String?
    }
    private let session: URLSession
    private var responses: [URL: CachedResponse] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
    }

    func fetch(url: URL) async throws -> ResetSourceSnapshot {
        let endpoint = try ResetSubscriptionSource.requestURL(for: url)
        var request = URLRequest(url: endpoint)
        request.setValue("application/json, text/html, application/rss+xml, text/plain;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland/1.0 (reset subscription)", forHTTPHeaderField: "User-Agent")
        if let etag = responses[endpoint]?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else {
                throw ResetSubscriptionError.source("来源地址没有返回 HTTP 响应。")
            }
            guard let finalURL = http.url,
                  ["http", "https"].contains(finalURL.scheme?.lowercased() ?? "") else {
                throw ResetSubscriptionError.source("来源地址跳转到了不支持的协议。")
            }
            if http.statusCode == 304, let cached = responses[endpoint] {
                return try ResetSubscriptionSource.parse(data: cached.data, url: url, contentType: cached.contentType)
            }
            guard (200..<300).contains(http.statusCode) else {
                let suffix = http.statusCode == 429 ? "，请求过于频繁，稍后会自动重试" : ""
                throw ResetSubscriptionError.source("获取动态失败（HTTP \(http.statusCode)）\(suffix)。")
            }
            guard response.expectedContentLength <= Int64(ResetSubscriptionSource.maximumResponseBytes) else {
                throw ResetSubscriptionError.source("来源内容超过 1 MB，请配置具体的资讯或 API 地址。")
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < ResetSubscriptionSource.maximumResponseBytes else {
                    throw ResetSubscriptionError.source("来源内容超过 1 MB，请配置具体的资讯或 API 地址。")
                }
                data.append(byte)
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")
            let snapshot = try ResetSubscriptionSource.parse(data: data, url: url, contentType: contentType)
            if responses.count >= 8, responses[endpoint] == nil { responses.removeAll() }
            responses[endpoint] = CachedResponse(data: data, contentType: contentType, etag: http.value(forHTTPHeaderField: "ETag"))
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ResetSubscriptionError {
            throw error
        } catch {
            throw ResetSubscriptionError.source("获取动态失败：\(error.localizedDescription)")
        }
    }
}
