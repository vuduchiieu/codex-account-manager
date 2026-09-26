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
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 540))
        window.minSize = NSSize(width: 640, height: 440)
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

    var id: Self { self }

    var icon: String {
        switch self {
        case .accounts: "person.2"
        case .general: "gearshape"
        }
    }

    @MainActor
    func title(_ localization: LocalizationManager) -> String {
        switch self {
        case .accounts: localization.text("accounts")
        case .general: localization.text("general")
        }
    }
}

private struct SettingsWindowView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared
    @State private var selection: SettingsSection? = .accounts

    var body: some View {
        settingsNavigation
            .frame(minWidth: 640, minHeight: 440)
            .navigationTitle(localization.text("settings"))
            .onAppear { model.menuOpened() }
    }

    private var settingsNavigation: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title(localization), systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch selection ?? .accounts {
            case .accounts:
                AccountManagementSettingsView(model: model)
            case .general:
                GeneralSettingsView(model: model)
            }
        }
    }
}

private struct AccountManagementSettingsView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared
    @State private var draggedAccountID: UUID?
    @State private var hoveredAccountID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("manage_accounts"))
                        .font(.title2.weight(.semibold))
                    Text(localization.format("account_count", model.accounts.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                List {
                    ForEach(model.accounts) { account in
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
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
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
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(account.isActive ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(account.isActive || isProcessing)
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
                }
                .focusable(false)
                .accessibilityLabel(localization.text("delete"))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            AccountDragPreview(account: account, activeGreen: .green)
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        Form {
            Section(localization.text("codex_cli")) {
                LabeledContent(localization.text("binary_path")) {
                    Text(model.state.codexBinaryPath ?? localization.text("not_configured"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(model.state.codexBinaryPath == nil ? .secondary : .primary)
                }
                SettingsActionButton(
                    title: localization.text("choose_binary"),
                    icon: "folder",
                    isDisabled: false,
                    action: model.chooseBinary
                )
            }

            Section(localization.text("app_preferences")) {
                Picker(
                    localization.text("language"),
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

                Toggle(
                    localization.text("launch_at_login"),
                    isOn: Binding(
                        get: { model.state.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .focusable(false)

                Toggle(
                    localization.text("quota_reset_notifications"),
                    isOn: Binding(
                        get: { model.quotaResetNotificationsEnabled },
                        set: { model.setQuotaResetNotificationsEnabled($0) }
                    )
                )
                .focusable(false)
            }
        }
        .formStyle(.grouped)
        .padding(24)
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
