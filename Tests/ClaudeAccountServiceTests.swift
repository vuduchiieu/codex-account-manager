import Foundation
import Testing
@testable import LLMAccountSwitcher

struct ClaudeAccountServiceTests {
    @Test func parsesCurrentAndNestedAuthStatusJSON() throws {
        let current = try ClaudeAccountService.parseStatus(
            #"{"loggedIn":true,"authMethod":"claude.ai","email":"max@example.com","subscriptionType":"max"}"#
        )
        #expect(current == ClaudeAuthStatus(
            isLoggedIn: true,
            email: "max@example.com",
            plan: "max",
            authMethod: "claude.ai"
        ))

        let nested = try ClaudeAccountService.parseStatus(
            #"{"account":{"isLoggedIn":true,"emailAddress":"team@example.com","planType":"team"}}"#
        )
        #expect(nested.isLoggedIn)
        #expect(nested.email == "team@example.com")
        #expect(nested.plan == "team")
    }

    @Test func loginAndStatusUseAnIsolatedClaudeConfigDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("claude")
        let body = #"""
        #!/bin/zsh
        set -euo pipefail
        if [[ "${1:-}" == "--version" ]]; then
          print "2.1.0"
          exit 0
        fi
        if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
          mkdir -p "$CLAUDE_CONFIG_DIR"
          print '{"loggedIn":true,"email":"work@example.com","subscriptionType":"pro","authMethod":"claude.ai"}' > "$CLAUDE_CONFIG_DIR/status.json"
          exit 0
        fi
        if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
          [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]
          cat "$CLAUDE_CONFIG_DIR/status.json"
          exit 0
        fi
        exit 2
        """#
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let profile = root.appendingPathComponent("profile", isDirectory: true)
        let service = ClaudeAccountService(binaryPath: script.path)
        let status = try await service.login(profile: profile)

        #expect(status.isLoggedIn)
        #expect(status.email == "work@example.com")
        #expect(status.plan == "pro")
        #expect(FileManager.default.fileExists(atPath: profile.appendingPathComponent("status.json").path))
    }

    @Test func storePersistsClaudeAccountsAndActiveLauncherProfile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(rootDirectory: root)
        let id = UUID()
        let account = ClaudeAccount(
            id: id,
            displayName: "Claude 1",
            email: "one@example.com",
            rawPlan: "max",
            authMethod: "claude.ai",
            profileDirectoryName: id.uuidString,
            usesDefaultProfile: false,
            isActive: true,
            lastRefreshAt: Date(timeIntervalSince1970: 1_000)
        )
        var state = AppState()
        state.activeClaudeAccountId = id
        try await store.saveClaudeAccounts([account], state: state)
        #expect(await store.loadClaudeAccounts() == [account])

        let profile = try await store.createClaudeProfile(id: id)
        try await store.setActiveClaudeProfile(profile)
        let launcher = try await store.prepareClaudeLauncher(binaryPath: "/usr/local/bin/claude")
        let activePath = try String(contentsOf: await store.activeClaudeProfileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let launcherText = try String(contentsOf: launcher, encoding: .utf8)
        #expect(activePath == profile.path)
        #expect(launcherText.contains("CLAUDE_CONFIG_DIR"))
        #expect(launcherText.contains("claude-binary-path"))
    }
}
