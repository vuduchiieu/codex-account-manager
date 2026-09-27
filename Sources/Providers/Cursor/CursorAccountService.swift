import Foundation

struct CursorAuthStatus: Equatable, Sendable {
    let isLoggedIn: Bool
    let email: String?
    let plan: String?
}

struct CursorCommandResult: Sendable {
    let status: Int32
    let output: String
}

struct CursorAccountService: Sendable {
    let binaryPath: String

    func status(profile: URL?, usesFileCredentialStore: Bool = false) async throws -> CursorAuthStatus {
        let result = try await run(
            arguments: ["status"],
            profile: profile,
            usesFileCredentialStore: usesFileCredentialStore,
            timeout: 25
        )
        let status = Self.parseStatus(result.output)
        if result.status != 0, !status.isLoggedIn,
           !result.output.lowercased().contains("not logged in"),
           !result.output.lowercased().contains("not authenticated") {
            throw LLMAccountSwitcherError.message(result.output.cursorNonEmpty ?? L10n.text("cursor_status_failed"))
        }
        return status
    }

    func login(profile: URL) async throws -> CursorAuthStatus {
        let result = try await run(
            arguments: ["login"],
            profile: profile,
            usesFileCredentialStore: true,
            timeout: 600
        )
        guard result.status == 0 else {
            throw LLMAccountSwitcherError.message(result.output.cursorNonEmpty ?? L10n.text("login_failed"))
        }
        let status = try await status(profile: profile, usesFileCredentialStore: true)
        guard status.isLoggedIn else {
            throw LLMAccountSwitcherError.message(L10n.text("login_not_completed"))
        }
        return status
    }

    static func parseStatus(_ text: String) -> CursorAuthStatus {
        let normalized = text.lowercased()
        let loggedOut = normalized.contains("not logged in")
            || normalized.contains("not authenticated")
            || normalized.contains("login required")
        let loggedIn = !loggedOut && (
            normalized.contains("login successful")
                || normalized.contains("logged in")
                || normalized.contains("authenticated")
        )

        return CursorAuthStatus(
            isLoggedIn: loggedIn,
            email: firstMatch(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: text),
            plan: labeledValue(labels: ["plan", "subscription"], in: text)
        )
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func labeledValue(labels: [String], in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, labels.contains(parts[0].lowercased()), !parts[1].isEmpty else { continue }
            return parts[1]
        }
        return nil
    }

    private func run(
        arguments: [String],
        profile: URL?,
        usesFileCredentialStore: Bool,
        timeout: TimeInterval
    ) async throws -> CursorCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                if let profile {
                    try? FileManager.default.createDirectory(
                        at: profile,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    environment["CURSOR_CONFIG_DIR"] = profile.path
                } else {
                    environment.removeValue(forKey: "CURSOR_CONFIG_DIR")
                }
                if usesFileCredentialStore {
                    environment["AGENT_CLI_CREDENTIAL_STORE"] = "file"
                } else {
                    environment.removeValue(forKey: "AGENT_CLI_CREDENTIAL_STORE")
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
                    continuation.resume(throwing: LLMAccountSwitcherError.message(L10n.text("cursor_command_timeout")))
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: CursorCommandResult(status: process.terminationStatus, output: text))
            }
        }
    }
}

private extension String {
    var cursorNonEmpty: String? { isEmpty ? nil : self }
}
