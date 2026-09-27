import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let navigation = SettingsNavigationModel()
    private var controller: NSWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window = controller?.window {
            window.title = L10n.text("settings")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsWindowView(model: model, navigation: navigation))
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.text("settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 800, height: 560))
        window.minSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAccounts() {
        navigation.selection = .accounts
        show()
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts
    case general
    case about

    var id: Self { self }

    var icon: String {
        switch self {
        case .accounts: "person.2"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }

    @MainActor
    func title(_ localization: LocalizationManager) -> String {
        switch self {
        case .accounts: localization.text("accounts")
        case .general: localization.text("general")
        case .about: localization.text("about")
        }
    }
}

@MainActor @Observable
private final class SettingsNavigationModel {
    var selection: SettingsSection? = .accounts
}

private struct SettingsWindowView: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigationModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        settingsNavigation
            .frame(minWidth: 680, minHeight: 460)
            .onAppear { model.menuOpened() }
    }

    private var settingsNavigation: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            navigation.selection = section
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 20)
                                Text(section.title(localization))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(navigation.selection == section ? Color.primary.opacity(0.10) : .clear)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                Text("LLM Account Switcher")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(16)
            }
            .padding(.top, 10)
            .background(.ultraThinMaterial)
            .navigationTitle(localization.text("settings"))
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                switch navigation.selection ?? .accounts {
                case .accounts:
                    AccountManagementSettingsView(model: model)
                case .general:
                    GeneralSettingsView(model: model)
                case .about:
                    AboutSettingsView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct AboutSettingsView: View {
    @State private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                VStack(spacing: 5) {
                    Text("LLM Account Switcher")
                        .font(.title2.weight(.bold))
                    Text(localization.format("app_version", version))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(localization.text("app_description"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)

                Text(localization.text("community_disclaimer"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 420)

                SettingsActionButton(
                    title: "GitHub",
                    icon: "link",
                    isDisabled: false,
                    action: openGitHub
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .navigationTitle(localization.text("about"))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appIcon: NSImage {
        guard let url = Bundle.main.url(forResource: "llm-account-switcher-icon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSApp.applicationIconImage
        }
        return image
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/vuduchiieu/codex-account-manager") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AccountManagementSettingsView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared
    @State private var draggedAccountID: UUID?
    @State private var hoveredAccountID: UUID?
    @State private var selectedProvider: LLMProvider = .codex
    @State private var providerOrder = LLMProviderOrderStore.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    LLMProviderPicker(
                        selection: $selectedProvider,
                        providers: providerOrder.providers,
                        accountCounts: providerAccountCounts,
                        allowsReordering: true,
                        onMoveProvider: { source, destination in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                providerOrder.move(source, over: destination)
                            }
                        }
                    )

                    HStack(alignment: .center, spacing: 10) {
                        Spacer()
                        if selectedProvider == .codex {
                            SettingsActionButton(
                            title: localization.text("import_current"),
                            icon: "square.and.arrow.down",
                            isDisabled: !providerOrder.isEnabled(.codex) || model.state.codexBinaryPath == nil || !model.canImportCurrentAccount || model.isImportingAccount,
                                action: model.importCurrentAccount
                            )
                            SettingsActionButton(
                            title: localization.text("add_account"),
                            icon: "plus",
                            isDisabled: !providerOrder.isEnabled(.codex) || model.state.codexBinaryPath == nil || model.isAddingAccount,
                                action: model.addAccount
                            )
                        } else if selectedProvider == .claude {
                            SettingsActionButton(
                            title: localization.text("import_current_claude"),
                            icon: "square.and.arrow.down",
                            isDisabled: !providerOrder.isEnabled(.claude) || model.state.claudeBinaryPath == nil || model.isImportingClaudeAccount,
                                action: model.importCurrentClaudeAccount
                            )
                            SettingsActionButton(
                            title: localization.text("add_account"),
                            icon: "plus",
                            isDisabled: !providerOrder.isEnabled(.claude) || model.state.claudeBinaryPath == nil || model.isAddingClaudeAccount,
                                action: model.addClaudeAccount
                            )
                        } else if selectedProvider == .cursor {
                            SettingsActionButton(
                                title: localization.text("import_current_cursor"),
                                icon: "square.and.arrow.down",
                                isDisabled: !providerOrder.isEnabled(.cursor) || model.state.cursorBinaryPath == nil || model.isImportingCursorAccount,
                                action: model.importCurrentCursorAccount
                            )
                            SettingsActionButton(
                                title: localization.text("add_account"),
                                icon: "plus",
                                isDisabled: !providerOrder.isEnabled(.cursor) || model.state.cursorBinaryPath == nil || model.isAddingCursorAccount,
                                action: model.addCursorAccount
                            )
                        } else if selectedProvider == .antigravity {
                            SettingsActionButton(
                                title: localization.text("import_current_antigravity"),
                                icon: "square.and.arrow.down",
                                isDisabled: !providerOrder.isEnabled(.antigravity)
                                    || model.state.antigravityBinaryPath == nil
                                    || model.isImportingAntigravityAccount,
                                action: model.importCurrentAntigravityAccount
                            )
                            SettingsActionButton(
                                title: localization.text("add_account"),
                                icon: "plus",
                                isDisabled: !providerOrder.isEnabled(.antigravity)
                                    || model.state.antigravityBinaryPath == nil
                                    || model.isAddingAntigravityAccount,
                                action: model.addAntigravityAccount
                            )
                        } else {
                            SettingsActionButton(
                                title: localization.text("import_current_copilot"),
                                icon: "square.and.arrow.down",
                                isDisabled: !providerOrder.isEnabled(.copilot)
                                    || model.state.copilotBinaryPath == nil
                                    || model.isImportingCopilotAccount,
                                action: model.importCurrentCopilotAccount
                            )
                            SettingsActionButton(
                                title: localization.text("add_account"),
                                icon: "plus",
                                isDisabled: !providerOrder.isEnabled(.copilot)
                                    || model.state.copilotBinaryPath == nil
                                    || model.isAddingCopilotAccount,
                                action: model.addCopilotAccount
                            )
                        }
                    }
                }

                if selectedProvider == .codex {
                    codexCLISettings
                    if providerOrder.isEnabled(.codex) {
                        SettingsGroup(title: localization.format("account_count", model.accounts.count)) {
                            codexAccountsContent
                        }
                    } else {
                        providerDisabledContent(.codex)
                    }
                } else if selectedProvider == .claude {
                    claudeCLISettings
                    if providerOrder.isEnabled(.claude) {
                        SettingsGroup(title: localization.format("account_count", model.claudeAccounts.count)) {
                            claudeAccountsContent
                        }
                    } else {
                        providerDisabledContent(.claude)
                    }
                } else if selectedProvider == .cursor {
                    cursorCLISettings
                    if providerOrder.isEnabled(.cursor) {
                        SettingsGroup(title: localization.format("account_count", model.cursorAccounts.count)) {
                            cursorAccountsContent
                        }
                    } else {
                        providerDisabledContent(.cursor)
                    }
                } else if selectedProvider == .antigravity {
                    antigravityCLISettings
                    if providerOrder.isEnabled(.antigravity) {
                        SettingsGroup(title: localization.format("account_count", model.antigravityAccounts.count)) {
                            antigravityAccountsContent
                        }
                    } else {
                        providerDisabledContent(.antigravity)
                    }
                } else {
                    copilotCLISettings
                    if providerOrder.isEnabled(.copilot) {
                        SettingsGroup(title: localization.format("account_count", model.copilotAccounts.count)) {
                            copilotAccountsContent
                        }
                    } else {
                        providerDisabledContent(.copilot)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle(localization.text("manage_accounts"))
    }

    private var codexCLISettings: some View {
        SettingsGroup(title: localization.text("codex_cli")) {
            providerToggleRow(.codex)

            Divider().padding(.leading, 50)
            HStack(spacing: 14) {
                SettingsRowIcon(systemName: "terminal")
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("binary_path"))
                    binaryPathStatus(.codex, path: model.state.codexBinaryPath)
                }
                Spacer(minLength: 12)
                SettingsActionButton(
                    title: localization.text("choose_binary"),
                    icon: "folder",
                    isDisabled: model.resolvingProviderBinaries.contains(.codex),
                    action: model.chooseBinary
                )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)

        }
    }

    private var claudeCLISettings: some View {
        SettingsGroup(title: localization.text("claude_code")) {
            providerToggleRow(.claude)

            Divider().padding(.leading, 50)
            HStack(spacing: 14) {
                SettingsRowIcon(systemName: "sparkles")
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("binary_path"))
                    binaryPathStatus(.claude, path: model.state.claudeBinaryPath)
                }
                Spacer(minLength: 12)
                SettingsActionButton(
                    title: localization.text("choose_claude_binary"),
                    icon: "folder",
                    isDisabled: model.resolvingProviderBinaries.contains(.claude),
                    action: model.chooseClaudeBinary
                )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)

            if let launcherPath = model.claudeLauncherPath {
                Divider().padding(.leading, 50)
                HStack(spacing: 14) {
                    SettingsRowIcon(systemName: "command")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.text("managed_claude_command"))
                        Text(launcherPath)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    SettingsActionButton(
                        title: localization.text("copy_path"),
                        icon: "doc.on.doc",
                        isDisabled: false,
                        action: { copyToPasteboard(launcherPath) }
                    )
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
        }
    }

    private var cursorCLISettings: some View {
        SettingsGroup(title: localization.text("cursor_agent")) {
            providerToggleRow(.cursor)

            Divider().padding(.leading, 50)
            HStack(spacing: 14) {
                SettingsRowIcon(systemName: "cursorarrow.rays")
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("binary_path"))
                    binaryPathStatus(.cursor, path: model.state.cursorBinaryPath)
                }
                Spacer(minLength: 12)
                SettingsActionButton(
                    title: localization.text("choose_cursor_binary"),
                    icon: "folder",
                    isDisabled: model.resolvingProviderBinaries.contains(.cursor),
                    action: model.chooseCursorBinary
                )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)

            if let launcherPath = model.cursorLauncherPath {
                Divider().padding(.leading, 50)
                HStack(spacing: 14) {
                    SettingsRowIcon(systemName: "command")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.text("managed_cursor_command"))
                        Text(launcherPath)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    SettingsActionButton(
                        title: localization.text("copy_path"),
                        icon: "doc.on.doc",
                        isDisabled: false,
                        action: { copyToPasteboard(launcherPath) }
                    )
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
        }
    }

    private var antigravityCLISettings: some View {
        SettingsGroup(title: localization.text("antigravity_cli")) {
            providerToggleRow(.antigravity)

            Divider().padding(.leading, 50)
            HStack(spacing: 14) {
                SettingsRowIcon(systemName: "diamond")
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("binary_path"))
                    binaryPathStatus(.antigravity, path: model.state.antigravityBinaryPath)
                }
                Spacer(minLength: 12)
                SettingsActionButton(
                    title: localization.text("choose_antigravity_binary"),
                    icon: "folder",
                    isDisabled: model.resolvingProviderBinaries.contains(.antigravity),
                    action: model.chooseAntigravityBinary
                )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)

        }
    }

    private var copilotCLISettings: some View {
        SettingsGroup(title: localization.text("copilot_cli")) {
            providerToggleRow(.copilot)

            Divider().padding(.leading, 50)
            HStack(spacing: 14) {
                SettingsRowIcon(systemName: "chevron.left.forwardslash.chevron.right")
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("binary_path"))
                    binaryPathStatus(.copilot, path: model.state.copilotBinaryPath)
                }
                Spacer(minLength: 12)
                SettingsActionButton(
                    title: localization.text("choose_copilot_binary"),
                    icon: "folder",
                    isDisabled: model.resolvingProviderBinaries.contains(.copilot),
                    action: model.chooseCopilotBinary
                )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)

            if let launcherPath = model.copilotLauncherPath {
                Divider().padding(.leading, 50)
                HStack(spacing: 14) {
                    SettingsRowIcon(systemName: "command")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.text("managed_copilot_command"))
                        Text(launcherPath)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    SettingsActionButton(
                        title: localization.text("copy_path"),
                        icon: "doc.on.doc",
                        isDisabled: false,
                        action: { copyToPasteboard(launcherPath) }
                    )
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
        }
    }

    private func providerSettings(_ provider: LLMProvider) -> some View {
        SettingsGroup(title: provider.name) {
            providerToggleRow(provider)
        }
    }

    @ViewBuilder
    private func binaryPathStatus(_ provider: LLMProvider, path: String?) -> some View {
        if model.resolvingProviderBinaries.contains(provider) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(localization.text("onboarding_detecting_binary"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text(path ?? localization.text("not_configured"))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    private func providerToggleRow(_ provider: LLMProvider) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemName: "power")
            Text(localization.format("enable_provider", provider.name))
            Spacer(minLength: 12)
            Toggle(
                "",
                isOn: Binding(
                    get: { providerOrder.isEnabled(provider) },
                    set: { enabled in
                        providerOrder.setEnabled(enabled, for: provider)
                        guard enabled else { return }
                        Task {
                            switch provider {
                            case .codex:
                                await model.resolveBinary()
                            case .claude:
                                await model.resolveClaudeBinary()
                            case .cursor:
                                await model.resolveCursorBinary()
                            case .antigravity:
                                await model.resolveAntigravityBinary()
                            case .copilot:
                                await model.resolveCopilotBinary()
                            }
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .focusable(false)
            .disabled(model.resolvingProviderBinaries.contains(provider))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func providerDisabledContent(_ provider: LLMProvider) -> some View {
        ContentUnavailableView(
            localization.format("provider_disabled", provider.name),
            systemImage: "power",
            description: Text(localization.text("provider_disabled_description"))
        )
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    @ViewBuilder private var codexAccountsContent: some View {
        if model.state.codexBinaryPath == nil {
            ContentUnavailableView(
                localization.text("codex_cli_not_found"),
                systemImage: "terminal",
                description: Text(localization.text("configure_cli_in_accounts"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if model.accounts.isEmpty {
            ContentUnavailableView(
                localization.text("no_accounts"),
                systemImage: "person.crop.circle.badge.plus",
                description: Text(localization.text("no_accounts_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                        SettingsAccountRow(
                            account: account,
                            isProcessing: model.processingIDs.contains(account.id),
                            onDelete: { confirmDelete(account) },
                            onBeginDrag: {
                                draggedAccountID = account.id
                                hoveredAccountID = nil
                                return NSItemProvider(object: account.id.uuidString as NSString)
                            },
                            model: model
                        )
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: SettingsAccountOrderDropDelegate(
                                destinationID: account.id,
                                draggedAccountID: $draggedAccountID,
                                hoveredAccountID: $hoveredAccountID,
                                model: model
                            )
                        )
                        .overlay(alignment: insertionIndicatorAlignment(for: account.id)) {
                            if hoveredAccountID == account.id, draggedAccountID != account.id {
                                Capsule()
                                    .fill(.primary.opacity(0.7))
                                    .frame(height: 2)
                                    .padding(.horizontal, 10)
                            }
                        }

                        if index < model.accounts.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.accounts.count) * 62, 372))
        }
    }

    @ViewBuilder private var claudeAccountsContent: some View {
        if model.state.claudeBinaryPath == nil {
            ContentUnavailableView(
                localization.text("claude_cli_not_found"),
                systemImage: "sparkles",
                description: Text(localization.text("configure_claude_cli_in_accounts"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if model.claudeAccounts.isEmpty {
            ContentUnavailableView(
                localization.text("no_accounts"),
                systemImage: "person.crop.circle.badge.plus",
                description: Text(localization.text("no_claude_accounts_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.claudeAccounts.enumerated()), id: \.element.id) { index, account in
                        ClaudeSettingsAccountRow(
                            account: account,
                            isProcessing: model.processingClaudeIDs.contains(account.id),
                            onDelete: { confirmDeleteClaude(account) },
                            onBeginDrag: {
                                draggedAccountID = account.id
                                hoveredAccountID = nil
                                return NSItemProvider(object: account.id.uuidString as NSString)
                            },
                            model: model
                        )
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: ClaudeSettingsAccountOrderDropDelegate(
                                destinationID: account.id,
                                draggedAccountID: $draggedAccountID,
                                hoveredAccountID: $hoveredAccountID,
                                model: model
                            )
                        )
                        .overlay(alignment: claudeInsertionIndicatorAlignment(for: account.id)) {
                            if hoveredAccountID == account.id, draggedAccountID != account.id {
                                Capsule()
                                    .fill(.primary.opacity(0.7))
                                    .frame(height: 2)
                                    .padding(.horizontal, 10)
                            }
                        }

                        if index < model.claudeAccounts.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.claudeAccounts.count) * 62, 372))
        }
    }

    @ViewBuilder private var cursorAccountsContent: some View {
        if model.state.cursorBinaryPath == nil {
            ContentUnavailableView(
                localization.text("cursor_cli_not_found"),
                systemImage: "cursorarrow.rays",
                description: Text(localization.text("configure_cursor_cli_in_accounts"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if model.cursorAccounts.isEmpty {
            ContentUnavailableView(
                localization.text("no_accounts"),
                systemImage: "person.crop.circle.badge.plus",
                description: Text(localization.text("no_cursor_accounts_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.cursorAccounts.enumerated()), id: \.element.id) { index, account in
                        CursorSettingsAccountRow(
                            account: account,
                            isProcessing: model.processingCursorIDs.contains(account.id),
                            onDelete: { confirmDeleteCursor(account) },
                            onBeginDrag: {
                                draggedAccountID = account.id
                                hoveredAccountID = nil
                                return NSItemProvider(object: account.id.uuidString as NSString)
                            },
                            model: model
                        )
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: CursorSettingsAccountOrderDropDelegate(
                                destinationID: account.id,
                                draggedAccountID: $draggedAccountID,
                                hoveredAccountID: $hoveredAccountID,
                                model: model
                            )
                        )
                        .overlay(alignment: cursorInsertionIndicatorAlignment(for: account.id)) {
                            if hoveredAccountID == account.id, draggedAccountID != account.id {
                                Capsule()
                                    .fill(.primary.opacity(0.7))
                                    .frame(height: 2)
                                    .padding(.horizontal, 10)
                            }
                        }

                        if index < model.cursorAccounts.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.cursorAccounts.count) * 62, 372))
        }
    }

    @ViewBuilder private var antigravityAccountsContent: some View {
        if model.state.antigravityBinaryPath == nil {
            ContentUnavailableView(
                localization.text("antigravity_cli_not_found"),
                systemImage: "diamond",
                description: Text(localization.text("configure_antigravity_cli_in_accounts"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if model.antigravityAccounts.isEmpty {
            ContentUnavailableView(
                localization.text("no_accounts"),
                systemImage: "person.crop.circle.badge.plus",
                description: Text(localization.text("no_antigravity_accounts_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.antigravityAccounts.enumerated()), id: \.element.id) { index, account in
                        AntigravitySettingsAccountRow(
                            account: account,
                            isProcessing: model.processingAntigravityIDs.contains(account.id),
                            onDelete: { confirmDeleteAntigravity(account) },
                            onBeginDrag: {
                                draggedAccountID = account.id
                                hoveredAccountID = nil
                                return NSItemProvider(object: account.id.uuidString as NSString)
                            },
                            model: model
                        )
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: AntigravitySettingsAccountOrderDropDelegate(
                                destinationID: account.id,
                                draggedAccountID: $draggedAccountID,
                                hoveredAccountID: $hoveredAccountID,
                                model: model
                            )
                        )
                        .overlay(alignment: antigravityInsertionIndicatorAlignment(for: account.id)) {
                            if hoveredAccountID == account.id, draggedAccountID != account.id {
                                Capsule()
                                    .fill(.primary.opacity(0.7))
                                    .frame(height: 2)
                                    .padding(.horizontal, 10)
                            }
                        }
                        if index < model.antigravityAccounts.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.antigravityAccounts.count) * 62, 372))
        }
    }

    @ViewBuilder private var copilotAccountsContent: some View {
        if model.state.copilotBinaryPath == nil {
            ContentUnavailableView(
                localization.text("copilot_cli_not_found"),
                systemImage: "chevron.left.forwardslash.chevron.right",
                description: Text(localization.text("configure_copilot_cli_in_accounts"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if model.copilotAccounts.isEmpty {
            ContentUnavailableView(
                localization.text("no_accounts"),
                systemImage: "person.crop.circle.badge.plus",
                description: Text(localization.text("no_copilot_accounts_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.copilotAccounts.enumerated()), id: \.element.id) { index, account in
                        CopilotSettingsAccountRow(
                            account: account,
                            isProcessing: model.processingCopilotIDs.contains(account.id),
                            onDelete: { confirmDeleteCopilot(account) },
                            onBeginDrag: {
                                draggedAccountID = account.id
                                hoveredAccountID = nil
                                return NSItemProvider(object: account.id.uuidString as NSString)
                            },
                            model: model
                        )
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: CopilotSettingsAccountOrderDropDelegate(
                                destinationID: account.id,
                                draggedAccountID: $draggedAccountID,
                                hoveredAccountID: $hoveredAccountID,
                                model: model
                            )
                        )
                        .overlay(alignment: copilotInsertionIndicatorAlignment(for: account.id)) {
                            if hoveredAccountID == account.id, draggedAccountID != account.id {
                                Capsule()
                                    .fill(.primary.opacity(0.7))
                                    .frame(height: 2)
                                    .padding(.horizontal, 10)
                            }
                        }
                        if index < model.copilotAccounts.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.copilotAccounts.count) * 62, 372))
        }
    }

    private var providerAccountCounts: [LLMProvider: Int] {
        Dictionary(uniqueKeysWithValues: LLMProvider.allCases.map { provider in
            let count: Int
            switch provider {
            case .codex: count = model.state.codexBinaryPath == nil ? 0 : model.accounts.count
            case .claude: count = model.state.claudeBinaryPath == nil ? 0 : model.claudeAccounts.count
            case .cursor: count = model.state.cursorBinaryPath == nil ? 0 : model.cursorAccounts.count
            case .antigravity: count = model.state.antigravityBinaryPath == nil ? 0 : model.antigravityAccounts.count
            case .copilot: count = model.state.copilotBinaryPath == nil ? 0 : model.copilotAccounts.count
            }
            return (provider, count)
        })
    }

    private var selectedAccountCount: Int {
        providerAccountCounts[selectedProvider, default: 0]
    }

    private func insertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.accounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.accounts.firstIndex(where: { $0.id == destinationID }) else {
            return .top
        }
        return sourceIndex < destinationIndex ? .bottom : .top
    }

    private func claudeInsertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.claudeAccounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.claudeAccounts.firstIndex(where: { $0.id == destinationID }) else {
            return .top
        }
        return sourceIndex < destinationIndex ? .bottom : .top
    }

    private func cursorInsertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.cursorAccounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.cursorAccounts.firstIndex(where: { $0.id == destinationID }) else {
            return .top
        }
        return sourceIndex < destinationIndex ? .bottom : .top
    }

    private func antigravityInsertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.antigravityAccounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.antigravityAccounts.firstIndex(where: { $0.id == destinationID }) else {
            return .top
        }
        return sourceIndex < destinationIndex ? .bottom : .top
    }

    private func copilotInsertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.copilotAccounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.copilotAccounts.firstIndex(where: { $0.id == destinationID }) else {
            return .top
        }
        return sourceIndex < destinationIndex ? .bottom : .top
    }

    private func confirmDelete(_ account: CodexAccount) {
        let accountName = account.email ?? account.displayName
        let confirmed = NativeDeleteAlert.confirm(
            title: localization.format("delete_confirmation", accountName),
            message: localization.text("delete_message"),
            deleteTitle: localization.text("delete_local_profile"),
            cancelTitle: localization.text("cancel")
        )
        if confirmed { model.delete(account.id) }
    }

    private func confirmDeleteClaude(_ account: ClaudeAccount) {
        let accountName = account.email ?? account.displayName
        let confirmed = NativeDeleteAlert.confirm(
            title: localization.format("delete_confirmation", accountName),
            message: localization.text("delete_claude_message"),
            deleteTitle: localization.text("delete_local_profile"),
            cancelTitle: localization.text("cancel")
        )
        if confirmed { model.deleteClaude(account.id) }
    }

    private func confirmDeleteCursor(_ account: CursorAccount) {
        let accountName = account.email ?? account.displayName
        let confirmed = NativeDeleteAlert.confirm(
            title: localization.format("delete_confirmation", accountName),
            message: localization.text("delete_cursor_message"),
            deleteTitle: localization.text("delete_local_profile"),
            cancelTitle: localization.text("cancel")
        )
        if confirmed { model.deleteCursor(account.id) }
    }

    private func confirmDeleteAntigravity(_ account: AntigravityAccount) {
        let accountName = account.email ?? account.displayName
        let confirmed = NativeDeleteAlert.confirm(
            title: localization.format("delete_confirmation", accountName),
            message: localization.text("delete_antigravity_message"),
            deleteTitle: localization.text("delete_local_profile"),
            cancelTitle: localization.text("cancel")
        )
        if confirmed { model.deleteAntigravity(account.id) }
    }

    private func confirmDeleteCopilot(_ account: CopilotAccount) {
        let confirmed = NativeDeleteAlert.confirm(
            title: localization.format("delete_confirmation", account.login),
            message: localization.text("delete_copilot_message"),
            deleteTitle: localization.text("delete_local_profile"),
            cancelTitle: localization.text("cancel")
        )
        if confirmed { model.deleteCopilot(account.id) }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct SettingsAccountRow: View {
    let account: CodexAccount
    let isProcessing: Bool
    let onDelete: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.setActive(account.id)
            } label: {
                Group {
                    if model.switchingAccountID == account.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                            .font(.title3)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(model.switchingAccountID == nil && !account.isActive && !isProcessing)
            .focusable(false)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.email ?? localization.text("unknown_email"))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isProcessing {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel(localization.text("delete"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 61)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            AccountDragPreview(account: account, activeGreen: .accentColor)
        }
    }
}

private struct ClaudeSettingsAccountRow: View {
    let account: ClaudeAccount
    let isProcessing: Bool
    let onDelete: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.setActiveClaude(account.id)
            } label: {
                Group {
                    if model.switchingClaudeAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                            .font(.title3)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(model.switchingClaudeAccountID == nil && !account.isActive && !isProcessing)
            .focusable(false)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.email ?? account.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isProcessing || model.refreshingClaudeIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel(localization.text("delete"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 61)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            HStack(spacing: 10) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? account.displayName).font(.body.weight(.semibold))
                    Text(account.planDisplayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: 300, height: 58, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct CursorSettingsAccountRow: View {
    let account: CursorAccount
    let isProcessing: Bool
    let onDelete: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { model.setActiveCursor(account.id) } label: {
                Group {
                    if model.switchingCursorAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                            .font(.title3)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(model.switchingCursorAccountID == nil && !account.isActive && !isProcessing)
            .focusable(false)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.email ?? account.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isProcessing || model.refreshingCursorIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel(localization.text("delete"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 61)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            HStack(spacing: 10) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? account.displayName).font(.body.weight(.semibold))
                    Text(account.planDisplayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: 300, height: 58, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct AntigravitySettingsAccountRow: View {
    let account: AntigravityAccount
    let isProcessing: Bool
    let onDelete: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { model.setActiveAntigravity(account.id) } label: {
                Group {
                    if model.switchingAntigravityAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                            .font(.title3)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(model.switchingAntigravityAccountID == nil && !account.isActive && !isProcessing)
            .focusable(false)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.email ?? account.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isProcessing || model.refreshingAntigravityIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel(localization.text("delete"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 61)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            HStack(spacing: 10) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? account.displayName).font(.body.weight(.semibold))
                    Text(account.planDisplayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: 300, height: 58, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct CopilotSettingsAccountRow: View {
    let account: CopilotAccount
    let isProcessing: Bool
    let onDelete: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { model.setActiveCopilot(account.id) } label: {
                Group {
                    if model.switchingCopilotAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                            .font(.title3)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(model.switchingCopilotAccountID == nil && !account.isActive && !isProcessing)
            .focusable(false)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.login)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.host.replacingOccurrences(of: "https://", with: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isProcessing || model.refreshingCopilotIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel(localization.text("delete"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 61)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            HStack(spacing: 10) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.login).font(.body.weight(.semibold))
                    Text(account.planDisplayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: 300, height: 58, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: localization.text("app_preferences")) {
                    SettingsPreferenceRow(icon: "globe", title: localization.text("language")) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.languageOverride },
                                set: { model.setLanguageOverride($0) }
                            )
                        ) {
                            Text(localization.text("language_system"))
                                .tag(nil as AppLanguage?)
                            ForEach(AppLanguage.allCases) { language in
                                Text(languageName(language))
                                    .tag(language as AppLanguage?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    Divider().padding(.leading, 50)

                    SettingsPreferenceRow(icon: "power", title: localization.text("launch_at_login")) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { model.state.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .focusable(false)
                    }

                    Divider().padding(.leading, 50)

                    SettingsPreferenceRow(icon: "bell", title: localization.text("quota_reset_notifications")) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { model.quotaResetNotificationsEnabled },
                                set: { model.setQuotaResetNotificationsEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .focusable(false)
                    }
                }

            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .navigationTitle(localization.text("general"))
    }

    private func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .vietnamese: localization.text("language_vietnamese")
        case .english: localization.text("language_english")
        case .japanese: localization.text("language_japanese")
        case .chinese: localization.text("language_chinese")
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                }
        }
    }
}

private struct SettingsRowIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 20)
    }
}

private struct SettingsPreferenceRow<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemName: icon)
            Text(title)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

private struct SettingsAccountOrderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedAccountID: UUID?
    @Binding var hoveredAccountID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID, draggedAccountID != destinationID else { return }
        hoveredAccountID = destinationID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedAccountID else { return false }
        model.moveAccount(sourceID, over: destinationID)
        model.saveAccountOrder()
        draggedAccountID = nil
        hoveredAccountID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if hoveredAccountID == destinationID { hoveredAccountID = nil }
    }
}

private struct ClaudeSettingsAccountOrderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedAccountID: UUID?
    @Binding var hoveredAccountID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID, draggedAccountID != destinationID else { return }
        hoveredAccountID = destinationID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedAccountID else { return false }
        model.moveClaudeAccount(sourceID, over: destinationID)
        model.saveClaudeAccountOrder()
        draggedAccountID = nil
        hoveredAccountID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if hoveredAccountID == destinationID { hoveredAccountID = nil }
    }
}

private struct CursorSettingsAccountOrderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedAccountID: UUID?
    @Binding var hoveredAccountID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID, draggedAccountID != destinationID else { return }
        hoveredAccountID = destinationID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedAccountID else { return false }
        model.moveCursorAccount(sourceID, over: destinationID)
        model.saveCursorAccountOrder()
        draggedAccountID = nil
        hoveredAccountID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if hoveredAccountID == destinationID { hoveredAccountID = nil }
    }
}

private struct AntigravitySettingsAccountOrderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedAccountID: UUID?
    @Binding var hoveredAccountID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID, draggedAccountID != destinationID else { return }
        hoveredAccountID = destinationID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedAccountID else { return false }
        model.moveAntigravityAccount(sourceID, over: destinationID)
        model.saveAntigravityAccountOrder()
        draggedAccountID = nil
        hoveredAccountID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if hoveredAccountID == destinationID { hoveredAccountID = nil }
    }
}

private struct CopilotSettingsAccountOrderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedAccountID: UUID?
    @Binding var hoveredAccountID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID, draggedAccountID != destinationID else { return }
        hoveredAccountID = destinationID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedAccountID else { return false }
        model.moveCopilotAccount(sourceID, over: destinationID)
        model.saveCopilotAccountOrder()
        draggedAccountID = nil
        hoveredAccountID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if hoveredAccountID == destinationID { hoveredAccountID = nil }
    }
}

private struct SettingsActionButton: View {
    let title: String
    let icon: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Label(title, systemImage: icon)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .focusable(false)
            .disabled(isDisabled)
        } else {
            Button(action: action) {
                Label(title, systemImage: icon)
            }
            .focusable(false)
            .disabled(isDisabled)
        }
    }
}
