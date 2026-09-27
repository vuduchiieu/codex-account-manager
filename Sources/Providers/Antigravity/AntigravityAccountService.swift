import CryptoKit
import Foundation

struct AntigravityAuthStatus: Equatable, Sendable {
    let isLoggedIn: Bool
    let email: String?
    let plan: String?
    let credentialFingerprint: String
}

struct AntigravityLoginSession: Sendable {
    let previousLiveCredential: Data?
    let startedAt: Date
}

protocol AntigravityCredentialStoring: Sendable {
    func readLiveCredential() async throws -> Data?
    func writeLiveCredential(_ credential: Data) async throws
    func deleteLiveCredential() async throws
    func readProfileCredential(key: String) async throws -> Data?
    func writeProfileCredential(_ credential: Data, key: String) async throws
    func deleteProfileCredential(key: String) async throws
}

actor SystemAntigravityCredentialStore: AntigravityCredentialStoring {
    private let liveService = "gemini"
    private let liveAccount = "antigravity"
    private let profileService = "local.llm-account-switcher.antigravity-profile"

    func readLiveCredential() async throws -> Data? {
        try read(service: liveService, account: liveAccount)
    }

    func writeLiveCredential(_ credential: Data) async throws {
        try deleteAll(service: liveService, account: liveAccount)
        try write(credential, service: liveService, account: liveAccount)
    }

    func deleteLiveCredential() async throws {
        try deleteAll(service: liveService, account: liveAccount)
    }

    func readProfileCredential(key: String) async throws -> Data? {
        try read(service: profileService, account: key)
    }

    func writeProfileCredential(_ credential: Data, key: String) async throws {
        try write(credential, service: profileService, account: key)
    }

    func deleteProfileCredential(key: String) async throws {
        try deleteAll(service: profileService, account: key)
    }

    private func read(service: String, account: String) throws -> Data? {
        let result = try runSecurity([
            "find-generic-password", "-s", service, "-a", account, "-w",
        ])
        guard result.status == 0 else { return nil }
        guard var value = String(data: result.output, encoding: .utf8) else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_keychain_read_failed"))
        }
        while value.last == "\n" || value.last == "\r" { value.removeLast() }
        return value.isEmpty ? nil : Data(value.utf8)
    }

    private func write(_ credential: Data, service: String, account: String) throws {
        guard let value = String(data: credential, encoding: .utf8), !value.isEmpty else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_keychain_invalid"))
        }
        let input = Data((value + "\n" + value + "\n").utf8)
        let result = try runSecurity([
            "add-generic-password", "-U", "-s", service, "-a", account, "-w",
        ], input: input)
        guard result.status == 0 else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_keychain_write_failed"))
        }
    }

    private func deleteAll(service: String, account: String) throws {
        for _ in 0..<5 {
            let result = try runSecurity([
                "delete-generic-password", "-s", service, "-a", account,
            ])
            if result.status != 0 { break }
        }
    }

    private func runSecurity(_ arguments: [String], input: Data? = nil) throws -> (status: Int32, output: Data) {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let standardInput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        if input != nil { process.standardInput = standardInput }
        try process.run()
        if let input {
            try standardInput.fileHandleForWriting.write(contentsOf: input)
            try standardInput.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        return (process.terminationStatus, output.fileHandleForReading.readDataToEndOfFile())
    }
}

struct AntigravityAccountService: Sendable {
    private let credentialStore: any AntigravityCredentialStoring

    init(credentialStore: any AntigravityCredentialStoring = SystemAntigravityCredentialStore()) {
        self.credentialStore = credentialStore
    }

