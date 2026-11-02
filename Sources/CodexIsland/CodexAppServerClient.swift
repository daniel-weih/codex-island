import Foundation
import Darwin

enum CodexAppServerError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case notReady
    case serverStopped
    case requestTimedOut(String)
    case invalidResponse
    case remote(code: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "找不到 Codex CLI。请安装 codex，或设置 CODEX_CLI_PATH。"
        case .launchFailed(let message):
            return "Codex App Server 启动失败：\(message)"
        case .notReady:
            return "Codex App Server 尚未就绪"
        case .serverStopped:
            return "Codex App Server 已停止"
        case .requestTimedOut(let method):
            return "请求 \(method) 超时"
        case .invalidResponse:
            return "Codex App Server 返回了无法解析的数据"
        case .remote(_, let message):
            return message
        }
    }
}

final class CodexAppServerClient: @unchecked Sendable {
    typealias NotificationHandler = (String, JSONObject) -> Void
    typealias ConnectionHandler = (Bool, String?) -> Void

    private final class RequestCancellation: @unchecked Sendable {
        let id = UUID()
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private struct PendingRequest {
        let method: String
        let cancellationID: UUID?
        let completion: (Result<JSONObject, Error>) -> Void
    }

    private struct PendingWrite {
        let data: Data
        let requestID: Int?
        var offset = 0
    }

    var onNotification: NotificationHandler?
    var onConnectionChanged: ConnectionHandler?

