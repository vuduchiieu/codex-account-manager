import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    private let model: AppModel
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

        let hostingController = NSHostingController(rootView: SettingsWindowView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.text("settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
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

private struct SettingsWindowView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared
    @State private var selection: SettingsSection? = .accounts

    var body: some View {
        settingsNavigation
            .frame(minWidth: 680, minHeight: 460)
            .onAppear { model.menuOpened() }
    }

    private var settingsNavigation: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text(localization.text("settings"))
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            selection = section
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
                                    .fill(selection == section ? Color.primary.opacity(0.10) : .clear)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                Text("Codex Account Manager")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(16)
            }
            .padding(.top, 48)
            .background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                switch selection ?? .accounts {
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
            Text(localization.text("about"))
                .font(.largeTitle.weight(.bold))

            VStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                VStack(spacing: 5) {
                    Text("Codex Account Manager")
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
        .padding(.top, 48)
        .padding(.bottom, 24)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appIcon: NSImage {
        guard let url = Bundle.main.url(forResource: "codex-account-manager-icon", withExtension: "icns"),
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.text("manage_accounts"))
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)

                HStack(alignment: .center, spacing: 10) {
                    Text(localization.format("account_count", model.accounts.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsActionButton(
                        title: localization.text("import_current"),
                        icon: "square.and.arrow.down",
                        isDisabled: model.state.codexBinaryPath == nil || !model.canImportCurrentAccount || model.isImportingAccount,
                        action: model.importCurrentAccount
                    )
                    SettingsActionButton(
                        title: localization.text("add_account"),
                        icon: "plus",
                        isDisabled: model.state.codexBinaryPath == nil || model.isAddingAccount,
                        action: model.addAccount
                    )
                }
            }

            if model.state.codexBinaryPath == nil {
                ContentUnavailableView(
                    localization.text("codex_cli_not_found"),
                    systemImage: "terminal",
                    description: Text(localization.text("configure_cli_in_general"))
                )
            } else if model.accounts.isEmpty {
                ContentUnavailableView(
                    localization.text("no_accounts"),
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text(localization.text("no_accounts_description"))
                )
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
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(model.accounts.count) * 62, 372))
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 48)
        .padding(.bottom, 24)
    }

    private func insertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.accounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.accounts.firstIndex(where: { $0.id == destinationID }) else {
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

private struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(localization.text("general"))
                    .font(.largeTitle.weight(.bold))

                SettingsGroup(title: localization.text("codex_cli")) {
                    HStack(spacing: 14) {
                        SettingsRowIcon(systemName: "terminal")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localization.text("binary_path"))
                            Text(model.state.codexBinaryPath ?? localization.text("not_configured"))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        SettingsActionButton(
                            title: localization.text("choose_binary"),
                            icon: "folder",
                            isDisabled: false,
                            action: model.chooseBinary
                        )
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                }

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
            .padding(.top, 48)
            .padding(.bottom, 28)
        }
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
