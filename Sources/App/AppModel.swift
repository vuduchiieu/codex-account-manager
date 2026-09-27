import AppKit
import Foundation
import Observation
import OSLog

actor RefreshGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() }
    }
}

@MainActor @Observable
final class AppModel {
    var accounts: [CodexAccount] = []
    var claudeAccounts: [ClaudeAccount] = []
    var cursorAccounts: [CursorAccount] = []
    var antigravityAccounts: [AntigravityAccount] = []
    var copilotAccounts: [CopilotAccount] = []
    var state = AppState()
    var codexVersion: String?
    var claudeVersion: String?
    var claudeLauncherPath: String?
    var cursorVersion: String?
    var cursorLauncherPath: String?
    var copilotVersion: String?
    var copilotLauncherPath: String?
    var resolvingProviderBinaries: Set<LLMProvider> = []
    var isLoading = true
    var isAddingAccount = false
    var isImportingAccount = false
    var loginMessageKey: String?
    var refreshingIDs: Set<UUID> = []
    var processingIDs: Set<UUID> = []
    var switchingAccountID: UUID?
    var isAddingClaudeAccount = false
    var isImportingClaudeAccount = false
    var refreshingClaudeIDs: Set<UUID> = []
    var processingClaudeIDs: Set<UUID> = []
    var switchingClaudeAccountID: UUID?
    var isAddingCursorAccount = false
    var isImportingCursorAccount = false
    var refreshingCursorIDs: Set<UUID> = []
    var processingCursorIDs: Set<UUID> = []
    var switchingCursorAccountID: UUID?
    var isAddingAntigravityAccount = false
    var isImportingAntigravityAccount = false
    var refreshingAntigravityIDs: Set<UUID> = []
    var processingAntigravityIDs: Set<UUID> = []
    var switchingAntigravityAccountID: UUID?
    var isAddingCopilotAccount = false
    var isImportingCopilotAccount = false
    var refreshingCopilotIDs: Set<UUID> = []
    var processingCopilotIDs: Set<UUID> = []
    var switchingCopilotAccountID: UUID?
    var externalAccountDetected = false

    private let store: AccountStore
    private let resolver = CodexBinaryResolver()
    private let claudeResolver = ClaudeBinaryResolver()
    private let cursorResolver = CursorBinaryResolver()
    private let antigravityResolver = AntigravityBinaryResolver()
    private let copilotResolver = CopilotBinaryResolver()
    private let antigravityAccountService = AntigravityAccountService()
    private let claudeEnvironmentService = ClaudeEnvironmentService()
    private let refreshGate = RefreshGate(limit: 2)
    private let launchService = LaunchAtLoginService()
    private let codexDesktopRelaunchService = CodexDesktopRelaunchService()
    private let quotaResetNotificationService = QuotaResetNotificationService()
    private let logger = Logger(subsystem: "local.llm-account-switcher.app", category: "model")
    private var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private var loginTask: Task<Void, Never>?
    private var claudeLoginTask: Task<Void, Never>?
    private var cursorLoginTask: Task<Void, Never>?
    private var antigravityLoginTask: Task<Void, Never>?
    private var copilotLoginTask: Task<Void, Never>?
    private var loginClient: CodexAppServerClient?
    private var loginID: String?
    private var activityMonitor: CodexActivityMonitor?
    private var quotaResetTask: Task<Void, Never>?

    init(store: AccountStore = AccountStore()) {
        self.store = store
        Task { await load() }
    }

