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
    var state = AppState()
    var codexVersion: String?
    var isLoading = true
    var isAddingAccount = false
    var isImportingAccount = false
    var loginMessageKey: String?
    var refreshingIDs: Set<UUID> = []
    var processingIDs: Set<UUID> = []
    var externalAccountDetected = false

    private let store: AccountStore
    private let resolver = CodexBinaryResolver()
    private let refreshGate = RefreshGate(limit: 2)
    private let launchService = LaunchAtLoginService()
    private let codexDesktopRelaunchService = CodexDesktopRelaunchService()
    private let quotaResetNotificationService = QuotaResetNotificationService()
    private let logger = Logger(subsystem: "local.codex-account-manager.app", category: "model")
    private var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private var loginTask: Task<Void, Never>?
    private var loginClient: CodexAppServerClient?
    private var loginID: String?
    private var activityMonitor: CodexActivityMonitor?

    init(store: AccountStore = AccountStore()) {
        self.store = store
        Task { await load() }
    }

    var activeAccount: CodexAccount? { accounts.first(where: \.isActive) }
    var quotaResetNotificationsEnabled: Bool { state.quotaResetNotificationsEnabled != false }
    var languageOverride: AppLanguage? { state.languageOverride }
    var canImportCurrentAccount: Bool {
        FileManager.default.fileExists(atPath: defaultAuthURL.path)
    }
    var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    func load() async {
        let loaded = await store.load()
        let deduplicated = AccountDeduplicator.split(loaded.0)
        accounts = deduplicated.unique
        state = loaded.1
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
        await reconcileActiveAccount()
        isLoading = false
        if !accounts.isEmpty, quotaResetNotificationsEnabled {
            quotaResetNotificationService.requestAuthorization()
        }
        if CommandLine.arguments.contains("--test-notification") {
            quotaResetNotificationService.sendTestNotification(
                accountName: activeAccount?.email ?? accounts.first?.email ?? "example@codex-account-manager.app",
                language: LocalizationManager.shared.language
            )
        }
        startActivityMonitoring()
    }

    func menuOpened() {
        Task {
            await checkExternalChange()
        }
    }

    func resolveBinary(manualPath: String? = nil) async {
        if CommandLine.arguments.contains("--simulate-no-codex") {
            state.codexBinaryPath = nil
            codexVersion = nil
            return
        }
        let info: CodexBinaryInfo?
        if let manualPath, let version = await resolver.verify(path: manualPath) {
            info = CodexBinaryInfo(path: manualPath, version: version)
        } else {
            info = await resolver.resolve(savedPath: state.codexBinaryPath)
        }
        state.codexBinaryPath = info?.path
        codexVersion = info?.version
        try? await persist()
    }

    func chooseBinary() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("select_binary_title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task {
            await resolveBinary(manualPath: path)
            if codexVersion == nil { showMessage(L10n.text("invalid_binary")) }
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
                        throw CodexAccountManagerError.message(L10n.text("account_exists"))
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
                } catch { try? await store.removeProfile(named: id.uuidString); throw error }
            } catch { show(error) }
        }
    }

    func addAccount() {
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
                        throw CodexAccountManagerError.message(L10n.text("account_exists"))
                    }
                    accounts.append(makeAccount(id: id, result: result, isActive: false))
                    if quotaResetNotificationsEnabled {
                        quotaResetNotificationService.requestAuthorization()
                    }
                    try await persist()
                } catch { try? await store.removeProfile(named: id.uuidString); throw error }
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
        guard !processingIDs.contains(id) else { return }
        processingIDs.insert(id)
        Task {
            defer { processingIDs.remove(id) }
            do { try await activate(id) } catch { show(error) }
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
        Task { try? await persist() }
    }

    func setLanguageOverride(_ language: AppLanguage?) {
        state.languageOverride = language
        LocalizationManager.shared.setLanguageOverride(language)
        Task { try? await persist() }
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
            try await service.read(profile: profile).remote
        }
        let date = try await switcher.switchAccount(from: activeAccount, to: target)
        for index in accounts.indices { accounts[index].isActive = accounts[index].id == id }
        state.activeAccountId = id
        state.defaultAuthModificationDate = date
        externalAccountDetected = false
        try await persist()
        try await codexDesktopRelaunchService.relaunchIfRunning()
    }

    private func makeAccount(id: UUID, result: RefreshedAccount, isActive: Bool) -> CodexAccount {
        CodexAccount(id: id, displayName: AccountNumbering.takeNext(from: &state), email: result.remote.email,
                     rawPlan: result.remote.plan ?? result.usage?.sourcePlan, profileDirectoryName: id.uuidString,
                     isActive: isActive, usage: result.usage, lastRefreshAt: Date(),
                     lastSuccessfulRefreshAt: Date(), lastError: nil)
    }

    private func containsAccount(email: String?) -> Bool {
        guard let email = AccountDeduplicator.normalizedEmail(email) else { return false }
        return accounts.contains { AccountDeduplicator.normalizedEmail($0.email) == email }
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

    private func persist() async throws { try await store.save(accounts: accounts, state: state) }
    private func shortMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let normalized = message.lowercased()
        if normalized.contains("login server error") || normalized.contains("login was not completed") {
            return L10n.text("login_not_completed")
        }
        if normalized.contains("workspace routing discovery timed out") {
            return L10n.text("workspace_discovery_timed_out")
        }
        return message
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
            title: "codex-account-manager",
            message: message,
            closeTitle: L10n.text("close")
        )
    }
}
