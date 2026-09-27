import Foundation

actor AccountStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let destination = applicationSupport.appendingPathComponent("llm-account-switcher", isDirectory: true)
            let legacyDirectories = ["codex-account-manager", "CodexBar"].map {
                applicationSupport.appendingPathComponent($0, isDirectory: true)
            }
            if !fileManager.fileExists(atPath: destination.path),
               let legacy = legacyDirectories.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                try? fileManager.moveItem(at: legacy, to: destination)
            }
            self.rootDirectory = destination
        }
    }

    var profilesDirectory: URL { rootDirectory.appendingPathComponent("profiles", isDirectory: true) }
    var claudeProfilesDirectory: URL { rootDirectory.appendingPathComponent("claude-profiles", isDirectory: true) }
    var cursorProfilesDirectory: URL { rootDirectory.appendingPathComponent("cursor-profiles", isDirectory: true) }
    var backupsDirectory: URL { rootDirectory.appendingPathComponent("backups", isDirectory: true) }
    var accountsURL: URL { rootDirectory.appendingPathComponent("accounts.json") }
    var claudeAccountsURL: URL { rootDirectory.appendingPathComponent("claude-accounts.json") }
    var cursorAccountsURL: URL { rootDirectory.appendingPathComponent("cursor-accounts.json") }
    var antigravityAccountsURL: URL { rootDirectory.appendingPathComponent("antigravity-accounts.json") }
    var copilotAccountsURL: URL { rootDirectory.appendingPathComponent("copilot-accounts.json") }
    var activeClaudeProfileURL: URL { rootDirectory.appendingPathComponent("active-claude-profile") }
    var claudeBinaryPathURL: URL { rootDirectory.appendingPathComponent("claude-binary-path") }
    var claudeLauncherURL: URL {
        rootDirectory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("claude")
    }
    var activeCursorProfileURL: URL { rootDirectory.appendingPathComponent("active-cursor-profile") }
    var activeCursorCredentialStoreURL: URL { rootDirectory.appendingPathComponent("active-cursor-credential-store") }
    var cursorBinaryPathURL: URL { rootDirectory.appendingPathComponent("cursor-binary-path") }
    var cursorLauncherURL: URL {
        rootDirectory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("agent")
    }
    var antigravityLoginCommandURL: URL {
        rootDirectory.appendingPathComponent("antigravity-login.command")
    }
    var copilotBinaryPathURL: URL { rootDirectory.appendingPathComponent("copilot-binary-path") }
    var copilotLauncherURL: URL {
        rootDirectory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("copilot")
    }
    var stateURL: URL { rootDirectory.appendingPathComponent("state.json") }

    func prepare() throws {
        try createSecureDirectory(rootDirectory)
        try createSecureDirectory(profilesDirectory)
        try createSecureDirectory(claudeProfilesDirectory)
        try createSecureDirectory(cursorProfilesDirectory)
        try createSecureDirectory(backupsDirectory)
    }

    func load() -> ([CodexAccount], AppState) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let accounts = (try? Data(contentsOf: accountsURL)).flatMap { try? decoder.decode([CodexAccount].self, from: $0) } ?? []
        var state = (try? Data(contentsOf: stateURL)).flatMap { try? decoder.decode(AppState.self, from: $0) } ?? AppState()
        guard state.schemaVersion == 1 else { return (accounts, AppState()) }
        if state.nextAccountNumber < 1 { state.nextAccountNumber = 1 }
        return (accounts, state)
    }

    func save(accounts: [CodexAccount], state: AppState) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(accounts), to: accountsURL, permissions: 0o600)
        try atomicWrite(try encoder.encode(state), to: stateURL, permissions: 0o600)
    }

    func loadClaudeAccounts() -> [ClaudeAccount] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: claudeAccountsURL))
            .flatMap { try? decoder.decode([ClaudeAccount].self, from: $0) } ?? []
    }

    func saveClaudeAccounts(_ accounts: [ClaudeAccount], state: AppState) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(accounts), to: claudeAccountsURL, permissions: 0o600)
        try atomicWrite(try encoder.encode(state), to: stateURL, permissions: 0o600)
    }

    func loadCursorAccounts() -> [CursorAccount] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: cursorAccountsURL))
            .flatMap { try? decoder.decode([CursorAccount].self, from: $0) } ?? []
    }

    func saveCursorAccounts(_ accounts: [CursorAccount], state: AppState) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(accounts), to: cursorAccountsURL, permissions: 0o600)
        try atomicWrite(try encoder.encode(state), to: stateURL, permissions: 0o600)
    }

    func loadAntigravityAccounts() -> [AntigravityAccount] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: antigravityAccountsURL))
            .flatMap { try? decoder.decode([AntigravityAccount].self, from: $0) } ?? []
    }

    func saveAntigravityAccounts(_ accounts: [AntigravityAccount], state: AppState) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(accounts), to: antigravityAccountsURL, permissions: 0o600)
        try atomicWrite(try encoder.encode(state), to: stateURL, permissions: 0o600)
    }

    func loadCopilotAccounts() -> [CopilotAccount] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: copilotAccountsURL))
            .flatMap { try? decoder.decode([CopilotAccount].self, from: $0) } ?? []
    }

    func saveCopilotAccounts(_ accounts: [CopilotAccount], state: AppState) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(accounts), to: copilotAccountsURL, permissions: 0o600)
        try atomicWrite(try encoder.encode(state), to: stateURL, permissions: 0o600)
    }

    func createProfile(id: UUID) throws -> URL {
        try prepare()
        let directory = profilesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try createSecureDirectory(directory)
        let config = Data("cli_auth_credentials_store = \"file\"\n".utf8)
        try atomicWrite(config, to: directory.appendingPathComponent("config.toml"), permissions: 0o600)
        return directory
    }

    func createClaudeProfile(id: UUID) throws -> URL {
        try prepare()
        let directory = claudeProfilesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try createSecureDirectory(directory)
        return directory
    }

    func createCursorProfile(id: UUID) throws -> URL {
        try prepare()
        let directory = cursorProfilesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try createSecureDirectory(directory)
        return directory
    }

    func profileURL(named name: String) -> URL { profilesDirectory.appendingPathComponent(name, isDirectory: true) }
    func claudeProfileURL(named name: String) -> URL {
        claudeProfilesDirectory.appendingPathComponent(name, isDirectory: true)
    }
    func cursorProfileURL(named name: String) -> URL {
        cursorProfilesDirectory.appendingPathComponent(name, isDirectory: true)
    }

    func removeProfile(named name: String) throws {
        let url = profileURL(named: name)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func removeClaudeProfile(named name: String) throws {
        let url = claudeProfileURL(named: name)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func removeCursorProfile(named name: String) throws {
        let url = cursorProfileURL(named: name)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func setActiveClaudeProfile(_ profile: URL) throws {
        try atomicWrite(Data((profile.path + "\n").utf8), to: activeClaudeProfileURL, permissions: 0o600)
    }

    func prepareClaudeLauncher(binaryPath: String) throws -> URL {
        try prepare()
        try atomicWrite(Data((binaryPath + "\n").utf8), to: claudeBinaryPathURL, permissions: 0o600)
        let script = """
        #!/bin/zsh
        set -euo pipefail
        ROOT_DIR="${0:A:h:h}"
        BINARY_PATH="$(<\"$ROOT_DIR/claude-binary-path\")"
        PROFILE_PATH="$(<\"$ROOT_DIR/active-claude-profile\")"
        if [[ -z "$BINARY_PATH" || -z "$PROFILE_PATH" ]]; then
            print -u2 "LLM Account Switcher: no active Claude account"
            exit 1
        fi
        exec env CLAUDE_CONFIG_DIR="$PROFILE_PATH" "$BINARY_PATH" "$@"
        """
        try atomicWrite(Data(script.utf8), to: claudeLauncherURL, permissions: 0o700)
        return claudeLauncherURL
    }

    func setActiveCursorProfile(_ profile: URL, usesFileCredentialStore: Bool) throws {
        try atomicWrite(Data((profile.path + "\n").utf8), to: activeCursorProfileURL, permissions: 0o600)
        let credentialStore = usesFileCredentialStore ? "file" : "keychain"
        try atomicWrite(Data((credentialStore + "\n").utf8), to: activeCursorCredentialStoreURL, permissions: 0o600)
    }

    func prepareCursorLauncher(binaryPath: String) throws -> URL {
        try prepare()
        try atomicWrite(Data((binaryPath + "\n").utf8), to: cursorBinaryPathURL, permissions: 0o600)
        let script = """
        #!/bin/zsh
        set -euo pipefail
        ROOT_DIR="${0:A:h:h}"
        BINARY_PATH="$(<\"$ROOT_DIR/cursor-binary-path\")"
        PROFILE_PATH="$(<\"$ROOT_DIR/active-cursor-profile\")"
        CREDENTIAL_STORE="$(<\"$ROOT_DIR/active-cursor-credential-store\")"
        if [[ -z "$BINARY_PATH" || -z "$PROFILE_PATH" || -z "$CREDENTIAL_STORE" ]]; then
            print -u2 "LLM Account Switcher: no active Cursor account"
            exit 1
        fi
        if [[ "$CREDENTIAL_STORE" == "keychain" ]]; then
            exec env -u AGENT_CLI_CREDENTIAL_STORE CURSOR_CONFIG_DIR="$PROFILE_PATH" "$BINARY_PATH" "$@"
        fi
        exec env CURSOR_CONFIG_DIR="$PROFILE_PATH" AGENT_CLI_CREDENTIAL_STORE=file "$BINARY_PATH" "$@"
        """
        try atomicWrite(Data(script.utf8), to: cursorLauncherURL, permissions: 0o700)
        return cursorLauncherURL
    }

    func removeCursorLauncher() throws {
        for url in [cursorBinaryPathURL, cursorLauncherURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func prepareAntigravityLoginCommand(binaryPath: String) throws -> URL {
        try prepare()
        let escapedPath = shellQuote(binaryPath)
        let script = """
        #!/bin/zsh
        clear
        print "LLM Account Switcher"
        print "Complete the Antigravity sign-in, then leave this window open until the account appears in the app."
        print
        \(escapedPath)
        """
        try atomicWrite(Data(script.utf8), to: antigravityLoginCommandURL, permissions: 0o700)
        return antigravityLoginCommandURL
    }

    func prepareCopilotLauncher(binaryPath: String) throws -> URL {
        try prepare()
        try atomicWrite(Data((binaryPath + "\n").utf8), to: copilotBinaryPathURL, permissions: 0o600)
        let script = """
        #!/bin/zsh
        set -euo pipefail
        ROOT_DIR="${0:A:h:h}"
        BINARY_PATH="$(<\"$ROOT_DIR/copilot-binary-path\")"
        if [[ -z "$BINARY_PATH" ]]; then
            print -u2 "LLM Account Switcher: no GitHub Copilot binary"
            exit 1
        fi
        exec env -u COPILOT_GITHUB_TOKEN -u GH_TOKEN -u GITHUB_TOKEN "$BINARY_PATH" "$@"
        """
        try atomicWrite(Data(script.utf8), to: copilotLauncherURL, permissions: 0o700)
        return copilotLauncherURL
    }

    func copyCredential(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        try atomicWrite(data, to: destination, permissions: 0o600)
    }

    func atomicWrite(_ data: Data, to destination: URL, permissions: Int) throws {
        try createSecureDirectory(destination.deletingLastPathComponent())
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: permissions]) else {
            throw LLMAccountSwitcherError.message(L10n.text("temp_file_failed"))
        }
        defer { try? fileManager.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
    }

    private func createSecureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
