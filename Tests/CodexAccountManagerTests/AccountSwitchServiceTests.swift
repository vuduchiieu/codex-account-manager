import Foundation
import Testing
@testable import CodexAccountManager

struct AccountSwitchServiceTests {
    @Test func switchesAndBacksUpAtomically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("default")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root.appendingPathComponent("store"))
        let id = UUID()
        let profile = try await store.createProfile(id: id)
        try await store.atomicWrite(Data("target".utf8), to: profile.appendingPathComponent("auth.json"), permissions: 0o600)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: home.appendingPathComponent("auth.json"))
        let authURL = home.appendingPathComponent("auth.json")
        let switcher = AccountSwitchService(store: store, defaultCodexHome: home) { _ in
            let value = String(data: try Data(contentsOf: authURL), encoding: .utf8)
            return RemoteAccount(email: value == "target" ? "target@example.com" : "original@example.com", plan: nil, accountType: "chatgpt")
        }
        let target = CodexAccount(id: id, displayName: "Target", email: "target@example.com", rawPlan: nil,
                                  profileDirectoryName: id.uuidString, isActive: false, usage: nil,
                                  lastRefreshAt: nil, lastSuccessfulRefreshAt: nil, lastError: nil)
        _ = try await switcher.switchAccount(from: nil, to: target)
        #expect(String(data: try Data(contentsOf: authURL), encoding: .utf8) == "target")
        let backup = await store.backupsDirectory.appendingPathComponent("pre-codex-account-manager-auth.json")
        #expect(String(data: try Data(contentsOf: backup), encoding: .utf8) == "original")
    }

    @Test func rollsBackWhenIdentityDoesNotMatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("default")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root.appendingPathComponent("store"))
        let id = UUID(), profile = try await store.createProfile(id: id)
        try await store.atomicWrite(Data("target".utf8), to: profile.appendingPathComponent("auth.json"), permissions: 0o600)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let authURL = home.appendingPathComponent("auth.json")
        try Data("original".utf8).write(to: authURL)
        let switcher = AccountSwitchService(store: store, defaultCodexHome: home) { _ in
            RemoteAccount(email: "wrong@example.com", plan: nil, accountType: "chatgpt")
        }
        let target = CodexAccount(id: id, displayName: "Target", email: "target@example.com", rawPlan: nil,
                                  profileDirectoryName: id.uuidString, isActive: false, usage: nil,
                                  lastRefreshAt: nil, lastSuccessfulRefreshAt: nil, lastError: nil)
        await #expect(throws: Error.self) { try await switcher.switchAccount(from: nil, to: target) }
        #expect(String(data: try Data(contentsOf: authURL), encoding: .utf8) == "original")
    }
}
