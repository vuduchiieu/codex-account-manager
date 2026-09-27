import Foundation

struct CopilotIdentity: Codable, Equatable, Hashable, Sendable {
    let host: String
    let login: String

    var key: String { "\(host.lowercased())|\(login.lowercased())" }
}

struct CopilotAuthState: Equatable, Sendable {
    let identities: [CopilotIdentity]
    let activeIdentity: CopilotIdentity?
}

struct CopilotCommandResult: Sendable {
    let status: Int32
    let output: String
}

struct CopilotAccountService: Sendable {
    let binaryPath: String
    let configURL: URL

    init(
        binaryPath: String,
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/config.json")
    ) {
        self.binaryPath = binaryPath
        self.configURL = configURL
    }

    func status() throws -> CopilotAuthState {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return CopilotAuthState(identities: [], activeIdentity: nil)
        }
        let data = try Data(contentsOf: configURL)
        return try Self.parseConfig(data)
    }

    func login() async throws -> CopilotAuthState {
        let result = try await run(arguments: ["login", "--web-flow"], timeout: 600)
        guard result.status == 0 else {
            throw LLMAccountSwitcherError.message(result.output.nonEmptyCopilot ?? L10n.text("login_failed"))
        }
        let state = try status()
        guard !state.identities.isEmpty else {
            throw LLMAccountSwitcherError.message(L10n.text("login_not_completed"))
        }
        return state
    }

    func activate(_ identity: CopilotIdentity) throws -> CopilotAuthState {
        let original = try Data(contentsOf: configURL)
        var object = try Self.configObject(from: original)
        let state = try Self.parseConfig(original)
        guard state.identities.contains(identity) else {
            throw LLMAccountSwitcherError.message(L10n.text("copilot_login_required"))
        }

        let key = object["lastLoggedInUser"] != nil || object["last_logged_in_user"] == nil
            ? "lastLoggedInUser" : "last_logged_in_user"
        object[key] = ["host": identity.host, "login": identity.login]

        do {
            try writeConfig(object)
            let verified = try status()
            guard verified.activeIdentity == identity else {
                throw LLMAccountSwitcherError.message(L10n.text("switch_verify_mismatch"))
            }
            return verified
        } catch {
            try? atomicWrite(original, to: configURL)
            throw error
        }
    }

    func remove(_ identity: CopilotIdentity) throws -> CopilotAuthState {
        let original = try Data(contentsOf: configURL)
        var object = try Self.configObject(from: original)
        let listKey = object["loggedInUsers"] != nil || object["logged_in_users"] == nil
            ? "loggedInUsers" : "logged_in_users"
        let remaining = try Self.parseConfig(original).identities.filter { $0 != identity }
        object[listKey] = remaining.map { ["host": $0.host, "login": $0.login] }

        let activeKey = object["lastLoggedInUser"] != nil || object["last_logged_in_user"] == nil
            ? "lastLoggedInUser" : "last_logged_in_user"
        if let replacement = remaining.first {
            object[activeKey] = ["host": replacement.host, "login": replacement.login]
        } else {
            object.removeValue(forKey: activeKey)
        }

        do {
            try writeConfig(object)
            return try status()
        } catch {
            try? atomicWrite(original, to: configURL)
            throw error
        }
    }

    static func parseConfig(_ data: Data) throws -> CopilotAuthState {
        let object = try configObject(from: data)
        let rawUsers = object["loggedInUsers"] ?? object["logged_in_users"]
        let users = (rawUsers as? [[String: Any]] ?? []).compactMap(identity)
        let unique = users.reduce(into: [CopilotIdentity]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        let rawActive = object["lastLoggedInUser"] ?? object["last_logged_in_user"]
        let active = (rawActive as? [String: Any]).flatMap(identity)
        let resolvedActive = active.flatMap { unique.contains($0) ? $0 : nil } ?? unique.first
        return CopilotAuthState(identities: unique, activeIdentity: resolvedActive)
    }

    private static func configObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMAccountSwitcherError.message(L10n.text("copilot_config_invalid"))
        }
        return object
    }

    private static func identity(_ object: [String: Any]) -> CopilotIdentity? {
        guard let rawHost = object["host"] as? String,
              let rawLogin = object["login"] as? String else { return nil }
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = rawLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !login.isEmpty else { return nil }
        return CopilotIdentity(host: host, login: login)
    }

    private func writeConfig(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(data, to: configURL)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func run(arguments: [String], timeout: TimeInterval) async throws -> CopilotCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                environment.removeValue(forKey: "COPILOT_GITHUB_TOKEN")
                environment.removeValue(forKey: "GH_TOKEN")
                environment.removeValue(forKey: "GITHUB_TOKEN")
                process.environment = environment
                process.standardOutput = output
                process.standardError = output
                process.standardInput = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                guard !process.isRunning else {
                    process.terminate()
                    continuation.resume(throwing: LLMAccountSwitcherError.message(L10n.text("copilot_command_timeout")))
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: CopilotCommandResult(status: process.terminationStatus, output: text))
            }
        }
    }
}

private extension String {
    var nonEmptyCopilot: String? { isEmpty ? nil : self }
}
