import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    let onOpenSettings: () -> Void
    @State private var localization = LocalizationManager.shared
    @State private var accountRowHeights: [UUID: CGFloat] = [:]
    @State private var draggedAccountID: UUID?
    @State private var hoveredAccountID: UUID?

    private let maximumVisibleAccounts = 4
    private let estimatedAccountRowHeight: CGFloat = 166

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("codex-account-manager")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(localization.text("settings"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 12)

            if model.isAddingAccount {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localization.text(model.loginMessageKey ?? "waiting_login")).font(.caption)
                    Spacer()
                    Button(localization.text("cancel"), role: .cancel) { model.cancelAddAccount() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            if model.isLoading {
                ProgressView(localization.text("loading")).frame(maxWidth: .infinity, minHeight: 130)
            } else if model.state.codexBinaryPath == nil {
                codexUnavailableContent
            } else if model.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(localization.text("no_accounts"))
                        .font(.headline.weight(.semibold))
                    emptyAccountActions
                }
                .frame(maxWidth: .infinity)
                .frame(height: estimatedAccountRowHeight)
            } else {
                if model.accounts.count <= maximumVisibleAccounts {
                    accountRows
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        accountRows
                    }
                    .frame(height: scrollViewportHeight)
                }
            }
        }
        .frame(width: 370)
        .background(WindowCornerConfigurator(radius: 24).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onPreferenceChange(AccountRowHeightPreferenceKey.self) { accountRowHeights = $0 }
        .onAppear { model.menuOpened() }
    }

    private var accountRows: some View {
        VStack(spacing: 0) {
            ForEach(model.accounts) { account in
                AccountRowView(
                    account: account,
                    isRefreshing: model.refreshingIDs.contains(account.id),
                    onBeginDrag: {
                        draggedAccountID = account.id
                        hoveredAccountID = nil
                        return NSItemProvider(object: account.id.uuidString as NSString)
                    },
                    model: model
                )
                .onDrop(
                    of: [UTType.plainText],
                    delegate: AccountOrderDropDelegate(
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
                            .padding(.horizontal, 14)
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: AccountRowHeightPreferenceKey.self,
                            value: [account.id: geometry.size.height]
                        )
                    }
                }
                if account.id != model.accounts.last?.id {
                    Divider().padding(.horizontal, 14)
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: model.accounts.map(\.id))
    }

    private var scrollViewportHeight: CGFloat {
        let visibleAccounts = Array(model.accounts.prefix(maximumVisibleAccounts))
        let measuredHeights = visibleAccounts.compactMap { accountRowHeights[$0.id] }
        let rowsHeight = measuredHeights.count == visibleAccounts.count
            ? measuredHeights.reduce(0, +)
            : estimatedAccountRowHeight * CGFloat(maximumVisibleAccounts)
        let dividersHeight = CGFloat(max(0, visibleAccounts.count - 1))
        let minimumHeight = measuredHeights.first ?? estimatedAccountRowHeight
        return max(minimumHeight, rowsHeight + dividersHeight)
    }

    private func insertionIndicatorAlignment(for destinationID: UUID) -> Alignment {
        guard let draggedAccountID,
              let sourceIndex = model.accounts.firstIndex(where: { $0.id == draggedAccountID }),
              let destinationIndex = model.accounts.firstIndex(where: { $0.id == destinationID }) else {
            return .top
        }
        return sourceIndex < destinationIndex ? .bottom : .top
    }

    @ViewBuilder private var emptyAccountActions: some View {
        if #available(macOS 26.0, *) {
            emptyAccountButtons
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            .controlSize(.regular)
        } else {
            emptyAccountButtons
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            .controlSize(.regular)
        }
    }

    @ViewBuilder private var codexUnavailableContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text(localization.text("codex_cli_not_found"))
                .font(.headline.weight(.semibold))
            Text(localization.text("codex_cli_setup_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            chooseBinaryButton
        }
        .frame(maxWidth: .infinity)
        .frame(height: estimatedAccountRowHeight)
    }

    @ViewBuilder private var chooseBinaryButton: some View {
        if #available(macOS 26.0, *) {
            Button(localization.text("choose_binary")) { model.chooseBinary() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .focusable(false)
        } else {
            Button(localization.text("choose_binary")) { model.chooseBinary() }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .focusable(false)
        }
    }

    private var emptyAccountButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                addAccountButton
                importAccountButton
            }
            VStack(spacing: 6) {
                addAccountButton
                importAccountButton
            }
        }
        .frame(maxWidth: 338)
    }

    private var addAccountButton: some View {
        Button { model.addAccount() } label: {
            Label(localization.text("add_account"), systemImage: "plus")
        }
        .focusable(false)
        .disabled(model.state.codexBinaryPath == nil || model.isAddingAccount)
    }

    private var importAccountButton: some View {
        Button { model.importCurrentAccount() } label: {
            Label(localization.text("import_current"), systemImage: "square.and.arrow.down")
        }
        .focusable(false)
        .disabled(
            model.state.codexBinaryPath == nil
                || !model.canImportCurrentAccount
                || model.isImportingAccount
        )
    }

}

private struct AccountOrderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedAccountID: UUID?
    @Binding var hoveredAccountID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID,
              draggedAccountID != destinationID else { return }
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

private struct AccountRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
