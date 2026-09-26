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
            let destination = applicationSupport.appendingPathComponent("codex-account-manager", isDirectory: true)
            let legacy = applicationSupport.appendingPathComponent("CodexBar", isDirectory: true)
            if !fileManager.fileExists(atPath: destination.path), fileManager.fileExists(atPath: legacy.path) {
                try? fileManager.moveItem(at: legacy, to: destination)
            }
            self.rootDirectory = destination
        }
    }

    var profilesDirectory: URL { rootDirectory.appendingPathComponent("profiles", isDirectory: true) }
    var backupsDirectory: URL { rootDirectory.appendingPathComponent("backups", isDirectory: true) }
    var accountsURL: URL { rootDirectory.appendingPathComponent("accounts.json") }
    var stateURL: URL { rootDirectory.appendingPathComponent("state.json") }

    func prepare() throws {
        try createSecureDirectory(rootDirectory)
        try createSecureDirectory(profilesDirectory)
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

    func createProfile(id: UUID) throws -> URL {
        try prepare()
        let directory = profilesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try createSecureDirectory(directory)
        let config = Data("cli_auth_credentials_store = \"file\"\n".utf8)
        try atomicWrite(config, to: directory.appendingPathComponent("config.toml"), permissions: 0o600)
        return directory
    }

    func profileURL(named name: String) -> URL { profilesDirectory.appendingPathComponent(name, isDirectory: true) }

    func removeProfile(named name: String) throws {
        let url = profileURL(named: name)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
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
            throw CodexAccountManagerError.message(L10n.text("temp_file_failed"))
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
}
