import Foundation

struct ClaudeAuthStatus: Equatable, Sendable {
    let isLoggedIn: Bool
    let email: String?
    let plan: String?
    let authMethod: String?
}

struct ClaudeCommandResult: Sendable {
    let status: Int32
    let output: String
}

struct ClaudeAccountService: Sendable {
    let binaryPath: String

    func status(profile: URL?) async throws -> ClaudeAuthStatus {
        let result = try await run(arguments: ["auth", "status"], profile: profile, timeout: 20)
        if result.status == 1, result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClaudeAuthStatus(isLoggedIn: false, email: nil, plan: nil, authMethod: nil)
        }
        guard result.status == 0 || result.status == 1 else {
            throw LLMAccountSwitcherError.message(result.output.nonEmpty ?? L10n.text("claude_status_failed"))
        }
        return try Self.parseStatus(result.output)
    }

    func login(profile: URL) async throws -> ClaudeAuthStatus {
        let result = try await run(arguments: ["auth", "login"], profile: profile, timeout: 600)
        guard result.status == 0 else {
            throw LLMAccountSwitcherError.message(result.output.nonEmpty ?? L10n.text("login_failed"))
        }
        let status = try await status(profile: profile)
        guard status.isLoggedIn else {
            throw LLMAccountSwitcherError.message(L10n.text("login_not_completed"))
        }
        return status
    }

    static func parseStatus(_ text: String) throws -> ClaudeAuthStatus {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else {
            throw LLMAccountSwitcherError.message(L10n.text("claude_status_invalid"))
        }

        let loggedIn = recursiveValue(in: object, keys: ["loggedIn", "isLoggedIn"]) as? Bool
            ?? recursiveString(in: object, keys: ["status"]).map { ["loggedin", "authenticated"].contains($0.normalizedKey) }
            ?? false
        return ClaudeAuthStatus(
            isLoggedIn: loggedIn,
            email: recursiveString(in: object, keys: ["email", "emailAddress"]),
            plan: recursiveString(in: object, keys: ["subscriptionType", "planType", "plan"]),
            authMethod: recursiveString(in: object, keys: ["authMethod", "authenticationMethod", "loginMethod"])
        )
    }

    private func run(arguments: [String], profile: URL?, timeout: TimeInterval) async throws -> ClaudeCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                if let profile {
                    environment["CLAUDE_CONFIG_DIR"] = profile.path
                } else {
                    environment.removeValue(forKey: "CLAUDE_CONFIG_DIR")
                }
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
                    continuation.resume(throwing: LLMAccountSwitcherError.message(L10n.text("claude_command_timeout")))
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: ClaudeCommandResult(status: process.terminationStatus, output: text))
            }
        }
    }

    private static func recursiveString(in value: Any, keys: Set<String>) -> String? {
        recursiveValue(in: value, keys: keys) as? String
    }

    private static func recursiveValue(in value: Any, keys: Set<String>) -> Any? {
        if let object = value as? [String: Any] {
            for (key, child) in object where keys.contains(key) { return child }
            for child in object.values {
                if let match = recursiveValue(in: child, keys: keys) { return match }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let match = recursiveValue(in: child, keys: keys) { return match }
            }
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var normalizedKey: String {
        lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
    }
}