    private let queue = DispatchQueue(label: "com.codexisland.app.app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var pendingWrites: [PendingWrite] = []
    private var writeSource: DispatchSourceWrite?
    private var nextID = 1
    private var ready = false
    private var intentionallyStopping = false
    private let clientName: String

    /// Called by the application's exit handler, including probe exits. The
    /// normal asynchronous stop path cannot rely on its delayed SIGKILL after
    /// the parent process has already exited.
    static func shutdownAll() {
        AppServerProcesses.shared.shutdown()
    }

    init(clientName: String = "codex_island") {
        self.clientName = clientName
    }

    func start() async throws {
        let cancellation = RequestCancellation()
        try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard !cancellation.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if self.ready, self.process?.isRunning == true {
                    continuation.resume()
                    return
                }

                if self.process?.isRunning == true {
                    continuation.resume(throwing: CodexAppServerError.notReady)
                    return
                }

                do {
                    try self.launchLocked()
                    self.sendRequestLocked(
                        method: "initialize",
                        params: [
                            "clientInfo": [
                                "name": self.clientName,
                                "title": "Codex Island",
                                "version": "0.1.0"
                            ]
                        ],
                        timeout: 12,
                        cancellationID: cancellation.id
                    ) { result in
                        switch result {
                        case .success:
                            do {
                                try self.sendNotificationLocked(method: "initialized", params: [:])
                                self.ready = true
                                self.dispatchConnectionChanged(true, nil)
                                continuation.resume()
                            } catch {
                                self.abandonProcessLocked()
                                continuation.resume(throwing: error)
                            }
                        case .failure(let error):
                            self.abandonProcessLocked()
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        }, onCancel: {
            cancellation.cancel()
            self.queue.async { self.cancelRequestLocked(cancellation.id) }
        })
    }

    func request(method: String, params: JSONObject = [:], timeout: TimeInterval = 12) async throws -> JSONObject {
        let cancellation = RequestCancellation()
        return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !cancellation.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard self.ready, self.process?.isRunning == true else {
                    continuation.resume(throwing: CodexAppServerError.notReady)
                    return
                }
                self.sendRequestLocked(method: method, params: params, timeout: timeout, cancellationID: cancellation.id) { result in
                    continuation.resume(with: result)
                }
            }
        }
        }, onCancel: {
            cancellation.cancel()
            self.queue.async { self.cancelRequestLocked(cancellation.id) }
        })
    }

    func stop() {
        queue.async {
            self.intentionallyStopping = true
            self.ready = false
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            self.errorPipe?.fileHandleForReading.readabilityHandler = nil
            self.terminateProcessLocked()
            self.failAllPendingLocked(with: CodexAppServerError.serverStopped)
            self.cleanUpLocked()
        }
    }

    private func launchLocked() throws {
        if process != nil { abandonProcessLocked() }
        guard let launch = CodexExecutableLocator.locate() else {
            throw CodexAppServerError.executableNotFound
        }

        intentionallyStopping = false
        ready = false
        outputBuffer.removeAll(keepingCapacity: true)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let standardError = Pipe()
        // The child can exit between our liveness check and a write, including
        // replies to server requests. Report EPIPE instead of killing the app.
        let inputDescriptor = input.fileHandleForWriting.fileDescriptor
        let flags = fcntl(inputDescriptor, F_GETFL)
        guard flags != -1,
              fcntl(inputDescriptor, F_SETFL, flags | O_NONBLOCK) != -1,
              fcntl(inputDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw CodexAppServerError.launchFailed(
                NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription
            )
        }

        process.executableURL = launch.executableURL
        process.arguments = ["app-server"]
        process.environment = launch.environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = standardError

        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            guard let process else { return }
            self?.queue.async {
                guard let self, self.process === process else { return }
                guard !data.isEmpty else {
                    // EOF is a broken transport even if the child remains alive.
                    // Otherwise start() keeps accepting the unusable connection
                    // and every subsequent RPC waits for its own timeout.
                    self.failTransportLocked(with: CodexAppServerError.serverStopped)
                    return
                }
                self.consumeOutputLocked(data)
            }
        }

        standardError.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }

        process.terminationHandler = { [weak self] process in
            AppServerProcesses.shared.didExit(process)
            self?.queue.async {
                self?.handleTerminationLocked(process)
            }
        }

        do {
            try AppServerProcesses.shared.launch(process)
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        self.process = process
        inputPipe = input
        outputPipe = output
        errorPipe = standardError
    }

    private func sendRequestLocked(
        method: String,
        params: JSONObject,
        timeout: TimeInterval,
        cancellationID: UUID? = nil,
        completion: @escaping (Result<JSONObject, Error>) -> Void
    ) {
        guard process?.isRunning == true else {
            completion(.failure(CodexAppServerError.serverStopped))
            return
        }

        let id = nextID
        nextID += 1
        pending[id] = PendingRequest(method: method, cancellationID: cancellationID, completion: completion)

        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let request = self.pending[id] else { return }
            self.failRequestLocked(id, with: CodexAppServerError.requestTimedOut(request.method))
        }

        do {
            try writeLocked(["method": method, "id": id, "params": params], requestID: id)
        } catch {
            pending.removeValue(forKey: id)
            completion(.failure(error))
            return
        }

    }

    private func sendNotificationLocked(method: String, params: JSONObject) throws {
        try writeLocked(["method": method, "params": params])
    }

    private func cancelRequestLocked(_ cancellationID: UUID) {
        guard let id = pending.first(where: { $0.value.cancellationID == cancellationID })?.key else { return }
        failRequestLocked(id, with: CancellationError())
    }

    private func failRequestLocked(_ id: Int, with error: Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        if let index = pendingWrites.firstIndex(where: { $0.requestID == id }) {
            if pendingWrites[index].offset > 0 {
                // A partial JSON line cannot be discarded on a live connection:
                // the next message would complete a corrupt frame or run a
                // cancelled request. Close this connection before restarting.
                failTransportLocked(with: error)
            } else {
                pendingWrites.remove(at: index)
                if pendingWrites.isEmpty { cancelWriteSourceLocked() }
            }
        }
        request.completion(.failure(error))
    }

    private func writeLocked(_ object: JSONObject, requestID: Int? = nil) throws {
        guard let inputPipe, let process else { throw CodexAppServerError.serverStopped }
        var data = try JSONSerialization.data(withJSONObject: object, options: [])
        data.append(0x0A)
        pendingWrites.append(PendingWrite(data: data, requestID: requestID))
        guard writeSource == nil else { return }

        let handle = inputPipe.fileHandleForWriting
        let source = DispatchSource.makeWriteSource(fileDescriptor: handle.fileDescriptor, queue: queue)
        source.setEventHandler { [weak self, weak process] in
            guard let self, let process, self.process === process else { return }
            self.flushWritesLocked()
        }
        // Dispatch must finish observing the descriptor before its owner closes
        // it. Otherwise a cancelled source could observe a replacement pipe.
        source.setCancelHandler { withExtendedLifetime(handle) {} }
        writeSource = source
        source.resume()
    }

    private func flushWritesLocked() {
        guard let inputPipe else { return }
        // Nonblocking writes and a bounded batch keep deadlines, cancellation,
        // and stop() responsive even when the child stops reading stdin.
        var budget = 64 * 1024
        while let first = pendingWrites.first, budget > 0 {
            let count = min(first.data.count - first.offset, budget)
            let written = first.data.withUnsafeBytes { bytes in
                Darwin.write(inputPipe.fileHandleForWriting.fileDescriptor,
                             bytes.baseAddress!.advanced(by: first.offset), count)
            }
            if written > 0 {
                pendingWrites[0].offset += written
                budget -= written
                if pendingWrites[0].offset == first.data.count { pendingWrites.removeFirst() }
            } else if written == -1, errno == EINTR {
                continue
            } else if written == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                let error = NSError(domain: NSPOSIXErrorDomain, code: Int(written == 0 ? EIO : errno))
                failTransportLocked(with: error)
                return
            }
        }
        if pendingWrites.isEmpty { cancelWriteSourceLocked() }
    }

    private func cancelWriteSourceLocked() {
        writeSource?.cancel()
        writeSource = nil
    }

    private func failTransportLocked(with error: Error) {
        let wasReady = ready
        abandonProcessLocked(with: error)
        if wasReady { dispatchConnectionChanged(false, error.localizedDescription) }
    }

    private func consumeOutputLocked(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])

        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject else {
                continue
            }
            handleMessageLocked(object)
        }
    }

    private func handleMessageLocked(_ message: JSONObject) {
        // Server request IDs occupy a separate namespace from our pending requests.
        // Handle them first so an approval can never be mistaken for an RPC response.
        if message.string("method") != nil, let id = message["id"] {
            try? writeLocked(["id": id, "error": [
                "code": -32601,
                "message": "This client does not allow interactive requests or tool execution."
            ]])
            return
        }
        if let id = message.int("id"), let request = pending.removeValue(forKey: id) {
            if let error = message.dictionary("error") {
                request.completion(.failure(CodexAppServerError.remote(
                    code: error.int("code"),
                    message: error.string("message") ?? "Codex App Server 请求失败"
                )))
            } else if let result = message.dictionary("result") {
                request.completion(.success(result))
            } else {
                request.completion(.failure(CodexAppServerError.invalidResponse))
            }
            return
        }

        if let method = message.string("method") {
            let params = message.dictionary("params") ?? [:]
            if let handler = onNotification {
                DispatchQueue.main.async {
                    handler(method, params)
                }
            }
        }
    }

    private func handleTerminationLocked(_ terminatedProcess: Process) {
        // A replacement may have started before this callback reached our
        // queue. The old child's output and exit must never touch that connection.
        guard process === terminatedProcess else { return }
        let wasIntentional = intentionallyStopping
        ready = false
        failAllPendingLocked(with: CodexAppServerError.serverStopped)
        cleanUpLocked()
        if !wasIntentional {
            dispatchConnectionChanged(false, "App Server 已退出（\(terminatedProcess.terminationStatus)）")
        }
    }

    private func failAllPendingLocked(with error: Error) {
        let requests = pending.values
        pending.removeAll()
        requests.forEach { $0.completion(.failure(error)) }
    }

    private func cleanUpLocked() {
        cancelWriteSourceLocked()
        pendingWrites.removeAll()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer.removeAll(keepingCapacity: false)
    }

    private func abandonProcessLocked(with error: Error = CodexAppServerError.serverStopped) {
        intentionallyStopping = true
        ready = false
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        terminateProcessLocked()
        failAllPendingLocked(with: error)
        cleanUpLocked()
    }

    private func terminateProcessLocked() {
        guard let process else { return }
        AppServerProcesses.shared.terminate(process)
    }

    private func dispatchConnectionChanged(_ connected: Bool, _ message: String?) {
        guard let handler = onConnectionChanged else { return }
        DispatchQueue.main.async {
            handler(connected, message)
        }
    }
}