    var activeAccount: CodexAccount? { accounts.first(where: \.isActive) }
    var activeClaudeAccount: ClaudeAccount? { claudeAccounts.first(where: \.isActive) }
    var activeCursorAccount: CursorAccount? { cursorAccounts.first(where: \.isActive) }
    var activeAntigravityAccount: AntigravityAccount? { antigravityAccounts.first(where: \.isActive) }
    var activeCopilotAccount: CopilotAccount? { copilotAccounts.first(where: \.isActive) }
    var needsOnboarding: Bool { state.onboardingCompleted != true }
    var quotaResetNotificationsEnabled: Bool { state.quotaResetNotificationsEnabled != false }
    var languageOverride: AppLanguage? { state.languageOverride }
    var canImportCurrentAccount: Bool {
        FileManager.default.fileExists(atPath: defaultAuthURL.path)
    }
    var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }
    var defaultClaudeConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
    var defaultCursorConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true)
    }

    func load() async {
        let loaded = await store.load()
        claudeAccounts = await store.loadClaudeAccounts()
        cursorAccounts = await store.loadCursorAccounts()
        antigravityAccounts = await store.loadAntigravityAccounts()
        copilotAccounts = await store.loadCopilotAccounts()
        let deduplicated = AccountDeduplicator.split(loaded.0)
        accounts = deduplicated.unique
        state = loaded.1
        clearUnavailableBinaryPaths()
        if state.onboardingCompleted == nil {
            state.onboardingCompleted = !accounts.isEmpty || !claudeAccounts.isEmpty
                || !cursorAccounts.isEmpty || !antigravityAccounts.isEmpty || !copilotAccounts.isEmpty
        }
        LocalizationManager.shared.setLanguageOverride(state.languageOverride)
        if !deduplicated.duplicates.isEmpty {
            for duplicate in deduplicated.duplicates {
                try? await store.removeProfile(named: duplicate.profileDirectoryName)
            }
            state.activeAccountId = accounts.first(where: \.isActive)?.id
            try? await persist()
            logger.info("Đã dọn \(deduplicated.duplicates.count) profile tài khoản trùng")
        }
        enableLaunchAtLoginByDefaultIfNeeded()
        state.launchAtLogin = launchService.isEnabled
        await resolveBinary()
        await resolveClaudeBinary()
        await resolveCursorBinary()
        await resolveAntigravityBinary()
        await resolveCopilotBinary()
        await reconcileActiveAccount()
        await reconcileClaudeAccounts()
        await reconcileCursorAccounts()
        await reconcileAntigravityAccounts()
        await reconcileCopilotAccounts()
        await advanceExpiredQuotaWindows()
        isLoading = false
        if !accounts.isEmpty, quotaResetNotificationsEnabled {
            quotaResetNotificationService.requestAuthorization()
        }
        if CommandLine.arguments.contains("--test-notification") {
            quotaResetNotificationService.sendTestNotification(
                accountName: activeAccount?.email ?? accounts.first?.email ?? "example@llm-account-switcher.app",
                language: LocalizationManager.shared.language
            )
        }
        startActivityMonitoring()
    }

    func menuOpened() {
        let unavailableProviders = clearUnavailableBinaryPaths()
        Task {
            if !unavailableProviders.isEmpty {
                if unavailableProviders.contains(.cursor) {
                    try? await store.removeCursorLauncher()
                }
                try? await persistAll()
            }
            guard !isLoading else { return }
            await checkExternalChange()
            if let id = activeClaudeAccount?.id { refreshClaude(id) }
            if let id = activeCursorAccount?.id { refreshCursor(id) }
            if let id = activeAntigravityAccount?.id { refreshAntigravity(id) }
            if let id = activeCopilotAccount?.id { refreshCopilot(id) }
        }
    }

    @discardableResult
    func resolveBinary(manualPath: String? = nil) async -> Bool {
        resolvingProviderBinaries.insert(.codex)
        defer { resolvingProviderBinaries.remove(.codex) }
        if CommandLine.arguments.contains("--simulate-no-codex") {
            state.codexBinaryPath = nil
            codexVersion = nil
            return false
        }
        let info: CodexBinaryInfo?
        if let manualPath {
            guard let version = await resolver.verify(path: manualPath) else {
                return false
            }
            info = CodexBinaryInfo(path: manualPath, version: version)
        } else {
            info = await resolver.resolve(savedPath: state.codexBinaryPath)
        }
        state.codexBinaryPath = info?.path
        codexVersion = info?.version
        try? await persist()
        return info != nil
    }

    func chooseBinary() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("select_binary_title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task {
            let resolved = await resolveBinary(manualPath: path)
            if !resolved { showMessage(L10n.text("invalid_binary")) }
        }
    }

    @discardableResult
    func resolveClaudeBinary(manualPath: String? = nil) async -> Bool {
        resolvingProviderBinaries.insert(.claude)
        defer { resolvingProviderBinaries.remove(.claude) }
        let info: ClaudeBinaryInfo?
        if let manualPath {
            guard let version = await claudeResolver.verify(path: manualPath) else {
                return false
            }
            info = ClaudeBinaryInfo(path: manualPath, version: version)
        } else {
            info = await claudeResolver.resolve(savedPath: state.claudeBinaryPath)
        }
        state.claudeBinaryPath = info?.path
        claudeVersion = info?.version
        if let path = info?.path {
            if let launcher = try? await store.prepareClaudeLauncher(binaryPath: path) {
                claudeLauncherPath = launcher.path
            } else {
                claudeLauncherPath = nil
            }
        } else {
            claudeLauncherPath = nil
        }
        try? await persistAll()
        return info != nil
    }

    func chooseClaudeBinary() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("select_claude_binary_title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task {
            let resolved = await resolveClaudeBinary(manualPath: path)
            if !resolved { showMessage(L10n.text("invalid_claude_binary")) }
        }
    }

    @discardableResult
    func resolveCursorBinary(manualPath: String? = nil) async -> Bool {
        resolvingProviderBinaries.insert(.cursor)
        defer { resolvingProviderBinaries.remove(.cursor) }
        let info: CursorBinaryInfo?
        if let manualPath {
            guard let version = await cursorResolver.verify(path: manualPath) else {
                return false
            }
            info = CursorBinaryInfo(path: manualPath, version: version)
        } else {
            info = await cursorResolver.resolve(savedPath: state.cursorBinaryPath)
        }
        state.cursorBinaryPath = info?.path
        cursorVersion = info?.version
        if let path = info?.path {
            cursorLauncherPath = try? await store.prepareCursorLauncher(binaryPath: path).path
        } else {
            cursorLauncherPath = nil
            try? await store.removeCursorLauncher()
        }
        try? await persistAll()
        return info != nil
    }

    func chooseCursorBinary() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("select_cursor_binary_title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task {
            let resolved = await resolveCursorBinary(manualPath: path)
            if !resolved { showMessage(L10n.text("invalid_cursor_binary")) }
        }
    }

    @discardableResult
    func resolveAntigravityBinary(manualPath: String? = nil) async -> Bool {
        resolvingProviderBinaries.insert(.antigravity)
        defer { resolvingProviderBinaries.remove(.antigravity) }
        let info: AntigravityBinaryInfo?
        if let manualPath {
            guard let version = await antigravityResolver.verify(path: manualPath) else { return false }
            info = AntigravityBinaryInfo(path: manualPath, version: version)
        } else {
            info = await antigravityResolver.resolve(savedPath: state.antigravityBinaryPath)
        }
        state.antigravityBinaryPath = info?.path
        try? await persistAll()
        return info != nil
    }

    func chooseAntigravityBinary() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("select_antigravity_binary_title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task {
            let resolved = await resolveAntigravityBinary(manualPath: path)
            if !resolved { showMessage(L10n.text("invalid_antigravity_binary")) }
        }
    }

    @discardableResult
    func resolveCopilotBinary(manualPath: String? = nil) async -> Bool {
        resolvingProviderBinaries.insert(.copilot)
        defer { resolvingProviderBinaries.remove(.copilot) }
        let info: CopilotBinaryInfo?
        if let manualPath {
            guard let version = await copilotResolver.verify(path: manualPath) else { return false }
            info = CopilotBinaryInfo(path: manualPath, version: version)
        } else {
            info = await copilotResolver.resolve(savedPath: state.copilotBinaryPath)
        }
        state.copilotBinaryPath = info?.path
        copilotVersion = info?.version
        if let path = info?.path {
            copilotLauncherPath = try? await store.prepareCopilotLauncher(binaryPath: path).path
        } else {
            copilotLauncherPath = nil
        }
        try? await persistAll()
        return info != nil
    }

    func chooseCopilotBinary() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("select_copilot_binary_title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task {
            let resolved = await resolveCopilotBinary(manualPath: path)
            if !resolved { showMessage(L10n.text("invalid_copilot_binary")) }
        }
    }

    func importCurrentCursorAccount() {
        guard !isImportingCursorAccount else { return }
        guard let service = cursorAccountService else {
            showMessage(L10n.text("cursor_cli_not_found"))
            return
        }
        isImportingCursorAccount = true
        Task {
            defer { isImportingCursorAccount = false }
            do {
                var usesFileCredentialStore = false
                var status = try await service.status(profile: nil)
                if !status.isLoggedIn,
                   let fileStatus = try? await service.status(
                       profile: defaultCursorConfigURL,
                       usesFileCredentialStore: true
                   ), fileStatus.isLoggedIn {
                    status = fileStatus
                    usesFileCredentialStore = true
                }
                guard status.isLoggedIn else {
                    throw LLMAccountSwitcherError.message(L10n.text("cursor_not_logged_in"))
                }
                guard !containsCursorAccount(email: status.email) else {
                    throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                }
                let id = UUID()
                let isFirst = cursorAccounts.isEmpty
                cursorAccounts.append(makeCursorAccount(
                    id: id,
                    status: status,
                    profileDirectoryName: "default",
                    usesDefaultProfile: true,
                    usesFileCredentialStore: usesFileCredentialStore,
                    isActive: isFirst
                ))
                if isFirst {
                    state.activeCursorAccountId = id
                    try await activateCursorProfile(
                        defaultCursorConfigURL,
                        usesFileCredentialStore: usesFileCredentialStore
                    )
                }
                try await persistAll()
            } catch { show(error) }
        }
    }

    func addCursorAccount() {
        addCursorAccount(onSuccess: nil)
    }

    func addCursorAccount(onSuccess: (() -> Void)?) {
        guard cursorLoginTask == nil, let service = cursorAccountService else {
            showMessage(L10n.text("cursor_cli_not_found"))
            return
        }
        isAddingCursorAccount = true
        cursorLoginTask = Task {
            let id = UUID()
            do {
                let profile = try await store.createCursorProfile(id: id)
                do {
                    let status = try await service.login(profile: profile)
                    guard !containsCursorAccount(email: status.email) else {
                        try await store.removeCursorProfile(named: id.uuidString)
                        throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                    }
                    let isFirst = cursorAccounts.isEmpty
                    cursorAccounts.append(makeCursorAccount(
                        id: id,
                        status: status,
                        profileDirectoryName: id.uuidString,
                        usesDefaultProfile: false,
                        usesFileCredentialStore: true,
                        isActive: isFirst
                    ))
                    if isFirst {
                        state.activeCursorAccountId = id
                        try await activateCursorProfile(profile, usesFileCredentialStore: true)
                    }
                    try await persistAll()
                    onSuccess?()
                } catch {
                    cursorAccounts.removeAll { $0.id == id }
                    try? await store.removeCursorProfile(named: id.uuidString)
                    throw error
                }
            } catch is CancellationError {
            } catch { show(error) }
            cursorLoginTask = nil
            isAddingCursorAccount = false
        }
    }

    func refreshCursor(_ id: UUID) {
        guard !refreshingCursorIDs.contains(id),
              let service = cursorAccountService,
              let account = cursorAccounts.first(where: { $0.id == id }) else { return }
        refreshingCursorIDs.insert(id)
        Task {
            defer { refreshingCursorIDs.remove(id) }
            do {
                let profile = await cursorProfileURL(for: account)
                let status = try await service.status(
                    profile: profile,
                    usesFileCredentialStore: account.usesFileCredentialStore
                )
                guard status.isLoggedIn else {
                    throw LLMAccountSwitcherError.message(L10n.text("cursor_not_logged_in"))
                }
                if let index = cursorAccounts.firstIndex(where: { $0.id == id }) {
                    cursorAccounts[index].email = status.email
                    cursorAccounts[index].rawPlan = status.plan
                    cursorAccounts[index].lastRefreshAt = Date()
                    try await persistAll()
                }
            } catch { show(error) }
        }
    }

    func setActiveCursor(_ id: UUID) {
        guard switchingCursorAccountID == nil,
              !processingCursorIDs.contains(id),
              let account = cursorAccounts.first(where: { $0.id == id }),
              !account.isActive else { return }
        switchingCursorAccountID = id
        processingCursorIDs.insert(id)
        Task {
            defer {
                processingCursorIDs.remove(id)
                if switchingCursorAccountID == id { switchingCursorAccountID = nil }
            }
            do {
                guard let service = cursorAccountService else {
                    throw LLMAccountSwitcherError.message(L10n.text("cursor_cli_not_found"))
                }
                let profile = await cursorProfileURL(for: account)
                let status = try await service.status(
                    profile: profile,
                    usesFileCredentialStore: account.usesFileCredentialStore
                )
                guard status.isLoggedIn else {
                    throw LLMAccountSwitcherError.message(L10n.text("cursor_not_logged_in"))
                }
                for index in cursorAccounts.indices {
                    cursorAccounts[index].isActive = cursorAccounts[index].id == id
                }
                if let index = cursorAccounts.firstIndex(where: { $0.id == id }) {
                    cursorAccounts[index].email = status.email
                    cursorAccounts[index].rawPlan = status.plan
                    cursorAccounts[index].lastRefreshAt = Date()
                }
                state.activeCursorAccountId = id
                try await activateCursorProfile(
                    profile,
                    usesFileCredentialStore: account.usesFileCredentialStore
                )
                try await persistAll()
            } catch { show(error) }
        }
    }

    func moveCursorAccount(_ id: UUID, over destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = cursorAccounts.firstIndex(where: { $0.id == id }),
              let destinationIndex = cursorAccounts.firstIndex(where: { $0.id == destinationID }) else { return }
        let insertionIndex = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        cursorAccounts.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: insertionIndex)
    }

    func saveCursorAccountOrder() {
        Task { try? await persistAll() }
    }

    func deleteCursor(_ id: UUID) {
        guard !processingCursorIDs.contains(id),
              let account = cursorAccounts.first(where: { $0.id == id }) else { return }
        processingCursorIDs.insert(id)
        Task {
            defer { processingCursorIDs.remove(id) }
            if account.isActive, let replacement = cursorAccounts.first(where: { $0.id != id }) {
                do {
                    guard let service = cursorAccountService else {
                        throw LLMAccountSwitcherError.message(L10n.text("cursor_cli_not_found"))
                    }
                    let replacementProfile = await cursorProfileURL(for: replacement)
                    let status = try await service.status(
                        profile: replacementProfile,
                        usesFileCredentialStore: replacement.usesFileCredentialStore
                    )
                    guard status.isLoggedIn else {
                        throw LLMAccountSwitcherError.message(L10n.text("cursor_not_logged_in"))
                    }
                    for index in cursorAccounts.indices {
                        cursorAccounts[index].isActive = cursorAccounts[index].id == replacement.id
                    }
                    state.activeCursorAccountId = replacement.id
                    try await activateCursorProfile(
                        replacementProfile,
                        usesFileCredentialStore: replacement.usesFileCredentialStore
                    )
                } catch {
                    show(error)
                    return
                }
            }
            cursorAccounts.removeAll { $0.id == id }
            if !account.usesDefaultProfile {
                try? await store.removeCursorProfile(named: account.profileDirectoryName)
            }
            if account.isActive {
                state.activeCursorAccountId = nil
                try? await activateCursorProfile(defaultCursorConfigURL, usesFileCredentialStore: false)
            }
            try? await persistAll()
        }
    }

    func importCurrentAntigravityAccount() {
        guard !isImportingAntigravityAccount else { return }
        isImportingAntigravityAccount = true
        Task {
            defer { isImportingAntigravityAccount = false }
            let id = UUID()
            let credentialKey = id.uuidString
            do {
                let status = try await antigravityAccountService.importCurrent(profileKey: credentialKey)
                guard !containsAntigravityAccount(status: status) else {
                    try? await antigravityAccountService.deleteProfile(profileKey: credentialKey)
                    throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                }
                for index in antigravityAccounts.indices { antigravityAccounts[index].isActive = false }
                antigravityAccounts.append(makeAntigravityAccount(
                    id: id,
                    credentialKey: credentialKey,
                    status: status,
                    isActive: true
                ))
                state.activeAntigravityAccountId = id
                try await persistAll()
            } catch { show(error) }
        }
    }

    func addAntigravityAccount() {
        addAntigravityAccount(onSuccess: nil)
    }

    func addAntigravityAccount(onSuccess: (() -> Void)?) {
        guard antigravityLoginTask == nil, let binaryPath = state.antigravityBinaryPath else {
            showMessage(L10n.text("antigravity_cli_not_found"))
            return
        }
        isAddingAntigravityAccount = true
        antigravityLoginTask = Task {
            let id = UUID()
            let credentialKey = id.uuidString
            var loginSession: AntigravityLoginSession?
            do {
                loginSession = try await antigravityAccountService.prepareInteractiveLogin(
                    activeProfileKey: activeAntigravityAccount?.credentialKey
                )
                let command = try await store.prepareAntigravityLoginCommand(binaryPath: binaryPath)
                guard NSWorkspace.shared.open(command) else {
                    throw LLMAccountSwitcherError.message(L10n.text("antigravity_terminal_failed"))
                }
                guard let loginSession else { return }
                let status = try await antigravityAccountService.completeInteractiveLogin(
                    profileKey: credentialKey,
                    session: loginSession
                )
                guard !containsAntigravityAccount(status: status) else {
                    try? await antigravityAccountService.deleteProfile(profileKey: credentialKey)
                    throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                }
                for index in antigravityAccounts.indices { antigravityAccounts[index].isActive = false }
                antigravityAccounts.append(makeAntigravityAccount(
                    id: id,
                    credentialKey: credentialKey,
                    status: status,
                    isActive: true
                ))
                state.activeAntigravityAccountId = id
                try await persistAll()
                onSuccess?()
            } catch is CancellationError {
                if let loginSession { await antigravityAccountService.restoreAfterFailedLogin(loginSession) }
            } catch {
                if let loginSession { await antigravityAccountService.restoreAfterFailedLogin(loginSession) }
                show(error)
            }
            antigravityLoginTask = nil
            isAddingAntigravityAccount = false
        }
    }

    func cancelAddAntigravityAccount() {
        antigravityLoginTask?.cancel()
    }

    func refreshAntigravity(_ id: UUID) {
        guard !refreshingAntigravityIDs.contains(id),
              let account = antigravityAccounts.first(where: { $0.id == id }) else { return }
        refreshingAntigravityIDs.insert(id)
        Task {
            defer { refreshingAntigravityIDs.remove(id) }
            do {
                let status = try await antigravityAccountService.profileStatus(
                    profileKey: account.credentialKey,
                    knownEmail: account.email
                )
                if let index = antigravityAccounts.firstIndex(where: { $0.id == id }) {
                    antigravityAccounts[index].email = status.email ?? antigravityAccounts[index].email
                    antigravityAccounts[index].rawPlan = status.plan ?? antigravityAccounts[index].rawPlan
                    antigravityAccounts[index].credentialFingerprint = status.credentialFingerprint
                    antigravityAccounts[index].lastRefreshAt = Date()
                    try await persistAll()
                }
            } catch { show(error) }
        }
    }

    func setActiveAntigravity(_ id: UUID) {
        guard switchingAntigravityAccountID == nil,
              !processingAntigravityIDs.contains(id),
              let account = antigravityAccounts.first(where: { $0.id == id }),
              !account.isActive else { return }
        switchingAntigravityAccountID = id
        processingAntigravityIDs.insert(id)
        Task {
            defer {
                processingAntigravityIDs.remove(id)
                if switchingAntigravityAccountID == id { switchingAntigravityAccountID = nil }
            }
            do {
                let status = try await antigravityAccountService.activate(
                    profileKey: account.credentialKey,
                    currentProfileKey: activeAntigravityAccount?.credentialKey,
                    expectedEmail: account.email
                )
                for index in antigravityAccounts.indices {
                    antigravityAccounts[index].isActive = antigravityAccounts[index].id == id
                }
                if let index = antigravityAccounts.firstIndex(where: { $0.id == id }) {
                    antigravityAccounts[index].email = status.email ?? antigravityAccounts[index].email
                    antigravityAccounts[index].rawPlan = status.plan ?? antigravityAccounts[index].rawPlan
                    antigravityAccounts[index].credentialFingerprint = status.credentialFingerprint
                    antigravityAccounts[index].lastRefreshAt = Date()
                }
                state.activeAntigravityAccountId = id
                try await persistAll()
            } catch { show(error) }
        }
    }

    func moveAntigravityAccount(_ id: UUID, over destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = antigravityAccounts.firstIndex(where: { $0.id == id }),
              let destinationIndex = antigravityAccounts.firstIndex(where: { $0.id == destinationID }) else { return }
        let insertionIndex = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        antigravityAccounts.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: insertionIndex)
    }

    func saveAntigravityAccountOrder() {
        Task { try? await persistAll() }
    }

    func deleteAntigravity(_ id: UUID) {
        guard !processingAntigravityIDs.contains(id),
              let account = antigravityAccounts.first(where: { $0.id == id }) else { return }
        processingAntigravityIDs.insert(id)
        Task {
            defer { processingAntigravityIDs.remove(id) }
            if account.isActive, let replacement = antigravityAccounts.first(where: { $0.id != id }) {
                do {
                    let status = try await antigravityAccountService.activate(
                        profileKey: replacement.credentialKey,
                        currentProfileKey: account.credentialKey,
                        expectedEmail: replacement.email
                    )
                    for index in antigravityAccounts.indices {
                        antigravityAccounts[index].isActive = antigravityAccounts[index].id == replacement.id
                    }
                    if let index = antigravityAccounts.firstIndex(where: { $0.id == replacement.id }) {
                        antigravityAccounts[index].email = status.email ?? antigravityAccounts[index].email
                        antigravityAccounts[index].credentialFingerprint = status.credentialFingerprint
                    }
                    state.activeAntigravityAccountId = replacement.id
                } catch {
                    show(error)
                    return
                }
            } else if account.isActive {
                try? await antigravityAccountService.clearLiveCredential()
                state.activeAntigravityAccountId = nil
            }
            antigravityAccounts.removeAll { $0.id == id }
            try? await antigravityAccountService.deleteProfile(profileKey: account.credentialKey)
            try? await persistAll()
        }
    }

    func importCurrentCopilotAccount() {
        guard !isImportingCopilotAccount, let service = copilotAccountService else {
            showMessage(L10n.text("copilot_cli_not_found"))
            return
        }
        isImportingCopilotAccount = true
        Task {
            defer { isImportingCopilotAccount = false }
            do {
                let status = try service.status()
                guard !status.identities.isEmpty else {
                    throw LLMAccountSwitcherError.message(L10n.text("copilot_not_logged_in"))
                }
                mergeCopilotAccounts(from: status)
                try await persistAll()
            } catch { show(error) }
        }
    }

    func addCopilotAccount() {
        addCopilotAccount(onSuccess: nil)
    }

    func addCopilotAccount(onSuccess: (() -> Void)?) {
        guard copilotLoginTask == nil, let service = copilotAccountService else {
            showMessage(L10n.text("copilot_cli_not_found"))
            return
        }
        isAddingCopilotAccount = true
        copilotLoginTask = Task {
            defer {
                copilotLoginTask = nil
                isAddingCopilotAccount = false
            }
            do {
                let status = try await service.login()
                mergeCopilotAccounts(from: status)
                try await persistAll()
                onSuccess?()
            } catch is CancellationError {
            } catch { show(error) }
        }
    }

    func refreshCopilot(_ id: UUID) {
        guard !refreshingCopilotIDs.contains(id), let service = copilotAccountService else { return }
        refreshingCopilotIDs.insert(id)
        Task {
            defer { refreshingCopilotIDs.remove(id) }
            do {
                let status = try service.status()
                for index in copilotAccounts.indices {
                    let identity = copilotIdentity(for: copilotAccounts[index])
                    copilotAccounts[index].isActive = identity == status.activeIdentity
                    if copilotAccounts[index].id == id { copilotAccounts[index].lastRefreshAt = Date() }
                }
                state.activeCopilotAccountId = copilotAccounts.first(where: \.isActive)?.id
                try await persistAll()
            } catch { show(error) }
        }
    }

    func setActiveCopilot(_ id: UUID) {
        guard switchingCopilotAccountID == nil,
              !processingCopilotIDs.contains(id),
              let account = copilotAccounts.first(where: { $0.id == id }),
              !account.isActive,
              let service = copilotAccountService else { return }
        switchingCopilotAccountID = id
        processingCopilotIDs.insert(id)
        Task {
            defer {
                processingCopilotIDs.remove(id)
                if switchingCopilotAccountID == id { switchingCopilotAccountID = nil }
            }
            do {
                let status = try service.activate(copilotIdentity(for: account))
                for index in copilotAccounts.indices {
                    copilotAccounts[index].isActive = copilotIdentity(for: copilotAccounts[index]) == status.activeIdentity
                    if copilotAccounts[index].id == id { copilotAccounts[index].lastRefreshAt = Date() }
                }
                state.activeCopilotAccountId = id
                try await persistAll()
            } catch { show(error) }
        }
    }

    func moveCopilotAccount(_ id: UUID, over destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = copilotAccounts.firstIndex(where: { $0.id == id }),
              let destinationIndex = copilotAccounts.firstIndex(where: { $0.id == destinationID }) else { return }
        let insertionIndex = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        copilotAccounts.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: insertionIndex)
    }

    func saveCopilotAccountOrder() {
        Task { try? await persistAll() }
    }

    func deleteCopilot(_ id: UUID) {
        guard !processingCopilotIDs.contains(id),
              let account = copilotAccounts.first(where: { $0.id == id }) else { return }
        processingCopilotIDs.insert(id)
        Task {
            defer { processingCopilotIDs.remove(id) }
            if account.isActive,
               let replacement = copilotAccounts.first(where: { $0.id != id }),
               let service = copilotAccountService {
                do {
                    _ = try service.activate(copilotIdentity(for: replacement))
                    for index in copilotAccounts.indices {
                        copilotAccounts[index].isActive = copilotAccounts[index].id == replacement.id
                    }
                    state.activeCopilotAccountId = replacement.id
                } catch {
                    show(error)
                    return
                }
            } else if account.isActive {
                state.activeCopilotAccountId = nil
            }
            copilotAccounts.removeAll { $0.id == id }
            try? await persistAll()
        }
    }

    func importCurrentClaudeAccount() {
        guard !isImportingClaudeAccount else { return }
        guard let service = claudeAccountService else {
            showMessage(L10n.text("claude_cli_not_found"))
            return
        }
        isImportingClaudeAccount = true
        Task {
            defer { isImportingClaudeAccount = false }
            do {
                let status = try await service.status(profile: nil)
                guard status.isLoggedIn else {
                    throw LLMAccountSwitcherError.message(L10n.text("claude_not_logged_in"))
                }
                guard !containsClaudeAccount(email: status.email) else {
                    throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                }
                let id = UUID()
                let isFirst = claudeAccounts.isEmpty
                claudeAccounts.append(makeClaudeAccount(
                    id: id,
                    status: status,
                    profileDirectoryName: "default",
                    usesDefaultProfile: true,
                    isActive: isFirst
                ))
                if isFirst {
                    state.activeClaudeAccountId = id
                    try await activateClaudeProfile(defaultClaudeConfigURL)
                }
                try await persistAll()
            } catch { show(error) }
        }
    }

    func addClaudeAccount() {
        addClaudeAccount(onSuccess: nil)
    }

    func addClaudeAccount(onSuccess: (() -> Void)?) {
        guard claudeLoginTask == nil, let service = claudeAccountService else {
            showMessage(L10n.text("claude_cli_not_found"))
            return
        }
        isAddingClaudeAccount = true
        claudeLoginTask = Task {
            let id = UUID()
            do {
                let profile = try await store.createClaudeProfile(id: id)
                do {
                    let status = try await service.login(profile: profile)
                    guard !containsClaudeAccount(email: status.email) else {
                        try await store.removeClaudeProfile(named: id.uuidString)
                        throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                    }
                    let isFirst = claudeAccounts.isEmpty
                    claudeAccounts.append(makeClaudeAccount(
                        id: id,
                        status: status,
                        profileDirectoryName: id.uuidString,
                        usesDefaultProfile: false,
                        isActive: isFirst
                    ))
                    if isFirst {
                        state.activeClaudeAccountId = id
                        try await activateClaudeProfile(profile)
                    }
                    try await persistAll()
                    onSuccess?()
                } catch {
                    claudeAccounts.removeAll { $0.id == id }
                    try? await store.removeClaudeProfile(named: id.uuidString)
                    throw error
                }
            } catch is CancellationError {
            } catch { show(error) }
            claudeLoginTask = nil
            isAddingClaudeAccount = false
        }
    }

    func refreshClaude(_ id: UUID) {
        guard !refreshingClaudeIDs.contains(id),
              let service = claudeAccountService,
              let account = claudeAccounts.first(where: { $0.id == id }) else { return }
        refreshingClaudeIDs.insert(id)
        Task {
            defer { refreshingClaudeIDs.remove(id) }
            do {
                let profile = await claudeProfileURL(for: account)
                let status = try await service.status(profile: profile)
                guard status.isLoggedIn else {
                    throw LLMAccountSwitcherError.message(L10n.text("claude_not_logged_in"))
                }
                if let index = claudeAccounts.firstIndex(where: { $0.id == id }) {
                    claudeAccounts[index].email = status.email
                    claudeAccounts[index].rawPlan = status.plan
                    claudeAccounts[index].authMethod = status.authMethod
                    claudeAccounts[index].lastRefreshAt = Date()
                    try await persistAll()
                }
            } catch { show(error) }
        }
    }

    func setActiveClaude(_ id: UUID) {
        guard switchingClaudeAccountID == nil,
              !processingClaudeIDs.contains(id),
              let account = claudeAccounts.first(where: { $0.id == id }),
              !account.isActive else { return }
        switchingClaudeAccountID = id
        processingClaudeIDs.insert(id)
        Task {
            defer {
                processingClaudeIDs.remove(id)
                if switchingClaudeAccountID == id { switchingClaudeAccountID = nil }
            }
            do {
                guard let service = claudeAccountService else {
                    throw LLMAccountSwitcherError.message(L10n.text("claude_cli_not_found"))
                }
                let profile = await claudeProfileURL(for: account)
                let status = try await service.status(profile: profile)
                guard status.isLoggedIn else {
                    throw LLMAccountSwitcherError.message(L10n.text("claude_not_logged_in"))
                }
                for index in claudeAccounts.indices {
                    claudeAccounts[index].isActive = claudeAccounts[index].id == id
                }
                if let index = claudeAccounts.firstIndex(where: { $0.id == id }) {
                    claudeAccounts[index].email = status.email
                    claudeAccounts[index].rawPlan = status.plan
                    claudeAccounts[index].authMethod = status.authMethod
                    claudeAccounts[index].lastRefreshAt = Date()
                }
                state.activeClaudeAccountId = id
                try await activateClaudeProfile(profile)
                try await persistAll()
            } catch { show(error) }
        }
    }

    func moveClaudeAccount(_ id: UUID, over destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = claudeAccounts.firstIndex(where: { $0.id == id }),
              let destinationIndex = claudeAccounts.firstIndex(where: { $0.id == destinationID }) else { return }
        let insertionIndex = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        claudeAccounts.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: insertionIndex)
    }

    func saveClaudeAccountOrder() {
        Task { try? await persistAll() }
    }

    func deleteClaude(_ id: UUID) {
        guard !processingClaudeIDs.contains(id),
              let account = claudeAccounts.first(where: { $0.id == id }) else { return }
        processingClaudeIDs.insert(id)
        Task {
            defer { processingClaudeIDs.remove(id) }
            if account.isActive, let replacement = claudeAccounts.first(where: { $0.id != id }) {
                do {
                    guard let service = claudeAccountService else {
                        throw LLMAccountSwitcherError.message(L10n.text("claude_cli_not_found"))
                    }
                    let replacementProfile = await claudeProfileURL(for: replacement)
                    let status = try await service.status(profile: replacementProfile)
                    guard status.isLoggedIn else {
                        throw LLMAccountSwitcherError.message(L10n.text("claude_not_logged_in"))
                    }
                    for index in claudeAccounts.indices {
                        claudeAccounts[index].isActive = claudeAccounts[index].id == replacement.id
                    }
                    state.activeClaudeAccountId = replacement.id
                    try await activateClaudeProfile(replacementProfile)
                } catch {
                    show(error)
                    return
                }
            }
            claudeAccounts.removeAll { $0.id == id }
            if !account.usesDefaultProfile {
                try? await store.removeClaudeProfile(named: account.profileDirectoryName)
            }
            if account.isActive { state.activeClaudeAccountId = nil }
            try? await persistAll()
        }
    }

    func importCurrentAccount() {
        guard !isImportingAccount else { return }
        guard let service = accountService else { showMessage(L10n.text("codex_cli_not_found")); return }
        isImportingAccount = true
        Task {
            defer { isImportingAccount = false }
            let id = UUID()
            do {
                let profile = try await store.createProfile(id: id)
                do {
                    try await store.copyCredential(from: defaultAuthURL, to: profile.appendingPathComponent("auth.json"))
                    let result = try await service.read(profile: profile)
                    guard !containsAccount(email: result.remote.email) else {
                        try await store.removeProfile(named: id.uuidString)
                        throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                    }
                    let isFirst = accounts.isEmpty
                    let account = makeAccount(id: id, result: result, isActive: isFirst)
                    accounts.append(account)
                    if quotaResetNotificationsEnabled {
                        quotaResetNotificationService.requestAuthorization()
                    }
                    if isFirst { state.activeAccountId = id }
                    state.defaultAuthModificationDate = authModificationDate()
                    try await persist()
                    scheduleQuotaResetHandling()
                } catch { try? await store.removeProfile(named: id.uuidString); throw error }
            } catch { show(error) }
        }
    }

    func addAccount() {
        addAccount(onSuccess: nil)
    }

    func addAccount(onSuccess: (() -> Void)?) {
        guard loginTask == nil, let service = accountService else { showMessage(L10n.text("codex_cli_not_found")); return }
        isAddingAccount = true
        loginMessageKey = "preparing_login"
        loginTask = Task {
            let id = UUID()
            do {
                let profile = try await store.createProfile(id: id)
                do {
                    let (client, session) = try await service.startLogin(profile: profile)
                    loginClient = client
                    loginID = session.loginID
                    loginMessageKey = "waiting_chatgpt_login"
                    NSWorkspace.shared.open(session.authURL)
                    let result = try await service.finishLogin(client: client, loginID: session.loginID)
                    await client.stop()
                    guard !containsAccount(email: result.remote.email) else {
                        try await store.removeProfile(named: id.uuidString)
                        throw LLMAccountSwitcherError.message(L10n.text("account_exists"))
                    }
                    let isFirst = accounts.isEmpty
                    accounts.append(makeAccount(id: id, result: result, isActive: false))
                    if quotaResetNotificationsEnabled {
                        quotaResetNotificationService.requestAuthorization()
                    }
                    try await persist()
                    if isFirst {
                        try await activate(id)
                    }
                    scheduleQuotaResetHandling()
                    onSuccess?()
                } catch {
                    accounts.removeAll { $0.id == id }
                    try? await store.removeProfile(named: id.uuidString)
                    throw error
                }
            } catch is CancellationError {
            } catch { show(error) }
            loginClient = nil
            loginID = nil
            loginTask = nil
            isAddingAccount = false
            loginMessageKey = nil
        }
    }

    func cancelAddAccount() {
        guard let client = loginClient, let loginID else { loginTask?.cancel(); return }
        Task { await accountService?.cancelLogin(client: client, loginID: loginID) }
        loginTask?.cancel()
    }

    func refresh(_ id: UUID) {
        guard refreshTasks[id] == nil, let service = accountService,
              let account = accounts.first(where: { $0.id == id }) else { return }
        refreshingIDs.insert(id)
        let task = Task {
            await refreshGate.acquire()
            defer { Task { await self.refreshGate.release() } }
            do {
                let profile = await store.profileURL(named: account.profileDirectoryName)
                let result = try await service.read(profile: profile)
                if let index = accounts.firstIndex(where: { $0.id == id }) {
                    let resetKinds = QuotaResetDetector.resets(
                        previous: accounts[index].usage,
                        current: result.usage
                    )
                    accounts[index].email = result.remote.email
                    accounts[index].rawPlan = result.remote.plan ?? result.usage?.sourcePlan
                    accounts[index].usage = result.usage
                    accounts[index].lastRefreshAt = Date()
                    accounts[index].lastSuccessfulRefreshAt = Date()
                    accounts[index].lastError = result.usage == nil
                        ? AccountRefreshError(kind: .usageUnavailable, message: L10n.text("usage_unavailable")) : nil
                    try await persist()
                    scheduleQuotaResetHandling()
                    for kind in resetKinds where quotaResetNotificationsEnabled {
                        let resetDate = kind == .fiveHour
                            ? result.usage?.fiveHour?.resetsAt
                            : result.usage?.weekly?.resetsAt
                        quotaResetNotificationService.notify(
                            account: accounts[index],
                            kind: kind,
                            resetDate: resetDate,
                            language: LocalizationManager.shared.language
                        )
                    }
                }
            } catch {
                if let index = accounts.firstIndex(where: { $0.id == id }) {
                    accounts[index].lastRefreshAt = Date()
                    accounts[index].lastError = AccountRefreshError(
                        kind: refreshErrorKind(for: error),
                        message: shortMessage(error)
                    )
                    try? await persist()
                }
            }
            refreshingIDs.remove(id)
            refreshTasks[id] = nil
        }
        refreshTasks[id] = task
    }

    func setActive(_ id: UUID) {
        guard switchingAccountID == nil,
              !processingIDs.contains(id),
              let account = accounts.first(where: { $0.id == id }),
              !account.isActive else { return }
        switchingAccountID = id
        processingIDs.insert(id)
        Task {
            defer {
                processingIDs.remove(id)
                if switchingAccountID == id { switchingAccountID = nil }
            }
            do {
                try await activate(id)
            } catch {
                guard requiresReauthentication(error),
                      let account = accounts.first(where: { $0.id == id }),
                      NativeReauthenticationAlert.confirm(
                          title: L10n.text("reauthentication_required_title"),
                          message: L10n.format(
                              "reauthentication_required_message",
                              arguments: [account.email ?? account.displayName]
                          ),
                          confirmTitle: L10n.text("reauthenticate"),
                          cancelTitle: L10n.text("cancel")
                      ) else {
                    show(error)
                    return
                }

                do {
                    try await reauthenticateAndActivate(id)
                } catch {
                    show(error)
                }
            }
        }
    }

    func rename(_ id: UUID, to value: String) {
        let name = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].displayName = name
        Task { try? await persist() }
    }

    func moveAccount(_ id: UUID, over destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = accounts.firstIndex(where: { $0.id == id }),
              let destinationIndex = accounts.firstIndex(where: { $0.id == destinationID }) else { return }

        let insertionIndex = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        accounts.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: insertionIndex
        )
    }

    func saveAccountOrder() {
        Task { try? await persist() }
    }

    func delete(_ id: UUID) {
        guard !processingIDs.contains(id), let account = accounts.first(where: { $0.id == id }) else { return }
        processingIDs.insert(id)
        Task {
            defer { processingIDs.remove(id) }
            refreshTasks[id]?.cancel()
            if account.isActive, let replacement = accounts.first(where: { $0.id != id }) {
                do { try await activate(replacement.id) } catch { show(error); return }
            }
            accounts.removeAll { $0.id == id }
            try? await store.removeProfile(named: account.profileDirectoryName)
            if account.isActive {
                state.activeAccountId = accounts.first(where: \.isActive)?.id
            }
            try? await persist()
            scheduleQuotaResetHandling()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchService.setEnabled(enabled)
            state.launchAtLoginConfigured = true
            state.launchAtLogin = launchService.isEnabled
            Task { try? await persist() }
        } catch { show(error) }
    }

    func setQuotaResetNotificationsEnabled(_ enabled: Bool) {
        state.quotaResetNotificationsEnabled = enabled
        if enabled { quotaResetNotificationService.requestAuthorization() }
        scheduleQuotaResetHandling()
        Task { try? await persist() }
    }

    func setLanguageOverride(_ language: AppLanguage?) {
        state.languageOverride = language
        LocalizationManager.shared.setLanguageOverride(language)
        Task { try? await persist() }
    }

    func completeOnboarding(with provider: LLMProvider) async {
        LLMProviderOrderStore.shared.enableOnly(provider)
        state.onboardingCompleted = true
        try? await persistAll()
    }

    func shutdownAndQuit() {
        Task {
            if let activeAccount, let service = accountService {
                let switcher = AccountSwitchService(store: store) { profile in
                    try await service.read(profile: profile).remote
                }
                await switcher.syncOnTermination(active: activeAccount)
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private var accountService: CodexAccountService? {
        guard let path = state.codexBinaryPath else { return nil }
        return CodexAccountService(binaryPath: path, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
    }

    private var claudeAccountService: ClaudeAccountService? {
        guard let path = state.claudeBinaryPath else { return nil }
        return ClaudeAccountService(binaryPath: path)
    }

    private var cursorAccountService: CursorAccountService? {
        guard let path = state.cursorBinaryPath,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return CursorAccountService(binaryPath: path)
    }

    private var copilotAccountService: CopilotAccountService? {
        guard let path = state.copilotBinaryPath else { return nil }
        return CopilotAccountService(binaryPath: path)
    }

    @discardableResult
    private func clearUnavailableBinaryPaths() -> Set<LLMProvider> {
        var unavailable = Set<LLMProvider>()
        let fileManager = FileManager.default

        if let path = state.codexBinaryPath, !fileManager.isExecutableFile(atPath: path) {
            state.codexBinaryPath = nil
            codexVersion = nil
            unavailable.insert(.codex)
        }
        if let path = state.claudeBinaryPath, !fileManager.isExecutableFile(atPath: path) {
            state.claudeBinaryPath = nil
            claudeVersion = nil
            claudeLauncherPath = nil
            unavailable.insert(.claude)
        }
        if let path = state.cursorBinaryPath, !fileManager.isExecutableFile(atPath: path) {
            state.cursorBinaryPath = nil
            cursorVersion = nil
            cursorLauncherPath = nil
            unavailable.insert(.cursor)
        }
        if let path = state.antigravityBinaryPath, !fileManager.isExecutableFile(atPath: path) {
            state.antigravityBinaryPath = nil
            unavailable.insert(.antigravity)
        }
        if let path = state.copilotBinaryPath, !fileManager.isExecutableFile(atPath: path) {
            state.copilotBinaryPath = nil
            copilotVersion = nil
            copilotLauncherPath = nil
            unavailable.insert(.copilot)
        }

        return unavailable
    }

    private func enableLaunchAtLoginByDefaultIfNeeded() {
        guard state.launchAtLoginConfigured != true else { return }
        do {
            if !launchService.isEnabled { try launchService.setEnabled(true) }
            state.launchAtLoginConfigured = true
        } catch {
            logger.warning("Không thể bật khởi động cùng macOS mặc định: \(self.shortMessage(error), privacy: .public)")
        }
    }

    private func activate(_ id: UUID) async throws {
        guard let target = accounts.first(where: { $0.id == id }), !target.isActive,
              let service = accountService else { return }
        let switcher = AccountSwitchService(store: store) { profile in
            try await service.read(profile: profile, refreshToken: true).remote
        }
        let date = try await switcher.switchAccount(from: activeAccount, to: target)
        for index in accounts.indices { accounts[index].isActive = accounts[index].id == id }
        state.activeAccountId = id
        state.defaultAuthModificationDate = date
        externalAccountDetected = false
        try await persist()
        scheduleQuotaResetHandling()
        refresh(id)
        try await codexDesktopRelaunchService.relaunchIfRunning()
    }

    private func reauthenticateAndActivate(_ id: UUID) async throws {
        guard let target = accounts.first(where: { $0.id == id }),
              let service = accountService else {
            return
        }

        let profile = await store.profileURL(named: target.profileDirectoryName)
        let authURL = profile.appendingPathComponent("auth.json")
        let previousAuth = try? Data(contentsOf: authURL)
        isAddingAccount = true
        loginMessageKey = "reauthenticating_account"
        defer {
            loginClient = nil
            loginID = nil
            isAddingAccount = false
            loginMessageKey = nil
        }

        let result: RefreshedAccount
        var client: CodexAppServerClient?
        do {
            let session = try await service.startLogin(profile: profile)
            client = session.0
            loginClient = session.0
            loginID = session.1.loginID
            loginMessageKey = "waiting_chatgpt_login"
            NSWorkspace.shared.open(session.1.authURL)
            result = try await service.finishLogin(client: session.0, loginID: session.1.loginID)
            await session.0.stop()
            client = nil

            guard accountsMatch(result.remote.email, target.email) else {
                throw LLMAccountSwitcherError.message(
                    L10n.format(
                        "reauthenticate_wrong_account",
                        arguments: [result.remote.email ?? "", target.email ?? target.displayName]
                    )
                )
            }
        } catch {
            if let client { await client.stop() }
            if let previousAuth {
                try? await store.atomicWrite(previousAuth, to: authURL, permissions: 0o600)
            }
            throw error
        }

        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].email = result.remote.email
        accounts[index].rawPlan = result.remote.plan ?? result.usage?.sourcePlan
        accounts[index].usage = result.usage
        accounts[index].lastRefreshAt = Date()
        accounts[index].lastSuccessfulRefreshAt = Date()
        accounts[index].lastError = nil
        try await persist()
        try await activate(id)
    }

    private func makeAccount(id: UUID, result: RefreshedAccount, isActive: Bool) -> CodexAccount {
        CodexAccount(id: id, displayName: AccountNumbering.takeNext(from: &state), email: result.remote.email,
                     rawPlan: result.remote.plan ?? result.usage?.sourcePlan, profileDirectoryName: id.uuidString,
                     isActive: isActive, usage: result.usage, lastRefreshAt: Date(),
                     lastSuccessfulRefreshAt: Date(), lastError: nil)
    }

    private func makeClaudeAccount(
        id: UUID,
        status: ClaudeAuthStatus,
        profileDirectoryName: String,
        usesDefaultProfile: Bool,
        isActive: Bool
    ) -> ClaudeAccount {
        ClaudeAccount(
            id: id,
            displayName: "Claude \(claudeAccounts.count + 1)",
            email: status.email,
            rawPlan: status.plan,
            authMethod: status.authMethod,
            profileDirectoryName: profileDirectoryName,
            usesDefaultProfile: usesDefaultProfile,
            isActive: isActive,
            lastRefreshAt: Date()
        )
    }

    private func makeCursorAccount(
        id: UUID,
        status: CursorAuthStatus,
        profileDirectoryName: String,
        usesDefaultProfile: Bool,
        usesFileCredentialStore: Bool,
        isActive: Bool
    ) -> CursorAccount {
        CursorAccount(
            id: id,
            displayName: "Cursor \(cursorAccounts.count + 1)",
            email: status.email,
            rawPlan: status.plan,
            profileDirectoryName: profileDirectoryName,
            usesDefaultProfile: usesDefaultProfile,
            usesFileCredentialStore: usesFileCredentialStore,
            isActive: isActive,
            lastRefreshAt: Date()
        )
    }

    private func makeAntigravityAccount(
        id: UUID,
        credentialKey: String,
        status: AntigravityAuthStatus,
        isActive: Bool
    ) -> AntigravityAccount {
        AntigravityAccount(
            id: id,
            displayName: "Antigravity \(antigravityAccounts.count + 1)",
            email: status.email,
            rawPlan: status.plan,
            credentialKey: credentialKey,
            credentialFingerprint: status.credentialFingerprint,
            isActive: isActive,
            lastRefreshAt: Date()
        )
    }

    private func mergeCopilotAccounts(from status: CopilotAuthState) {
        for identity in status.identities where !copilotAccounts.contains(where: {
            copilotIdentity(for: $0) == identity
        }) {
            copilotAccounts.append(CopilotAccount(
                id: UUID(),
                displayName: identity.login,
                login: identity.login,
                host: identity.host,
                isActive: false,
                lastRefreshAt: Date()
            ))
        }
        for index in copilotAccounts.indices {
            copilotAccounts[index].isActive = copilotIdentity(for: copilotAccounts[index]) == status.activeIdentity
            copilotAccounts[index].lastRefreshAt = Date()
        }
        state.activeCopilotAccountId = copilotAccounts.first(where: \.isActive)?.id
    }

    private func copilotIdentity(for account: CopilotAccount) -> CopilotIdentity {
        CopilotIdentity(host: account.host, login: account.login)
    }

    private func containsAccount(email: String?) -> Bool {
        guard let email = AccountDeduplicator.normalizedEmail(email) else { return false }
        return accounts.contains { AccountDeduplicator.normalizedEmail($0.email) == email }
    }

    private func accountsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = AccountDeduplicator.normalizedEmail(lhs),
              let rhs = AccountDeduplicator.normalizedEmail(rhs) else {
            return false
        }
        return lhs == rhs
    }

    private func containsClaudeAccount(email: String?) -> Bool {
        guard let email = AccountDeduplicator.normalizedEmail(email) else { return false }
        return claudeAccounts.contains { AccountDeduplicator.normalizedEmail($0.email) == email }
    }

    private func containsCursorAccount(email: String?) -> Bool {
        guard let email = AccountDeduplicator.normalizedEmail(email) else { return false }
        return cursorAccounts.contains { AccountDeduplicator.normalizedEmail($0.email) == email }
    }

    private func containsAntigravityAccount(status: AntigravityAuthStatus) -> Bool {
        if let email = AccountDeduplicator.normalizedEmail(status.email),
           antigravityAccounts.contains(where: { AccountDeduplicator.normalizedEmail($0.email) == email }) {
            return true
        }
        return antigravityAccounts.contains { $0.credentialFingerprint == status.credentialFingerprint }
    }

    private func claudeProfileURL(for account: ClaudeAccount) async -> URL? {
        if account.usesDefaultProfile { return nil }
        return await store.claudeProfileURL(named: account.profileDirectoryName)
    }

    private func activateClaudeProfile(_ profile: URL?) async throws {
        let resolvedProfile = profile ?? defaultClaudeConfigURL
        try await store.setActiveClaudeProfile(resolvedProfile)
        await claudeEnvironmentService.activate(profile: resolvedProfile)
    }

    private func cursorProfileURL(for account: CursorAccount) async -> URL? {
        if account.usesDefaultProfile { return nil }
        return await store.cursorProfileURL(named: account.profileDirectoryName)
    }

    private func activateCursorProfile(_ profile: URL?, usesFileCredentialStore: Bool) async throws {
        try await store.setActiveCursorProfile(
            profile ?? defaultCursorConfigURL,
            usesFileCredentialStore: usesFileCredentialStore
        )
    }

    private func reconcileClaudeAccounts() async {
        guard !claudeAccounts.isEmpty else {
            state.activeClaudeAccountId = nil
            return
        }
        let requestedID = state.activeClaudeAccountId ?? claudeAccounts.first(where: \.isActive)?.id
        let activeID = requestedID.flatMap { id in claudeAccounts.contains(where: { $0.id == id }) ? id : nil }
            ?? claudeAccounts[0].id
        for index in claudeAccounts.indices {
            claudeAccounts[index].isActive = claudeAccounts[index].id == activeID
        }
        state.activeClaudeAccountId = activeID
        if let account = claudeAccounts.first(where: { $0.id == activeID }) {
            let profile = await claudeProfileURL(for: account)
            try? await activateClaudeProfile(profile)
        }
        try? await persistAll()
    }

    private func reconcileCursorAccounts() async {
        guard !cursorAccounts.isEmpty else {
            state.activeCursorAccountId = nil
            return
        }
        let requestedID = state.activeCursorAccountId ?? cursorAccounts.first(where: \.isActive)?.id
        let activeID = requestedID.flatMap { id in cursorAccounts.contains(where: { $0.id == id }) ? id : nil }
            ?? cursorAccounts[0].id
        for index in cursorAccounts.indices {
            cursorAccounts[index].isActive = cursorAccounts[index].id == activeID
        }
        state.activeCursorAccountId = activeID
        if let account = cursorAccounts.first(where: { $0.id == activeID }) {
            try? await activateCursorProfile(
                await cursorProfileURL(for: account),
                usesFileCredentialStore: account.usesFileCredentialStore
            )
        }
        try? await persistAll()
    }

    private func reconcileAntigravityAccounts() async {
        guard !antigravityAccounts.isEmpty else {
            state.activeAntigravityAccountId = nil
            return
        }
        let requestedID = state.activeAntigravityAccountId
            ?? antigravityAccounts.first(where: \.isActive)?.id
        let activeID = requestedID.flatMap { id in
            antigravityAccounts.contains(where: { $0.id == id }) ? id : nil
        } ?? antigravityAccounts[0].id
        for index in antigravityAccounts.indices {
            antigravityAccounts[index].isActive = antigravityAccounts[index].id == activeID
        }
        state.activeAntigravityAccountId = activeID
        if let account = antigravityAccounts.first(where: { $0.id == activeID }) {
            try? await antigravityAccountService.restoreLiveCredentialIfMissing(profileKey: account.credentialKey)
        }
        try? await persistAll()
    }

    private func reconcileCopilotAccounts() async {
        guard !copilotAccounts.isEmpty else {
            state.activeCopilotAccountId = nil
            return
        }
        guard let service = copilotAccountService,
              let status = try? service.status() else { return }
        for index in copilotAccounts.indices {
            copilotAccounts[index].isActive = copilotIdentity(for: copilotAccounts[index]) == status.activeIdentity
        }
        state.activeCopilotAccountId = copilotAccounts.first(where: \.isActive)?.id
        try? await persistAll()
    }

    private func startActivityMonitoring() {
        let monitor = CodexActivityMonitor(
            codexHome: defaultAuthURL.deletingLastPathComponent(),
            onPossibleAuthChange: { [weak self] in
                Task { await self?.checkExternalChange() }
            },
            onCodexActivity: { [weak self] in
                self?.handleCodexActivity()
            }
        )
        activityMonitor = monitor
        monitor.start()
    }

    private func handleCodexActivity() {
        guard let id = activeAccount?.id else { return }
        refresh(id)
    }

    private func checkExternalChange() async {
        guard let current = authModificationDate() else {
            externalAccountDetected = true
            return
        }
        guard let expected = state.defaultAuthModificationDate,
              abs(current.timeIntervalSince(expected)) <= 1 else {
            await reconcileActiveAccount()
            return
        }
    }

    private func reconcileActiveAccount() async {
        guard FileManager.default.fileExists(atPath: defaultAuthURL.path), let service = accountService else {
            externalAccountDetected = true
            return
        }

        do {
            let identity = try await service.readIdentity(profile: nil)
            guard let email = AccountDeduplicator.normalizedEmail(identity.email),
                  let matchedIndex = accounts.firstIndex(where: {
                      AccountDeduplicator.normalizedEmail($0.email) == email
                  }) else {
                for index in accounts.indices { accounts[index].isActive = false }
                state.activeAccountId = nil
                state.defaultAuthModificationDate = authModificationDate()
                externalAccountDetected = true
                try await persist()
                return
            }

            for index in accounts.indices { accounts[index].isActive = index == matchedIndex }
            state.activeAccountId = accounts[matchedIndex].id
            state.defaultAuthModificationDate = authModificationDate()
            externalAccountDetected = false

            let profileAuth = await store.profileURL(named: accounts[matchedIndex].profileDirectoryName)
                .appendingPathComponent("auth.json")
            try await store.copyCredential(from: defaultAuthURL, to: profileAuth)
            try await persist()
        } catch {
            logger.warning("Không thể xác minh tài khoản Codex đang active khi khởi động: \(self.shortMessage(error), privacy: .public)")
        }
    }

    private func authModificationDate() -> Date? {
        try? defaultAuthURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func advanceExpiredQuotaWindows(now: Date = Date()) async {
        var changed = false
        for index in accounts.indices {
            guard var usage = accounts[index].usage else { continue }
            if usage.advanceExpiredWindows(now: now) {
                accounts[index].usage = usage
                changed = true
            }
        }
        if changed { try? await persist() }
        scheduleQuotaResetHandling()
    }

    private func scheduleQuotaResetHandling() {
        quotaResetNotificationService.scheduleResetNotifications(
            accounts: accounts,
            enabled: quotaResetNotificationsEnabled,
            language: LocalizationManager.shared.language
        )

        quotaResetTask?.cancel()
        let now = Date()
        let nextReset = accounts
            .flatMap { account in [account.usage?.fiveHour?.resetsAt, account.usage?.weekly?.resetsAt] }
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
        guard let nextReset else { return }

        quotaResetTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(nextReset.timeIntervalSinceNow))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.advanceExpiredQuotaWindows()
        }
    }

    private func persist() async throws { try await store.save(accounts: accounts, state: state) }
    private func persistAll() async throws {
        try await store.save(accounts: accounts, state: state)
        try await store.saveClaudeAccounts(claudeAccounts, state: state)
        try await store.saveCursorAccounts(cursorAccounts, state: state)
        try await store.saveAntigravityAccounts(antigravityAccounts, state: state)
        try await store.saveCopilotAccounts(copilotAccounts, state: state)
    }
    private func shortMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let normalized = message.lowercased()
        if normalized.contains("login server error") || normalized.contains("login was not completed") {
            return L10n.text("login_not_completed")
        }
        if normalized.contains("workspace routing discovery timed out") {
            return L10n.text("workspace_discovery_timed_out")
        }
        if normalized.contains("workspace routing discovery unauthorized") || normalized.contains("unauthorized [401]") {
            return L10n.text("codex_session_expired")
        }
        return message
    }

    private func requiresReauthentication(_ error: Error) -> Bool {
        let message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        return message.contains("workspace routing discovery unauthorized")
            || message.contains("unauthorized [401]")
            || message == L10n.text("switch_verify_mismatch").lowercased()
    }

    private func refreshErrorKind(for error: Error) -> AccountRefreshError.Kind {
        let message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        if message.contains("workspace routing discovery timed out") {
            return .workspaceDiscoveryTimedOut
        }
        return .other
    }
    private func show(_ error: Error) {
        let message = shortMessage(error)
        showMessage(message)
        logger.error("Thao tác thất bại: \(message, privacy: .public)")
    }

    private func showMessage(_ message: String) {
        NativeErrorAlert.show(
            title: "LLM Account Switcher",
            message: message,
            closeTitle: L10n.text("close")
        )
    }
}
