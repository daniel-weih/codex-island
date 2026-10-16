import Foundation

enum CodexThreadSettingsReaderError: LocalizedError {
    case invalidRolloutPath

    var errorDescription: String? {
        "会话记录路径不在 Codex 数据目录中"
    }
}

/// Reads task-level settings from a rollout without decoding message or tool payloads.
enum CodexThreadSettingsReader {
    private static let chunkSize = 64 * 1024
    private static let threadSettingsMarker = Data("thread_settings_applied".utf8)
    private static let turnContextMarker = Data("turn_context".utf8)
    private static let cache = SettingsCache()

    static func readLatest(
        from rolloutPath: String,
        threadID: String? = nil,
        validatePath: Bool = true
    ) throws -> ThreadRuntimeSettings? {
        let url = try rolloutURL(
            from: rolloutPath,
            threadID: threadID,
            validatePath: validatePath
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let fileIdentity = [
            (attributes[.systemNumber] as? NSNumber)?.stringValue,
            (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        ]
        .compactMap { $0 }
        .joined(separator: ":")

        if let cached = cache.entry(for: url.path),
           cached.fileIdentity == fileIdentity,
           cached.fileSize == fileSize,
           cached.modifiedAt == modifiedAt {
            return cached.settings
        }

        let previous = cache.entry(for: url.path)
        let isAppendingToSameFile = previous?.fileIdentity == fileIdentity
            && fileSize > (previous?.fileSize ?? fileSize)
        let lowerBound: UInt64
        if isAppendingToSameFile, let previous {
            // Re-read an unfinished record from its exact start, even when it
            // spans multiple chunks. Completed records are already in the cache.
            lowerBound = min(previous.trailingLineStartOffset ?? previous.fileSize, previous.fileSize)
        } else {
            lowerBound = 0
        }

        let newlyRead = try scanBackwards(
            url: url,
            fileSize: fileSize,
            lowerBound: lowerBound
        )
        let resolved: ThreadRuntimeSettings?
        if isAppendingToSameFile,
           let previousSettings = previous?.settings,
           let newlyRead {
            resolved = ThreadRuntimeSettings(
                model: newlyRead.model ?? previousSettings.model,
                reasoningEffort: newlyRead.hasRecordedReasoningEffort
                    ? newlyRead.reasoningEffort : previousSettings.reasoningEffort,
                serviceTier: newlyRead.serviceTier ?? previousSettings.serviceTier,
                hasRecordedReasoningEffort: newlyRead.hasRecordedReasoningEffort
                    || previousSettings.hasRecordedReasoningEffort
            )
        } else {
            resolved = newlyRead ?? (isAppendingToSameFile ? previous?.settings : nil)
        }
        cache.store(
            CacheEntry(
                fileIdentity: fileIdentity,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                settings: resolved,
                trailingLineStartOffset: try findTrailingLineStartOffset(url: url, fileSize: fileSize)
            ),
            for: url.path
        )
        return resolved
    }

    private static func findTrailingLineStartOffset(url: URL, fileSize: UInt64) throws -> UInt64? {
        guard fileSize > 0 else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: fileSize - 1)
        if try handle.read(upToCount: 1)?.first == 0x0A { return nil }

        var position = fileSize
        while position > 0 {
            let readCount = min(chunkSize, Int(position))
            position -= UInt64(readCount)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            if let newline = chunk.lastIndex(of: 0x0A) {
                return position + UInt64(newline) + 1
            }
        }
        return 0
    }

    private static func scanBackwards(
        url: URL,
        fileSize: UInt64,
        lowerBound: UInt64
    ) throws -> ThreadRuntimeSettings? {
        var latest: ThreadRuntimeSettings?

        func mergeOlder(_ older: ThreadRuntimeSettings?) -> Bool {
            guard let older else { return false }
            // Both event types can update only some fields. Scan newest-first
            // and let earlier records fill only fields that are still unknown.
            let merged = ThreadRuntimeSettings(
                model: latest?.model ?? older.model,
                reasoningEffort: latest?.hasRecordedReasoningEffort == true
                    ? latest?.reasoningEffort : older.reasoningEffort,
                serviceTier: latest?.serviceTier ?? older.serviceTier,
                hasRecordedReasoningEffort: latest?.hasRecordedReasoningEffort == true
                    || older.hasRecordedReasoningEffort
            )
            latest = merged
            return merged.model != nil
                && merged.hasRecordedReasoningEffort
                && merged.serviceTier != nil
        }

        try CodexRolloutLineReader.scanBackwards(url: url, from: lowerBound, to: fileSize) { line in
            mergeOlder(parseThreadSettings(line) ?? parseTurnContext(line))
        }
        return latest
    }

    private static func parseThreadSettings<D: DataProtocol>(
        _ line: D
    ) -> ThreadRuntimeSettings? {
        let data = Data(line)
        guard data.range(of: threadSettingsMarker) != nil,
              let object = jsonObject(data),
              object.string("type") == "event_msg",
              let payload = object.dictionary("payload"),
              payload.string("type") == "thread_settings_applied",
              let settings = payload.dictionary("thread_settings") else {
            return nil
        }

        return runtimeSettings(
            model: settings.string("model"),
            reasoningEffort: settings.string("reasoning_effort"),
            serviceTier: recordedServiceTier(in: settings, isSettingsSnapshot: true),
            hasRecordedReasoningEffort: settings["reasoning_effort"] != nil
                || isCompleteSettingsSnapshot(settings)
        )
    }

    private static func parseTurnContext<D: DataProtocol>(
        _ line: D
    ) -> ThreadRuntimeSettings? {
        let data = Data(line)
        guard data.range(of: turnContextMarker) != nil,
              let object = jsonObject(data),
              object.string("type") == "turn_context",
              let payload = object.dictionary("payload") else {
            return nil
        }

        return runtimeSettings(
            model: payload.string("model"),
            reasoningEffort: payload["effort"] != nil
                ? payload.string("effort") : payload.string("reasoning_effort"),
            serviceTier: recordedServiceTier(in: payload),
            hasRecordedReasoningEffort: payload["effort"] != nil || payload["reasoning_effort"] != nil
        )
    }

    private static func runtimeSettings(
        model: String?,
        reasoningEffort: String?,
        serviceTier: String?,
        hasRecordedReasoningEffort: Bool
    ) -> ThreadRuntimeSettings? {
        guard model != nil || hasRecordedReasoningEffort || serviceTier != nil else { return nil }
        return ThreadRuntimeSettings(
            model: model,
            reasoningEffort: reasoningEffort,
            serviceTier: serviceTier,
            hasRecordedReasoningEffort: hasRecordedReasoningEffort
        )
    }

    /// Codex's full ThreadSettingsSnapshot omits default optional fields during
    /// serialization. Partial historical events still leave omitted fields alone.
    private static func isCompleteSettingsSnapshot(_ settings: JSONObject) -> Bool {
        settings.string("model") != nil && settings.string("model_provider_id") != nil
            && settings.string("cwd") != nil && settings["approval_policy"] != nil
    }

    static func recordedServiceTier(in settings: JSONObject, isSettingsSnapshot: Bool = false) -> String? {
        if settings["service_tier"] is NSNull { return "default" }
        if let tier = settings.string("service_tier") { return tier }
        if settings["service_tier"] == nil, isSettingsSnapshot, isCompleteSettingsSnapshot(settings) {
            return "default"
        }
        return nil
    }

    private static func jsonObject(_ line: Data) -> JSONObject? {
        guard !line.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: line) as? JSONObject
    }