/// Owns both active connections and children still in their termination grace
/// period. Only processes launched here are ever signalled; an application
/// exit closes registration before waiting, so queued starts cannot escape it.
private final class AppServerProcesses: @unchecked Sendable {
    private final class Child {
        let process: Process
        let group: pid_t?
        var isStopping = false // Protected by the registry lock.

        init(_ process: Process) {
            self.process = process
            let pid = process.processIdentifier
            // Foundation normally creates a child process group. Signal it
            // only after proving that our child, not the app, owns that group.
            group = getpgid(pid) == pid && getpgrp() != pid ? pid : nil
        }

        var isAlive: Bool {
            process.isRunning || group.map { kill(-$0, 0) == 0 } == true
        }

        func signal(_ signal: Int32) {
            if let group { kill(-group, signal) }
            else if process.isRunning { kill(process.processIdentifier, signal) }
        }
    }

    static let shared = AppServerProcesses()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Child] = [:]
    private var isShuttingDown = false

    func launch(_ process: Process) throws {
        try lock.withLock {
            guard !isShuttingDown else { throw CodexAppServerError.serverStopped }
            try process.run()
            processes[ObjectIdentifier(process)] = Child(process)
        }
    }

    func didExit(_ process: Process) {
        // An npm/shell launcher may exit while its server is still alive.
        // Keep ownership of that group until termination has completed.
        terminate(process)
    }

    func terminate(_ process: Process) {
        let key = ObjectIdentifier(process)
        let child: Child? = lock.withLock {
            guard let child = processes[key] else { return nil }
            guard child.isAlive else {
                processes.removeValue(forKey: key)
                return nil
            }
            guard !child.isStopping else { return nil }
            child.isStopping = true
            child.signal(SIGTERM)
            return child
        }
        guard let child else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            self.lock.withLock {
                guard self.processes[key] === child else { return }
                if child.isAlive { child.signal(SIGKILL) }
                self.processes.removeValue(forKey: key)
            }
        }
    }

    func shutdown() {
        let children = lock.withLock {
            isShuttingDown = true
            return Array(processes.values)
        }
        for child in children where child.isAlive { child.signal(SIGTERM) }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while children.contains(where: \.isAlive), ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        for child in children where child.isAlive {
            child.signal(SIGKILL)
        }
        // Foundation reaps the owned children. Keep exit handlers alive until
        // that happens instead of leaving orphaned model calls behind.
        for child in children { child.process.waitUntilExit() }
    }
}
