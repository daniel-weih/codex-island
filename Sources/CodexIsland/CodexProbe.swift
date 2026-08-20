import Darwin
import Foundation

enum CodexProbe {
    static func run() async -> Int32 {
        let client = CodexAppServerClient()
        defer { client.stop() }

        do {
            try await client.start()
            print("connection=ok")

            let accountResult = try await client.request(
                method: "account/read",
                params: ["refreshToken": false]
            )
            let account = CodexStatusPayloadParser.parseAccount(accountResult)
            print("account=\(account.authType == nil ? "authentication_required" : "available")")
            print("plan=\(account.planType ?? "unknown")")

            let limitsResult = try await client.request(method: "account/rateLimits/read")
            let limits = CodexStatusPayloadParser.parseRateLimits(limitsResult)
            print("primary_quota=\(limits.bucket?.primary == nil ? "unavailable" : "available")")
            print("secondary_quota=\(limits.bucket?.secondary == nil ? "unavailable" : "available")")
            print("reset_credits=\(limits.resetCredits?.availableCount.description ?? "unavailable")")
            if let resets = limits.resetCredits {
                print("reset_expirations=\(resets.expirationDates.count)/\(resets.availableCount)")
            }

            let usageResult = try await client.request(method: "account/usage/read")
            let usage = CodexStatusPayloadParser.parseUsage(usageResult)
            print("usage=\(usage.lifetimeTokens == nil ? "unavailable" : "available")")
            print("daily_usage=\(usage.dailyUsageBuckets.isEmpty ? "unavailable" : "available")")

            let authResult = try? await client.request(
                method: "getAuthStatus",
                params: ["includeToken": true, "refreshToken": false]
            )
            let profileResult = await CodexProfileIdentityProvider.load(
                authToken: authResult?.string("authToken")
            )
            print("profile_identity=\(profileResult.isRemoteProfile ? "remote" : "fallback")")
            print("profile_avatar=\(profileResult.identity.avatarData == nil ? "unavailable" : "available")")

            let threadResult = try await client.request(
                method: "thread/list",
                params: [
                    "limit": CodexDisplayPolicy.recentThreadFetchLimit,
                    "sortKey": "recency_at",
                    "sortDirection": "desc",
                    "archived": false,
                    "sourceKinds": ["cli", "vscode"],
                    "useStateDbOnly": true
                ]
            )
            let threads = CodexStatusPayloadParser.parseRecentThreads(
                threadResult,
                limit: CodexDisplayPolicy.recentThreadFetchLimit
            )
            print("recent_threads=\(threads.count)")
            let configuredCount = threads.reduce(into: 0) { count, thread in
                guard let path = thread.rolloutPath else { return }
                guard (try? CodexThreadSettingsReader.readLatest(
                        from: path,
                        threadID: thread.id
                      )) != nil else { return }
                count += 1
            }
            print("thread_configurations=\(configuredCount)/\(threads.count)")
            var activityCounts: [String: Int] = [:]
            for thread in threads {
                guard let path = thread.rolloutPath,
                      let activity = try? CodexThreadActivityReader.readLatest(
                        from: path,
                        threadID: thread.id
                      ) else { continue }
                let label: String
                switch activity.executionState {
                case .running: label = "running"
                case .idle: label = "idle"
                case .interrupted: label = "interrupted"
                case .failed: label = "failed"
                case .unknown: label = "unknown"
                }
                activityCounts[label, default: 0] += 1
            }
            let activitySummary = activityCounts
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            print("thread_activity=\(activitySummary)")
            return EXIT_SUCCESS
        } catch {
            fputs("probe_error=\(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }
}
