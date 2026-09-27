import Foundation
import Testing
@testable import LLMAccountSwitcher

struct AntigravityAccountServiceTests {
    @Test func parsesOpaqueKeychainPayloadWithoutExposingToken() async throws {
        let credential = credential(email: "royal@example.com", marker: "one")
        let status = await AntigravityAccountService.status(for: credential)

        #expect(status.isLoggedIn)
        #expect(status.email == "royal@example.com")
        #expect(status.credentialFingerprint.count == 64)
        #expect(AntigravityAccountService.decodedCredentialPayload(credential) != nil)
    }

    @Test func switchesKeychainCredentialAndSnapshotsCurrentAccount() async throws {
        let first = credential(email: "first@example.com", marker: "first")
        let second = credential(email: "second@example.com", marker: "second")
        let store = FakeAntigravityCredentialStore(
            live: first,
            profiles: ["first": first, "second": second]
        )
        let service = AntigravityAccountService(credentialStore: store)

        let status = try await service.activate(
            profileKey: "second",
            currentProfileKey: "first",
            expectedEmail: "second@example.com"
        )

        #expect(status.email == "second@example.com")
        #expect(await store.liveCredential() == second)
        #expect(await store.profileCredential(key: "first") == first)
    }

    @Test func rollsBackWhenKeychainVerificationFails() async throws {
        let first = credential(email: "first@example.com", marker: "first")
        let second = credential(email: "second@example.com", marker: "second")
        let store = FakeAntigravityCredentialStore(
            live: first,
            profiles: ["first": first, "second": second],
            corruptNextLiveWrite: true
        )
        let service = AntigravityAccountService(credentialStore: store)

        await #expect(throws: (any Error).self) {
            try await service.activate(
                profileKey: "second",
                currentProfileKey: "first",
                expectedEmail: "second@example.com"
            )
        }
        #expect(await store.liveCredential() == first)
    }

    private func credential(email: String, marker: String) -> Data {
        let object: [String: Any] = [
            "token": [
                "access_token": "access-\(marker)",
                "refresh_token": "refresh-\(marker)",
            ],
            "email": email,
            "auth_method": "consumer",
        ]
        let json = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return Data(("go-keyring-base64:" + json.base64EncodedString()).utf8)
    }
}

private actor FakeAntigravityCredentialStore: AntigravityCredentialStoring {
    private var live: Data?
    private var profiles: [String: Data]
    private var corruptNextLiveWrite: Bool

    init(live: Data?, profiles: [String: Data], corruptNextLiveWrite: Bool = false) {
        self.live = live
        self.profiles = profiles
        self.corruptNextLiveWrite = corruptNextLiveWrite
    }

    func readLiveCredential() async throws -> Data? { live }

    func writeLiveCredential(_ credential: Data) async throws {
        if corruptNextLiveWrite {
            corruptNextLiveWrite = false
            live = Data("corrupt".utf8)
        } else {
            live = credential
        }
    }

    func deleteLiveCredential() async throws { live = nil }
    func readProfileCredential(key: String) async throws -> Data? { profiles[key] }
    func writeProfileCredential(_ credential: Data, key: String) async throws { profiles[key] = credential }
    func deleteProfileCredential(key: String) async throws { profiles[key] = nil }

    func liveCredential() -> Data? { live }
    func profileCredential(key: String) -> Data? { profiles[key] }
}
