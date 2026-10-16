import Foundation
import SQLite3

/// Older TUI rollouts omit the tier, but request feedback records it by thread.
/// Read only a bounded tail through Codex's existing thread/time index. Missing
/// logs or an unsupported schema leave the tier unknown; shared config is not
/// evidence of another running TUI's settings.
enum CodexThreadServiceTierReader {
    private static let maximumRows = 128
    private static let maximumBodyBytes = 64 * 1024

    static func fillingMissing(
        in threads: [ThreadSummary], from databaseURL: URL? = nil
    ) -> [ThreadSummary] {
        let missingIDs = threads.filter { $0.serviceTier == nil }.map(\.id)
        guard !missingIDs.isEmpty else { return threads }
        let tiers = readLatest(for: missingIDs, from: databaseURL)
        var resolved = threads
        for index in resolved.indices where resolved[index].serviceTier == nil {
            guard let tier = tiers[resolved[index].id] else { continue }
            resolved[index].serviceTier = tier
            resolved[index].serviceTierSource = .runtimeLog
        }
        return resolved
    }

    static func readLatest(
        for threadIDs: [String], from databaseURL: URL? = nil
    ) -> [String: String] {
        guard !threadIDs.isEmpty else { return [:] }
        let url = databaseURL ?? defaultDatabaseURL
        // This database is optional; never create one for older Codex installs.
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { sqlite3_close(database) }
        guard status == SQLITE_OK, let database else { return [:] }
        sqlite3_busy_timeout(database, 20)

        // INDEXED BY deliberately rejects schemas without the supporting index
        // instead of falling back to a scan of the potentially large log DB.
        let query = """
            SELECT CASE WHEN target = 'feedback_tags'
                THEN substr(CAST(feedback_log_body AS BLOB), 1, \(maximumBodyBytes)) END
            FROM logs INDEXED BY idx_logs_thread_id_ts
            WHERE thread_id = ?
            ORDER BY ts DESC, ts_nanos DESC, id DESC LIMIT \(maximumRows)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [:] }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var tiers: [String: String] = [:]
        for id in Set(threadIDs) where !id.isEmpty {
            sqlite3_reset(statement)
            guard sqlite3_bind_text(statement, 1, id, -1, transient) == SQLITE_OK else { continue }
            while sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_bytes(statement, 0))
                guard count > 0, count <= maximumBodyBytes,
                      let bytes = sqlite3_column_blob(statement, 0),
                      let body = String(data: Data(bytes: bytes, count: count), encoding: .utf8),
                      let marker = body.range(of: "tags_json=", options: .literal),
                      let tags = try? JSONSerialization.jsonObject(
                        with: Data(body[marker.upperBound...].utf8)
                      ) as? [String: Any],
                      let value = tags["service_tier"] else { continue }
                if let rawTier = value as? String {
                    let tier = rawTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if ["default", "standard", "priority", "fast", "flex"].contains(tier) {
                        tiers[id] = tier
                    }
                }
                // A newer unknown value must not resurrect an older Fast state.
                break
            }
        }
        return tiers
    }

    private static var defaultDatabaseURL: URL {
        let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { ($0 as NSString).expandingTildeInPath }
        let home = configuredHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("logs_2.sqlite")
    }
}
