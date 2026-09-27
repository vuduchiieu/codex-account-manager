import Foundation
import OSLog

actor AccountSwitchService {
    typealias Verifier = @Sendable (URL?) async throws -> RemoteAccount

    private let store: AccountStore
    private let defaultCodexHome: URL
    private let verifier: Verifier
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "local.llm-account-switcher.app", category: "switch")

    init(store: AccountStore, defaultCodexHome: URL? = nil, fileManager: FileManager = .default, verifier: @escaping Verifier) {
        self.store = store
        self.fileManager = fileManager
        self.defaultCodexHome = defaultCodexHome ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        self.verifier = verifier
    }

    func switchAccount(from current: CodexAccount?, to target: CodexAccount) async throws -> Date? {
        let defaultAuth = defaultCodexHome.appendingPathComponent("auth.json")
        let targetAuth = await store.profileURL(named: target.profileDirectoryName).appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: targetAuth.path) else {
            throw LLMAccountSwitcherError.message(L10n.text("target_auth_missing"))
        }
        try fileManager.createDirectory(at: defaultCodexHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        if let current, fileManager.fileExists(atPath: defaultAuth.path) {
            let identity = try await verifier(nil)
            guard identitiesMatch(identity.email, current.email) else {
                throw LLMAccountSwitcherError.message(L10n.text("external_active_error"))
            }
            let currentAuth = await store.profileURL(named: current.profileDirectoryName).appendingPathComponent("auth.json")
            try await store.copyCredential(from: defaultAuth, to: currentAuth)
        }

        // Verify and refresh the destination profile before replacing the active auth file.
        // This prevents a stale profile from momentarily becoming the user's default account.
        let targetIdentity = try await verifier(targetAuth.deletingLastPathComponent())
        guard identitiesMatch(targetIdentity.email, target.email) else {
            throw LLMAccountSwitcherError.message(L10n.text("switch_verify_mismatch"))
        }

        let backup = await store.backupsDirectory.appendingPathComponent("pre-llm-account-switcher-codex-auth.json")
        if fileManager.fileExists(atPath: defaultAuth.path), !fileManager.fileExists(atPath: backup.path) {
            try await store.copyCredential(from: defaultAuth, to: backup)
        }
        let previousData = try? Data(contentsOf: defaultAuth)
        do {
            try await store.copyCredential(from: targetAuth, to: defaultAuth)
            let identity = try await verifier(nil)
            guard identitiesMatch(identity.email, target.email) else {
                throw LLMAccountSwitcherError.message(L10n.text("switch_verify_mismatch"))
            }
            // Codex may renew the access token while verifying. Keep the managed
            // profile in sync with the renewed default credentials.
            try await store.copyCredential(from: defaultAuth, to: targetAuth)
            logger.info("Chuyển tài khoản thành công: \(target.id.uuidString, privacy: .public)")
            return try? defaultAuth.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch {
            if let previousData { try? await store.atomicWrite(previousData, to: defaultAuth, permissions: 0o600) }
            logger.error("Chuyển tài khoản thất bại, đã rollback: \(target.id.uuidString, privacy: .public)")
            throw error
        }
    }

    func syncOnTermination(active: CodexAccount) async {
        let defaultAuth = defaultCodexHome.appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: defaultAuth.path),
              let identity = try? await verifier(nil), identitiesMatch(identity.email, active.email) else { return }
        let profileAuth = await store.profileURL(named: active.profileDirectoryName).appendingPathComponent("auth.json")
        try? await store.copyCredential(from: defaultAuth, to: profileAuth)
    }

    private func identitiesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}
