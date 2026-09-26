import Foundation
import OSLog

actor CodexAppServerClient {
    private struct RPCErrorPayload: Decodable { let code: Int?; let message: String }
    private struct Envelope: Decodable {
        let id: JSONValue?
        let method: String?
        let result: JSONValue?
        let error: RPCErrorPayload?
        let params: JSONValue?
    }
    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }
    private struct NotificationPending {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let logger = Logger(subsystem: "local.codex-account-manager.app", category: "app-server")
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var nextID = 1
    private var pending: [String: Pending] = [:]
    private var notificationWaiters: [String: [NotificationPending]] = [:]

    func start(binaryPath: String, codexHome: URL?) throws {
        guard process == nil else { return }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] process in
            Task { await self?.processExited(code: process.terminationStatus) }
        }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
    }

    func initialize(version: String) async throws {
        _ = try await request(method: "initialize", params: .object([
            "clientInfo": .object(["name": .string("codex-account-manager"), "title": .string("codex-account-manager"), "version": .string(version)]),
            "capabilities": .object(["experimentalApi": .bool(true)]),
        ]), timeout: 15)
        try sendNotification(method: "initialized", params: nil)
    }

    func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        let id = String(nextID)
        nextID += 1
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method)]
        if let params { object["params"] = params }
        let data = try lineData(.object(object))
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.timeoutRequest(id: id)
            }
            pending[id] = Pending(continuation: continuation, timeoutTask: timeoutTask)
            do { try input?.write(contentsOf: data) }
            catch {
                pending.removeValue(forKey: id)?.timeoutTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    func waitForNotification(method: String, timeout: TimeInterval) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.timeoutNotification(method: method)
            }
            notificationWaiters[method, default: []].append(
                NotificationPending(continuation: continuation, timeoutTask: timeoutTask)
            )
        }
    }

    func stop() async {
        guard let process else { return }
        input?.closeFile()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        cleanup(error: CodexAccountManagerError.message(L10n.text("app_server_stopped")))
    }

    private func sendNotification(method: String, params: JSONValue?) throws {
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method)]
        if let params { object["params"] = params }
        try input?.write(contentsOf: lineData(.object(object)))
    }

    private func lineData(_ value: JSONValue) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    private func ingest(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(line)) else {
                logger.warning("Bỏ qua output app-server không hợp lệ")
                continue
            }
            route(envelope)
        }
    }

    private func route(_ envelope: Envelope) {
        if let idValue = envelope.id {
            let id: String?
            switch idValue { case .string(let value): id = value; case .number(let value): id = String(Int(value)); default: id = nil }
            if let id, let item = pending.removeValue(forKey: id) {
                item.timeoutTask.cancel()
                if let error = envelope.error { item.continuation.resume(throwing: CodexAccountManagerError.message(error.message)) }
                else { item.continuation.resume(returning: envelope.result ?? .null) }
            }
        } else if let method = envelope.method, var waiters = notificationWaiters.removeValue(forKey: method), !waiters.isEmpty {
            let first = waiters.removeFirst()
            if !waiters.isEmpty { notificationWaiters[method] = waiters }
            first.timeoutTask.cancel()
            first.continuation.resume(returning: envelope.params ?? .null)
        }
    }

    private func timeoutRequest(id: String) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.continuation.resume(throwing: CodexAccountManagerError.message(L10n.text("app_server_no_response")))
    }

    private func timeoutNotification(method: String) {
        guard var waiters = notificationWaiters.removeValue(forKey: method), !waiters.isEmpty else { return }
        let first = waiters.removeFirst()
        if !waiters.isEmpty { notificationWaiters[method] = waiters }
        first.continuation.resume(throwing: CodexAccountManagerError.message(L10n.text("login_timeout")))
    }

    private func processExited(code: Int32) {
        logger.info("Codex app-server thoát, mã \(code)")
        cleanup(error: CodexAccountManagerError.message(L10n.text("app_server_exited")))
    }

    private func cleanup(error: Error) {
        process = nil
        input = nil
        for item in pending.values { item.timeoutTask.cancel(); item.continuation.resume(throwing: error) }
        pending.removeAll()
        for waiters in notificationWaiters.values {
            for waiter in waiters { waiter.timeoutTask.cancel(); waiter.continuation.resume(throwing: error) }
        }
        notificationWaiters.removeAll()
    }
}
