import Foundation

/// Reads each chunk once. In particular, a large image or tool-output record
/// must not cause its growing partial line to be split again on every read.
enum CodexRolloutLineReader {
    private static let chunkSize = 64 * 1024

    enum RecordKind: Hashable {
        case sessionMeta, turnContext, threadSettings, tokenCount, interAgentCommunication, other
    }

    /// Usage counters and activity boundaries are committed only by a newline.
    /// Retain at most one small line, then structurally classify oversized rows
    /// before loading relevant records. A skipped row is delivered as nil so a
    /// caller looking for the first physical line can still stop at that line.
    /// Returning true from visit stops the scan; the result is the next complete
    /// line's offset, so appends safely re-read any unfinished record.
    @discardableResult
    static func scanCommittedLines(
        url: URL, from lowerBound: UInt64 = 0, to upperBound: UInt64,
        oversizedKinds: Set<RecordKind>,
        visit: (Data?, UInt64, UInt64) -> Bool
    ) throws -> UInt64 {
        guard upperBound > lowerBound else { return lowerBound }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: lowerBound)
        var position = lowerBound
        var resumeOffset = lowerBound
        var line = Data()
        var oversized = false
        while position < upperBound {
            let shouldStop = try autoreleasepool {
                let count = Int(min(UInt64(chunkSize), upperBound - position))
                let chunk = try handle.read(upToCount: count) ?? Data()
                guard !chunk.isEmpty else { return true }
                let parts = chunk.split(separator: 0x0A, omittingEmptySubsequences: false)
                for (index, part) in parts.enumerated() {
                    if !oversized {
                        if line.count + part.count <= chunkSize {
                            line.append(contentsOf: part)
                        } else {
                            line.removeAll(keepingCapacity: true)
                            oversized = true
                        }
                    }
                    position += UInt64(part.count)
                    if index < parts.count - 1 {
                        let start = resumeOffset
                        let committed = oversized
                            ? try readOversizedLine(url: url, from: start, to: position, kinds: oversizedKinds)
                            : line
                        position += 1
                        resumeOffset = position
                        if visit(committed, start, resumeOffset) { return true }
                        line.removeAll(keepingCapacity: true)
                        oversized = false
                    }
                }
                return false
            }
            if shouldStop { break }
        }
        return resumeOffset
    }

    /// Field order is arbitrary. Inspect only structural type strings, without
    /// retaining large instruction, image, or tool-output strings in the probe.
    /// JSONSerialization in the consumer still validates every selected record.
    static func readOversizedLine(
        url: URL, from start: UInt64, to end: UInt64, kinds: Set<RecordKind>
    ) throws -> Data? {
        guard end > start else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        var position = start
        var probe = RecordProbe()
        while position < end, probe.kind == nil {
            let count = Int(min(UInt64(chunkSize), end - position))
            let chunk = try handle.read(upToCount: count) ?? Data()
            guard !chunk.isEmpty else { return nil }
            position += UInt64(chunk.count)
            for byte in chunk {
                probe.consume(byte)
                if probe.kind != nil { break }
            }
        }
        guard let kind = probe.kind, kinds.contains(kind) else { return nil }
        try handle.seek(toOffset: start)
        position = start
        var line = Data()
        while position < end {
            let count = Int(min(UInt64(chunkSize), end - position))
            let chunk = try handle.read(upToCount: count) ?? Data()
            guard !chunk.isEmpty else { return nil }
            line.append(chunk)
            position += UInt64(chunk.count)
        }
        return line
    }

    private struct RecordProbe {
        private enum StringTarget { case rootKey, rootType, payloadKey, payloadType }
        private var depth = 0
        private var payloadDepth: Int?
        private var rootExpectsKey = true
        private var payloadExpectsKey = true
        private var rootKey: String?
        private var payloadKey: String?
        private var rootType: String?
        private var payloadType: String?
        private var inString = false
        private var escaped = false
        private var target: StringTarget?
        private var capturedString: Data?

        var kind: RecordKind? {
            guard let rootType else { return nil }
            switch rootType {
            case "session_meta": return .sessionMeta
            case "turn_context": return .turnContext
            case "inter_agent_communication_metadata": return .interAgentCommunication
            case "event_msg":
                guard let payloadType else { return nil }
                switch payloadType {
                case "thread_settings_applied": return .threadSettings
                case "token_count": return .tokenCount
                default: return .other
                }
            default: return .other
            }
        }

        mutating func consume(_ byte: UInt8) {
            if inString {
                if capturedString != nil {
                    if capturedString!.count < 256 {
                        capturedString!.append(byte)
                    } else {
                        capturedString = nil
                    }
                }
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                    let value = capturedString.flatMap {
                        (try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)) as? String
                    }
                    switch target {
                    case .rootKey: rootKey = value; rootExpectsKey = false
                    case .rootType: rootType = value
                    case .payloadKey: payloadKey = value; payloadExpectsKey = false
                    case .payloadType: payloadType = value
                    case nil: break
                    }
                    capturedString = nil
                }
                return
            }
            switch byte {
            case 0x22:
                inString = true
                target = nil
                if depth == 1 {
                    target = rootExpectsKey ? .rootKey : (rootKey == "type" ? .rootType : nil)
                } else if depth == payloadDepth {
                    target = payloadExpectsKey ? .payloadKey : (payloadKey == "type" ? .payloadType : nil)
                }
                capturedString = target == nil ? nil : Data([0x22])
            case 0x7B, 0x5B:
                if byte == 0x7B, depth == 1, !rootExpectsKey, rootKey == "payload" {
                    payloadDepth = depth + 1
                    payloadExpectsKey = true
                }
                depth += 1
            case 0x7D, 0x5D:
                if depth == payloadDepth { payloadDepth = nil }
                depth -= 1
            case 0x2C:
                if depth == 1 { rootExpectsKey = true }
                if depth == payloadDepth { payloadExpectsKey = true }
            default: break
            }
        }
    }

    static func scanBackwards(
        url: URL, from lowerBound: UInt64 = 0, to upperBound: UInt64,
        visit: (Data) -> Bool
    ) throws {
        guard upperBound > lowerBound else { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var position = upperBound
        var fragments: [Data] = []
        var fragmentBytes = 0

        func emit(_ prefix: Data) -> Bool {
            var line = Data(capacity: prefix.count + fragmentBytes)
            line.append(prefix)
            for fragment in fragments.reversed() { line.append(fragment) }
            fragments.removeAll(keepingCapacity: true)
            fragmentBytes = 0
            return autoreleasepool { visit(line) }
        }

        while position > lowerBound {
            let count = min(chunkSize, Int(position - lowerBound))
            position -= UInt64(count)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: count) ?? Data()
            guard !chunk.isEmpty else { return }
            let parts = chunk.split(separator: 0x0A, omittingEmptySubsequences: false)
            for part in parts.dropFirst().reversed() {
                if emit(Data(part)) { return }
            }
            if let first = parts.first, !first.isEmpty {
                let fragment = Data(first)
                fragments.append(fragment)
                fragmentBytes += fragment.count
            }
        }
        if fragmentBytes > 0 { _ = emit(Data()) }
    }

    static func scanForward(
        url: URL, from lowerBound: UInt64, to upperBound: UInt64,
        visit: (Data) -> Void
    ) throws {
        guard upperBound > lowerBound else { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: lowerBound)
        var offset = lowerBound
        var line = Data()
        while offset < upperBound {
            let count = min(chunkSize, Int(upperBound - offset))
            let chunk = try handle.read(upToCount: count) ?? Data()
            guard !chunk.isEmpty else { break }
            offset += UInt64(chunk.count)
            let parts = chunk.split(separator: 0x0A, omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                line.append(contentsOf: part)
                if index < parts.count - 1 {
                    autoreleasepool { visit(line) }
                    line.removeAll(keepingCapacity: true)
                }
            }
        }
        // Readers accept a valid JSON record before its final newline arrives;
        // their append cursors re-read that last line on the next poll.
        if !line.isEmpty { autoreleasepool { visit(line) } }
    }
}