    static func rolloutURL(
        from rolloutPath: String,
        threadID: String?,
        validatePath: Bool
    ) throws -> URL {
        let expandedPath = (rolloutPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard validatePath else { return url }

        let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { ($0 as NSString).expandingTildeInPath }
        let codexHome = URL(fileURLWithPath: configuredHome
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true).path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let allowedRoots = ["sessions", "archived_sessions"].map {
            codexHome.appendingPathComponent($0, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
        let isInsideCodexData = allowedRoots.contains { root in
            url.path.hasPrefix(root.path + "/")
        }
        let matchesThread = threadID.map { id in
            id.isEmpty || url.lastPathComponent.contains(id)
        } ?? true
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])

        guard isInsideCodexData,
              matchesThread,
              url.pathExtension.lowercased() == "jsonl",
              values.isRegularFile == true else {
            throw CodexThreadSettingsReaderError.invalidRolloutPath
        }
        return url
    }
}

private struct CacheEntry {
    var fileIdentity: String
    var fileSize: UInt64
    var modifiedAt: Date
    var settings: ThreadRuntimeSettings?
    var trailingLineStartOffset: UInt64?
}

private final class SettingsCache: @unchecked Sendable {
    private let maximumEntryCount = 32
    private let lock = NSLock()
    private var entries: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []

    func entry(for path: String) -> CacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path] else { return nil }
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)
        return entry
    }

    func store(_ entry: CacheEntry, for path: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[path] = entry
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)
        while accessOrder.count > maximumEntryCount {
            let evictedPath = accessOrder.removeFirst()
            entries.removeValue(forKey: evictedPath)
        }
    }
}
