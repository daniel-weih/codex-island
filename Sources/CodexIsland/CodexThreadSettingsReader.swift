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
    private static let turnContextMarker = Data("\"type\":\"turn_context\"".utf8)
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
        let fileIdentity = [
            (attributes[.systemNumber] as? NSNumber)?.stringValue,
            (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        ]
        .compactMap { $0 }
        .joined(separator: ":")

        if let cached = cache.entry(for: url.path),
           cached.fileIdentity == fileIdentity,
           cached.fileSize == fileSize {
            return cached.settings
        }

        let previous = cache.entry(for: url.path)
        let isAppendingToSameFile = previous?.fileIdentity == fileIdentity
            && fileSize > (previous?.fileSize ?? fileSize)
        let lowerBound: UInt64
        if isAppendingToSameFile, let previous {
            // Include one full settings-sized overlap in case the prior read
            // observed a JSONL record while it was still being appended.
            lowerBound = previous.fileSize > UInt64(chunkSize)
                ? previous.fileSize - UInt64(chunkSize)
                : 0
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
                reasoningEffort: newlyRead.reasoningEffort ?? previousSettings.reasoningEffort,
                serviceTier: newlyRead.serviceTier ?? previousSettings.serviceTier
            )
        } else {
            resolved = newlyRead ?? (isAppendingToSameFile ? previous?.settings : nil)
        }
        cache.store(
            CacheEntry(
                fileIdentity: fileIdentity,
                fileSize: fileSize,
                settings: resolved
            ),
            for: url.path
        )
        return resolved
    }

    private static func scanBackwards(
        url: URL,
        fileSize: UInt64,
        lowerBound: UInt64
    ) throws -> ThreadRuntimeSettings? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var position = fileSize
        var carry = Data()
        var turnContextFallback: ThreadRuntimeSettings?

        while position > lowerBound {
            let readCount = min(chunkSize, Int(position - lowerBound))
            guard readCount > 0 else { break }

            position -= UInt64(readCount)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            guard !chunk.isEmpty else { break }

            var block = Data(capacity: chunk.count + carry.count)
            block.append(chunk)
            block.append(carry)

            let lines = block.split(separator: 0x0A, omittingEmptySubsequences: false)
            guard lines.count > 1 else {
                carry = block
                continue
            }

            // The first item may start in the preceding block. Every later item
            // is a complete JSONL record, so inspect them newest-first.
            carry = Data(lines[0])
            for line in lines.dropFirst().reversed() {
                if let settings = parseThreadSettings(line) {
                    return settings
                }
                if turnContextFallback == nil {
                    turnContextFallback = parseTurnContext(line)
                }
            }
        }

        // At file start this is certainly a complete line. At an incremental
        // boundary strict JSON decoding safely rejects a truncated prefix.
        if !carry.isEmpty {
            if let settings = parseThreadSettings(carry) {
                return settings
            }
            if turnContextFallback == nil {
                turnContextFallback = parseTurnContext(carry)
            }
        }
        return turnContextFallback
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
            serviceTier: settings.string("service_tier")
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
            reasoningEffort: payload.string("effort") ?? payload.string("reasoning_effort"),
            serviceTier: payload.string("service_tier")
        )
    }

    private static func runtimeSettings(
        model: String?,
        reasoningEffort: String?,
        serviceTier: String?
    ) -> ThreadRuntimeSettings? {
        guard model != nil || reasoningEffort != nil || serviceTier != nil else { return nil }
        return ThreadRuntimeSettings(
            model: model,
            reasoningEffort: reasoningEffort,
            serviceTier: serviceTier
        )
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
    var settings: ThreadRuntimeSettings?
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
