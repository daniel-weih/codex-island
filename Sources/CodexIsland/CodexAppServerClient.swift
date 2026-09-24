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
    /// Runs on the transport queue. Returning nil rejects an unsupported request.
    typealias ServerRequestHandler = (String, JSONObject) -> JSONObject?

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

    var onNotification: NotificationHandler?
    var onConnectionChanged: ConnectionHandler?
    var onServerRequest: ServerRequestHandler?

    private let queue = DispatchQueue(label: "com.codexisland.app.app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var nextID = 1
    private var ready = false
    private var intentionallyStopping = false
    private let clientName: String
    private let launchArguments: [String]
    private let workingDirectory: URL?

    init(clientName: String = "codex_island", launchArguments: [String] = [], workingDirectory: URL? = nil) {
        self.clientName = clientName
        self.launchArguments = launchArguments
        self.workingDirectory = workingDirectory
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
        guard let executable = CodexExecutableLocator.locate() else {
            throw CodexAppServerError.executableNotFound
        }

        intentionallyStopping = false
        ready = false
        outputBuffer.removeAll(keepingCapacity: true)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let standardError = Pipe()

        process.executableURL = executable
        process.arguments = ["app-server"] + launchArguments
        process.environment = CodexExecutableLocator.augmentedEnvironment()
        process.currentDirectoryURL = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = standardError

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.consumeOutputLocked(data)
            }
        }

        standardError.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] process in
            self?.queue.async {
                self?.handleTerminationLocked(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
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

        do {
            try writeLocked(["method": method, "id": id, "params": params])
        } catch {
            pending.removeValue(forKey: id)
            completion(.failure(error))
            return
        }

        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let request = self.pending.removeValue(forKey: id) else { return }
            request.completion(.failure(CodexAppServerError.requestTimedOut(request.method)))
        }
    }

    private func sendNotificationLocked(method: String, params: JSONObject) throws {
        try writeLocked(["method": method, "params": params])
    }

    private func cancelRequestLocked(_ cancellationID: UUID) {
        guard let id = pending.first(where: { $0.value.cancellationID == cancellationID })?.key,
              let request = pending.removeValue(forKey: id) else { return }
        request.completion(.failure(CancellationError()))
    }

    private func writeLocked(_ object: JSONObject) throws {
        guard let inputPipe else { throw CodexAppServerError.serverStopped }
        var data = try JSONSerialization.data(withJSONObject: object, options: [])
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
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
        if let method = message.string("method"), let id = message["id"] {
            let params = message.dictionary("params") ?? [:]
            if let result = onServerRequest?(method, params) {
                try? writeLocked(["id": id, "result": result])
            } else {
                try? writeLocked(["id": id, "error": [
                    "code": -32601,
                    "message": "This client does not allow interactive requests or tool execution."
                ]])
            }
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

    private func handleTerminationLocked(status: Int32) {
        let wasIntentional = intentionallyStopping
        ready = false
        failAllPendingLocked(with: CodexAppServerError.serverStopped)
        cleanUpLocked()
        if !wasIntentional {
            dispatchConnectionChanged(false, "App Server 已退出（\(status)）")
        }
    }

    private func failAllPendingLocked(with error: Error) {
        let requests = pending.values
        pending.removeAll()
        requests.forEach { $0.completion(.failure(error)) }
    }

    private func cleanUpLocked() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer.removeAll(keepingCapacity: false)
    }

    private func abandonProcessLocked() {
        intentionallyStopping = true
        ready = false
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        terminateProcessLocked()
        failAllPendingLocked(with: CodexAppServerError.serverStopped)
        cleanUpLocked()
    }

    private func terminateProcessLocked() {
        guard let process else { return }
        process.terminationHandler = nil
        guard process.isRunning else { return }
        process.terminate()
        // A stuck app-server must not keep consuming a scheduled analysis after cancellation.
        queue.asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func dispatchConnectionChanged(_ connected: Bool, _ message: String?) {
        guard let handler = onConnectionChanged else { return }
        DispatchQueue.main.async {
            handler(connected, message)
        }
    }
}