    func importCurrent(profileKey: String) async throws -> AntigravityAuthStatus {
        guard let credential = try await credentialStore.readLiveCredential() else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_not_logged_in"))
        }
        let status = await Self.status(for: credential)
        try await credentialStore.writeProfileCredential(credential, key: profileKey)
        return status
    }

    func profileStatus(profileKey: String, knownEmail: String? = nil) async throws -> AntigravityAuthStatus {
        guard let credential = try await credentialStore.readProfileCredential(key: profileKey) else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_login_required"))
        }
        return await Self.status(for: credential, fallbackEmail: knownEmail)
    }

    func prepareInteractiveLogin(activeProfileKey: String?) async throws -> AntigravityLoginSession {
        let previous = try await credentialStore.readLiveCredential()
        if let activeProfileKey, let previous {
            try await credentialStore.writeProfileCredential(previous, key: activeProfileKey)
        }
        try await credentialStore.deleteLiveCredential()
        return AntigravityLoginSession(previousLiveCredential: previous, startedAt: Date())
    }

    func completeInteractiveLogin(profileKey: String, session: AntigravityLoginSession) async throws -> AntigravityAuthStatus {
        let credential = try await waitForLiveCredential(timeout: 600)
        let status = await Self.status(for: credential, logFilesNewerThan: session.startedAt)
        try await credentialStore.writeProfileCredential(credential, key: profileKey)
        return status
    }

    func restoreAfterFailedLogin(_ session: AntigravityLoginSession) async {
        try? await credentialStore.deleteLiveCredential()
        if let previous = session.previousLiveCredential {
            try? await credentialStore.writeLiveCredential(previous)
        }
    }

    func activate(
        profileKey: String,
        currentProfileKey: String?,
        expectedEmail: String?
    ) async throws -> AntigravityAuthStatus {
        guard let target = try await credentialStore.readProfileCredential(key: profileKey) else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_login_required"))
        }
        let previous = try await credentialStore.readLiveCredential()
        if let currentProfileKey, let previous {
            try await credentialStore.writeProfileCredential(previous, key: currentProfileKey)
        }

        do {
            try await credentialStore.writeLiveCredential(target)
            guard let verified = try await credentialStore.readLiveCredential(), verified == target else {
                throw LLMAccountSwitcherError.message(L10n.text("switch_verify_mismatch"))
            }
            let status = await Self.status(for: target, fallbackEmail: expectedEmail)
            if let expectedEmail = AccountDeduplicator.normalizedEmail(expectedEmail),
               let actualEmail = AccountDeduplicator.normalizedEmail(status.email),
               expectedEmail != actualEmail {
                throw LLMAccountSwitcherError.message(L10n.text("switch_verify_mismatch"))
            }
            return status
        } catch {
            try? await credentialStore.deleteLiveCredential()
            if let previous { try? await credentialStore.writeLiveCredential(previous) }
            throw error
        }
    }

    func deleteProfile(profileKey: String) async throws {
        try await credentialStore.deleteProfileCredential(key: profileKey)
    }

    func clearLiveCredential() async throws {
        try await credentialStore.deleteLiveCredential()
    }

    func restoreLiveCredentialIfMissing(profileKey: String) async throws {
        guard try await credentialStore.readLiveCredential() == nil else { return }
        guard let saved = try await credentialStore.readProfileCredential(key: profileKey) else {
            throw LLMAccountSwitcherError.message(L10n.text("antigravity_login_required"))
        }
        try await credentialStore.writeLiveCredential(saved)
    }

    private func waitForLiveCredential(timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let credential = try await credentialStore.readLiveCredential(), !credential.isEmpty {
                return credential
            }
            try await Task.sleep(for: .milliseconds(750))
        }
        throw LLMAccountSwitcherError.message(L10n.text("login_timeout"))
    }

    static func status(
        for credential: Data,
        fallbackEmail: String? = nil,
        logFilesNewerThan date: Date? = nil
    ) async -> AntigravityAuthStatus {
        let payload = decodedCredentialPayload(credential)
        var email = recursiveString(in: payload as Any, keys: ["email", "emailAddress"])
        let plan = recursiveString(in: payload as Any, keys: ["plan", "planType", "subscriptionType"])

        if email == nil {
            for key in ["id_token", "access_token"] {
                guard let token = recursiveString(in: payload as Any, keys: [key]),
                      let jwt = decodedJWTPayload(token) else { continue }
                if let value = recursiveString(in: jwt, keys: ["email", "emailAddress"]) {
                    email = value
                    break
                }
            }
        }
        if email == nil { email = fallbackEmail }
        if email == nil,
           let accessToken = recursiveString(in: payload as Any, keys: ["access_token"]) {
            email = await googleUserEmail(accessToken: accessToken)
        }
        if email == nil { email = emailFromRecentLogs(newerThan: date) }

        return AntigravityAuthStatus(
            isLoggedIn: true,
            email: email,
            plan: plan,
            credentialFingerprint: SHA256.hash(data: credential).map { String(format: "%02x", $0) }.joined()
        )
    }

    static func decodedCredentialPayload(_ credential: Data) -> [String: Any]? {
        guard var value = String(data: credential, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("go-keyring-base64:") {
            value.removeFirst("go-keyring-base64:".count)
        }
        let data: Data
        if value.hasPrefix("{") {
            data = Data(value.utf8)
        } else if let decoded = Data(base64Encoded: value) {
            data = decoded
        } else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decodedJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func googleUserEmail(accessToken: String) async -> String? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return object["email"] as? String
    }

    private static func emailFromRecentLogs(newerThan date: Date?) -> String? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/log", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let candidates = files.compactMap { url -> (URL, Date)? in
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date == nil || modified >= date!.addingTimeInterval(-5) else { return nil }
            return (url, modified)
        }.sorted { $0.1 > $1.1 }
        let pattern = #"email=([^,\s]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        for (url, _) in candidates.prefix(8) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = expression.matches(in: text, range: range).last,
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else { continue }
            return String(text[valueRange])
        }
        return nil
    }

    private static func recursiveString(in value: Any, keys: Set<String>) -> String? {
        if let object = value as? [String: Any] {
            for (key, child) in object where keys.contains(key) {
                if let string = child as? String, !string.isEmpty { return string }
            }
            for child in object.values {
                if let match = recursiveString(in: child, keys: keys) { return match }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let match = recursiveString(in: child, keys: keys) { return match }
            }
        }
        return nil
    }
}
