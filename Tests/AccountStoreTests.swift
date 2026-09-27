import Foundation
import Testing
@testable import LLMAccountSwitcher

struct AccountStoreTests {
    @Test func saveLoadAndCorruptJSON() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root)
        var state = AppState()
        state.nextAccountNumber = 7
        let account = CodexAccount(id: UUID(), displayName: "Work", email: "work@example.com", rawPlan: "pro",
                                   profileDirectoryName: "profile", isActive: true, usage: nil,
                                   lastRefreshAt: nil, lastSuccessfulRefreshAt: nil, lastError: nil)
        try await store.save(accounts: [account], state: state)
        let loaded = await store.load()
        #expect(loaded.0 == [account])
        #expect(loaded.1.nextAccountNumber == 7)
        try Data("not json".utf8).write(to: await store.accountsURL)
        #expect(await store.load().0.isEmpty)
    }

    @Test func storesAntigravityMetadataWithoutCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root)
        let account = AntigravityAccount(
            id: UUID(),
            displayName: "Antigravity 1",
            email: "user@example.com",
            rawPlan: nil,
            credentialKey: UUID().uuidString,
            credentialFingerprint: String(repeating: "a", count: 64),
            isActive: true,
            lastRefreshAt: Date(timeIntervalSince1970: 1_000)
        )
        var state = AppState()
        state.activeAntigravityAccountId = account.id

        try await store.saveAntigravityAccounts([account], state: state)

        #expect(await store.loadAntigravityAccounts() == [account])
        let raw = try String(contentsOf: await store.antigravityAccountsURL, encoding: .utf8)
        #expect(!raw.contains("access_token"))
        #expect(!raw.contains("refresh_token"))
    }

    @Test func storesCopilotIdentityWithoutCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root)
        let account = CopilotAccount(
            id: UUID(),
            displayName: "octocat",
            login: "octocat",
            host: "https://github.com",
            isActive: true,
            lastRefreshAt: Date(timeIntervalSince1970: 1_000)
        )
        var state = AppState()
        state.activeCopilotAccountId = account.id

        try await store.saveCopilotAccounts([account], state: state)

        #expect(await store.loadCopilotAccounts() == [account])
        let raw = try String(contentsOf: await store.copilotAccountsURL, encoding: .utf8)
        #expect(!raw.lowercased().contains("token"))
    }

    @Test func copilotLauncherUsesSelectedCLIIdentityInsteadOfEnvironmentTokens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root)

        let launcher = try await store.prepareCopilotLauncher(binaryPath: "/tmp/copilot")
        let script = try String(contentsOf: launcher, encoding: .utf8)
        let savedBinary = try String(contentsOf: await store.copilotBinaryPathURL, encoding: .utf8)

        #expect(savedBinary.trimmingCharacters(in: .whitespacesAndNewlines) == "/tmp/copilot")
        #expect(script.contains("-u COPILOT_GITHUB_TOKEN"))
        #expect(script.contains("-u GH_TOKEN"))
        #expect(script.contains("-u GITHUB_TOKEN"))
    }
}
