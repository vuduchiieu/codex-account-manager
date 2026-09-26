import Foundation
import Testing
@testable import CodexAccountManager

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
}
