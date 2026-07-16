import Foundation
import ImageIO

struct ProfileIdentityLoadResult {
    var identity: ProfileIdentitySummary
    var isRemoteProfile: Bool
    var authorizationRejected: Bool
    var retrySoon: Bool
}

enum CodexProfileIdentityProvider {
    static func load(authToken: String?) async -> ProfileIdentityLoadResult {
        let fallback = ProfileIdentitySummary.empty

        guard let authToken, !authToken.isEmpty else {
            return ProfileIdentityLoadResult(
                identity: fallback,
                isRemoteProfile: false,
                authorizationRejected: false,
                retrySoon: true
            )
        }

        let remoteResult = await fetchRemoteProfile(authToken: authToken)
        guard case .success(let remoteProfile) = remoteResult else {
            let authorizationRejected: Bool
            if case .unauthorized = remoteResult {
                authorizationRejected = true
            } else {
                authorizationRejected = false
            }
            return ProfileIdentityLoadResult(
                identity: fallback,
                isRemoteProfile: false,
                authorizationRejected: authorizationRejected,
                retrySoon: true
            )
        }
        var identity = fallback
        if let displayName = normalized(remoteProfile.displayName) {
            identity.displayName = displayName
        }
        var avatarDownloadFailed = false
        if let avatarURL = remoteProfile.avatarURL {
            if let avatarData = await downloadAvatar(from: avatarURL) {
                identity.avatarData = avatarData
            } else {
                avatarDownloadFailed = true
            }
        }
        return ProfileIdentityLoadResult(
            identity: identity,
            isRemoteProfile: true,
            authorizationRejected: false,
            retrySoon: avatarDownloadFailed
        )
    }

    private struct RemoteProfile {
        var displayName: String?
        var avatarURL: URL?
    }

    private enum RemoteProfileResult {
        case success(RemoteProfile)
        case unauthorized
        case unavailable
    }

    private static func tokenPayload(_ token: String) -> JSONObject? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var encoded = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? JSONObject
    }

    private static func accountID(from authToken: String) -> String? {
        guard let payload = tokenPayload(authToken) else { return nil }
        return payload.dictionary("https://api.openai.com/auth")?
            .string("chatgpt_account_id")
            ?? payload.string("chatgpt_account_id")
    }

    private static func fetchRemoteProfile(authToken: String) async -> RemoteProfileResult {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/profiles/me") else {
            return .unavailable
        }
        guard let accountID = accountID(from: authToken) else { return .unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return .unavailable
        }
        if httpResponse.statusCode == 401 { return .unauthorized }
        guard httpResponse.statusCode == 200,
              data.count <= 2 * 1_024 * 1_024,
              let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject,
              let profile = root.dictionary("profile") else {
            return .unavailable
        }
        let avatarURL = profile.string("profile_picture_url").flatMap(URL.init(string:))
        return .success(RemoteProfile(
            displayName: profile.string("display_name"),
            avatarURL: avatarURL
        ))
    }

    private static func downloadAvatar(from url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              httpResponse.url?.scheme?.lowercased() == "https",
              httpResponse.expectedContentLength <= 0
                || httpResponse.expectedContentLength <= 5 * 1_024 * 1_024,
              data.count <= 5 * 1_024 * 1_024,
              isReasonableAvatarImage(data) else {
            return nil
        }
        return data
    }

    private static func isReasonableAvatarImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) <= 100,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0,
              height > 0,
              width <= 8_192,
              height <= 8_192,
              width * height <= 40_000_000 else {
            return false
        }
        return true
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
