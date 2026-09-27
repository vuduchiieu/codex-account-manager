import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    let onOpenSettings: () -> Void
    let onOpenAccountSettings: () -> Void
    @State private var localization = LocalizationManager.shared
    @State private var accountRowHeights: [UUID: CGFloat] = [:]
    @State private var draggedAccountID: UUID?
    @State private var hoveredAccountID: UUID?
    @State private var selectedProvider: LLMProvider = .codex
    @State private var providerOrder = LLMProviderOrderStore.shared

    private let maximumVisibleAccounts = 4
    private let estimatedAccountRowHeight: CGFloat = 166

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LLM Account Switcher")
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

            if visibleProviders.count > 1 {
                LLMProviderPicker(
                    selection: $selectedProvider,
                    providers: visibleProviders,
                    accountCounts: providerAccountCounts
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Divider()
                    .padding(.horizontal, 12)
            }

            if selectedProvider == .codex, model.isAddingAccount {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localization.text(model.loginMessageKey ?? "waiting_login")).font(.caption)
                    Spacer()
                    Button(localization.text("cancel"), role: .cancel) { model.cancelAddAccount() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if selectedProvider == .claude, model.isAddingClaudeAccount {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localization.text("waiting_claude_login")).font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if selectedProvider == .cursor, model.isAddingCursorAccount {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localization.text("waiting_cursor_login")).font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if selectedProvider == .antigravity, model.isAddingAntigravityAccount {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localization.text("waiting_antigravity_login")).font(.caption)
                    Spacer()
                    Button(localization.text("cancel"), role: .cancel) {
                        model.cancelAddAntigravityAccount()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if selectedProvider == .copilot, model.isAddingCopilotAccount {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(localization.text("waiting_copilot_login")).font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            providerContent
                .frame(height: stableProviderContentHeight, alignment: .top)
                .clipped()
        }
        .frame(width: 390)
        .background(WindowCornerConfigurator(radius: 24).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onPreferenceChange(AccountRowHeightPreferenceKey.self) { accountRowHeights = $0 }
        .onAppear {
            selectFirstEnabledProviderIfNeeded()
            model.menuOpened()
        }
        .onChange(of: providerOrder.enabledProviders) {
            selectFirstEnabledProviderIfNeeded()
        }
    }

    @ViewBuilder private var providerContent: some View {
        if !providerOrder.isEnabled(selectedProvider) {
            providerDisabledContent
        } else if selectedProvider == .codex {
            codexProviderContent
        } else if selectedProvider == .claude {
            claudeProviderContent
        } else if selectedProvider == .cursor {
            cursorProviderContent
        } else if selectedProvider == .antigravity {
            antigravityProviderContent
        } else {
            copilotProviderContent
        }
    }

    @ViewBuilder private var copilotProviderContent: some View {
        if model.isLoading {
            ProgressView(localization.text("loading")).frame(maxWidth: .infinity, minHeight: 130)
        } else if model.state.copilotBinaryPath == nil {
            VStack(spacing: 12) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("copilot_cli_not_found"))
                    .font(.headline.weight(.semibold))
                Text(localization.text("copilot_cli_setup_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else if model.copilotAccounts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("no_accounts"))
                    .font(.headline.weight(.semibold))
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.copilotAccounts.enumerated()), id: \.element.id) { index, account in
                        CopilotProviderAccountRow(account: account, model: model)
                        if index < model.copilotAccounts.count - 1 {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.copilotAccounts.count) * 69, 276))
        }
    }

    @ViewBuilder private var antigravityProviderContent: some View {
        if model.isLoading {
            ProgressView(localization.text("loading")).frame(maxWidth: .infinity, minHeight: 130)
        } else if model.state.antigravityBinaryPath == nil {
            VStack(spacing: 12) {
                Image(systemName: "diamond")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("antigravity_cli_not_found"))
                    .font(.headline.weight(.semibold))
                Text(localization.text("antigravity_cli_setup_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else if model.antigravityAccounts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("no_accounts"))
                    .font(.headline.weight(.semibold))
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.antigravityAccounts.enumerated()), id: \.element.id) { index, account in
                        AntigravityProviderAccountRow(account: account, model: model)
                        if index < model.antigravityAccounts.count - 1 {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.antigravityAccounts.count) * 69, 276))
        }
    }

    @ViewBuilder private var cursorProviderContent: some View {
        if model.isLoading {
            ProgressView(localization.text("loading")).frame(maxWidth: .infinity, minHeight: 130)
        } else if model.state.cursorBinaryPath == nil {
            VStack(spacing: 12) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("cursor_cli_not_found"))
                    .font(.headline.weight(.semibold))
                Text(localization.text("cursor_cli_setup_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else if model.cursorAccounts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("no_accounts"))
                    .font(.headline.weight(.semibold))
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.cursorAccounts.enumerated()), id: \.element.id) { index, account in
                        CursorProviderAccountRow(account: account, model: model)
                        if index < model.cursorAccounts.count - 1 {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.cursorAccounts.count) * 69, 276))
        }
    }

    private var providerDisabledContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "power")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(localization.format("provider_disabled", selectedProvider.name))
                .font(.headline.weight(.semibold))
            Text(localization.text("provider_disabled_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 285)
            Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .focusable(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: estimatedAccountRowHeight)
    }

    @ViewBuilder private var claudeProviderContent: some View {
        if model.isLoading {
            ProgressView(localization.text("loading")).frame(maxWidth: .infinity, minHeight: 130)
        } else if model.state.claudeBinaryPath == nil {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("claude_cli_not_found"))
                    .font(.headline.weight(.semibold))
                Text(localization.text("claude_cli_setup_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else if model.claudeAccounts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(localization.text("no_accounts"))
                    .font(.headline.weight(.semibold))
                Button(localization.text("open_account_settings"), action: onOpenAccountSettings)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: estimatedAccountRowHeight)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.claudeAccounts.enumerated()), id: \.element.id) { index, account in
                        ClaudeProviderAccountRow(account: account, model: model)
                        if index < model.claudeAccounts.count - 1 {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(model.claudeAccounts.count) * 69, 276))
        }
    }

    @ViewBuilder private var codexProviderContent: some View {
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
        } else if model.accounts.count <= maximumVisibleAccounts {
            accountRows
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                accountRows
            }
            .frame(height: scrollViewportHeight)
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

    private var visibleProviders: [LLMProvider] {
        providerOrder.providers.filter(providerOrder.isEnabled)
    }

    private var stableProviderContentHeight: CGFloat {
        visibleProviders.map(providerContentHeight).max() ?? estimatedAccountRowHeight
    }

    private func providerContentHeight(_ provider: LLMProvider) -> CGFloat {
        switch provider {
        case .codex:
            guard !model.isLoading,
                  model.state.codexBinaryPath != nil,
                  !model.accounts.isEmpty else { return estimatedAccountRowHeight }
            let visibleAccounts = Array(model.accounts.prefix(maximumVisibleAccounts))
            let rowHeights = visibleAccounts.map(estimatedHeight)
            return rowHeights.reduce(0, +) + CGFloat(max(0, visibleAccounts.count - 1))
        case .claude:
            guard !model.isLoading,
                  model.state.claudeBinaryPath != nil,
                  !model.claudeAccounts.isEmpty else { return estimatedAccountRowHeight }
            return min(CGFloat(model.claudeAccounts.count) * 69, 276)
        case .cursor:
            guard !model.isLoading,
                  model.state.cursorBinaryPath != nil,
                  !model.cursorAccounts.isEmpty else { return estimatedAccountRowHeight }
            return min(CGFloat(model.cursorAccounts.count) * 69, 276)
        case .antigravity:
            guard !model.isLoading,
                  model.state.antigravityBinaryPath != nil,
                  !model.antigravityAccounts.isEmpty else { return estimatedAccountRowHeight }
            return min(CGFloat(model.antigravityAccounts.count) * 69, 276)
        case .copilot:
            guard !model.isLoading,
                  model.state.copilotBinaryPath != nil,
                  !model.copilotAccounts.isEmpty else { return estimatedAccountRowHeight }
            return min(CGFloat(model.copilotAccounts.count) * 69, 276)
        }
    }

    private func estimatedHeight(for account: CodexAccount) -> CGFloat {
        let usageWindows: Int
        if account.rawPlan?.lowercased() == "free" {
            let usage = account.usage
            usageWindows = max(
                1,
                [usage?.fiveHour, usage?.weekly].compactMap { $0 }.count
                    + (usage?.additionalWindows.count ?? 0)
            )
        } else {
            usageWindows = 2 + (account.usage?.additionalWindows.count ?? 0)
        }
        let hasCredits = account.usage?.unlimitedCredits == true
            || (account.usage?.hasCredits == true && account.usage?.creditsBalance != nil)
        return 82
            + CGFloat(usageWindows * 33)
            + (hasCredits ? 22 : 0)
            + (account.lastError == nil ? 0 : 22)
    }

    private func selectFirstEnabledProviderIfNeeded() {
        guard !providerOrder.isEnabled(selectedProvider),
              let provider = providerOrder.providers.first(where: providerOrder.isEnabled) else { return }
        selectedProvider = provider
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
        Button(action: onOpenAccountSettings) {
            Label(localization.text("add_account"), systemImage: "plus")
        }
        .focusable(false)
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
