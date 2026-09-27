import Foundation
import Testing
@testable import LLMAccountSwitcher

struct CursorAccountServiceTests {
    @Test func parsesLoggedInAndLoggedOutStatus() {
        let loggedIn = CursorAccountService.parseStatus(
            "Login successful!\nLogged in as work@example.com\nPlan: Pro"
        )
        #expect(loggedIn == CursorAuthStatus(
            isLoggedIn: true,
            email: "work@example.com",
            plan: "Pro"
        ))

        let loggedOut = CursorAccountService.parseStatus("Not logged in. Run agent login.")
        #expect(!loggedOut.isLoggedIn)
        #expect(loggedOut.email == nil)
    }

    @Test func loginAndStatusUseAnIsolatedCursorConfigDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("agent")
        let body = #"""
        #!/bin/zsh
        set -euo pipefail
        if [[ "${1:-}" == "--version" ]]; then
          print "2026.09.1"
          exit 0
        fi
        if [[ "${1:-}" == "login" ]]; then
          [[ "${AGENT_CLI_CREDENTIAL_STORE:-}" == "file" ]]
          mkdir -p "$CURSOR_CONFIG_DIR"
          print 'Logged in as cursor@example.com\nPlan: Pro' > "$CURSOR_CONFIG_DIR/status.txt"
          exit 0
        fi
        if [[ "${1:-}" == "status" ]]; then
          [[ -n "${CURSOR_CONFIG_DIR:-}" ]]
          [[ "${AGENT_CLI_CREDENTIAL_STORE:-}" == "file" ]]
          cat "$CURSOR_CONFIG_DIR/status.txt"
          exit 0
        fi
        exit 2
        """#
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let profile = root.appendingPathComponent("profile", isDirectory: true)
        let service = CursorAccountService(binaryPath: script.path)
        let status = try await service.login(profile: profile)

        #expect(status.isLoggedIn)
        #expect(status.email == "cursor@example.com")
        #expect(status.plan == "Pro")
        #expect(FileManager.default.fileExists(atPath: profile.appendingPathComponent("status.txt").path))
    }

    @Test func storePersistsCursorAccountsAndBuildsManagedLauncher() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root)
        let id = UUID()
        let account = CursorAccount(
            id: id,
            displayName: "Cursor 1",
            email: "one@example.com",
            rawPlan: "pro",
            profileDirectoryName: id.uuidString,
            usesDefaultProfile: false,
            usesFileCredentialStore: true,
            isActive: true,
            lastRefreshAt: Date(timeIntervalSince1970: 1_000)
        )
        var state = AppState()
        state.activeCursorAccountId = id
        try await store.saveCursorAccounts([account], state: state)
        #expect(await store.loadCursorAccounts() == [account])

        let profile = try await store.createCursorProfile(id: id)
        try await store.setActiveCursorProfile(profile, usesFileCredentialStore: true)
        let launcher = try await store.prepareCursorLauncher(binaryPath: "/usr/local/bin/agent")
        let activePath = try String(contentsOf: await store.activeCursorProfileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let launcherText = try String(contentsOf: launcher, encoding: .utf8)
        #expect(activePath == profile.path)
        #expect(launcherText.contains("CURSOR_CONFIG_DIR"))
        #expect(launcherText.contains("cursor-binary-path"))
        #expect(launcherText.contains("AGENT_CLI_CREDENTIAL_STORE=file"))

        try await store.removeCursorLauncher()
        #expect(!FileManager.default.fileExists(atPath: launcher.path))
        #expect(!FileManager.default.fileExists(atPath: await store.cursorBinaryPathURL.path))
    }
}
