import Observation
import SwiftUI
import UniformTypeIdentifiers

enum LLMProvider: String, CaseIterable, Identifiable, Hashable {
    case codex
    case claude
    case cursor
    case antigravity
    case copilot

    var id: Self { self }

    var name: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        case .copilot: "Copilot"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: "terminal"
        case .claude: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .antigravity: "diamond"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        }
    }

    var isAvailable: Bool { true }

    static func restore(storedValue: String) -> LLMProvider? {
        storedValue == "gemini" ? .antigravity : LLMProvider(rawValue: storedValue)
    }
}

@MainActor @Observable
final class LLMProviderOrderStore {
    static let shared = LLMProviderOrderStore()

    private static let defaultsKey = "llmProviderOrder"
    private static let enabledDefaultsKey = "enabledLLMProviders"
    var providers: [LLMProvider] {
        didSet {
            UserDefaults.standard.set(providers.map(\.rawValue), forKey: Self.defaultsKey)
        }
    }
    var enabledProviders: Set<LLMProvider> {
        didSet {
            UserDefaults.standard.set(enabledProviders.map(\.rawValue).sorted(), forKey: Self.enabledDefaultsKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        let restored = saved.compactMap(LLMProvider.restore(storedValue:))
        let missing = LLMProvider.allCases.filter { !restored.contains($0) }
        providers = restored + missing

        if let savedEnabled = UserDefaults.standard.stringArray(forKey: Self.enabledDefaultsKey) {
            enabledProviders = Set(savedEnabled.compactMap(LLMProvider.restore(storedValue:)))
        } else {
            enabledProviders = Set(LLMProvider.allCases)
        }
    }

    func move(_ source: LLMProvider, over destination: LLMProvider) {
        guard source != destination,
              let sourceIndex = providers.firstIndex(of: source),
              let destinationIndex = providers.firstIndex(of: destination) else { return }
        let provider = providers.remove(at: sourceIndex)
        providers.insert(provider, at: min(destinationIndex, providers.count))
    }

    func isEnabled(_ provider: LLMProvider) -> Bool {
        enabledProviders.contains(provider)
    }

    func setEnabled(_ enabled: Bool, for provider: LLMProvider) {
        if enabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
    }

    func enableOnly(_ provider: LLMProvider) {
        enabledProviders = [provider]
    }
}

struct MockProviderQuota: Identifiable {
    let id = UUID()
    let label: String
    let remainingPercent: Double
    let resetsAt: Date
}

struct MockProviderAccount: Identifiable {
    let id: UUID
    let provider: LLMProvider
    let email: String
    let plan: String
    let lastUpdatedAt: Date
    let quotas: [MockProviderQuota]
}

enum MockProviderFixtures {
    static let cursorPrimaryID = UUID(uuidString: "C0010000-0000-4000-8000-000000000001")!
    static let antigravityPrimaryID = UUID(uuidString: "6E100000-0000-4000-8000-000000000001")!

    static func accounts(for provider: LLMProvider, now: Date = Date()) -> [MockProviderAccount] {
        switch provider {
        case .codex:
            []
        case .claude:
            []
        case .cursor:
            []
        case .antigravity:
            [
                MockProviderAccount(
                    id: antigravityPrimaryID,
                    provider: .antigravity,
                    email: "personal@gmail.com",
                    plan: "ADVANCED",
                    lastUpdatedAt: now.addingTimeInterval(-7 * 60),
                    quotas: [
                        MockProviderQuota(label: L10n.text("day"), remainingPercent: 88, resetsAt: now.addingTimeInterval(14 * 3_600)),
                        MockProviderQuota(label: L10n.text("month"), remainingPercent: 61, resetsAt: now.addingTimeInterval(16 * 86_400))
                    ]
                )
            ]
        case .copilot:
            []
        }
    }

}

struct LLMProviderPicker: View {
    @Binding var selection: LLMProvider
    let providers: [LLMProvider]
    let accountCounts: [LLMProvider: Int]
    var showsAddProvider = false
    var onAddProvider: (() -> Void)?
    var allowsReordering = false
    var onMoveProvider: ((LLMProvider, LLMProvider) -> Void)?
    @State private var draggedProvider: LLMProvider?
    @State private var hoveredProvider: LLMProvider?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            providerStrip
                .fixedSize(horizontal: true, vertical: false)

            navigationPicker
        }
        .onAppear { ensureValidSelection() }
        .onChange(of: providers) { _, _ in ensureValidSelection() }
    }

    private var navigationPicker: some View {
        HStack(spacing: 6) {
            navigationButton(
                systemImage: "chevron.left",
                isDisabled: previousProvider == nil,
                accessibilityLabel: L10n.text("previous_provider")
            ) {
                if let previousProvider { selection = previousProvider }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    providerStrip
                }
                .onChange(of: selection) { _, provider in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(provider, anchor: .center)
                    }
                }
            }

            navigationButton(
                systemImage: "chevron.right",
                isDisabled: nextProvider == nil,
                accessibilityLabel: L10n.text("next_provider")
            ) {
                if let nextProvider { selection = nextProvider }
            }
        }
    }

    private var providerStrip: some View {
        HStack(spacing: 7) {
            ForEach(providers) { provider in
                providerItem(provider)
                    .id(provider)
            }

            if showsAddProvider {
                Button(action: { onAddProvider?() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(L10n.text("add_provider"))
            }
        }
    }

    private func ensureValidSelection() {
        guard !providers.contains(selection), let first = providers.first else { return }
        selection = first
    }

    private var selectedIndex: Int {
        providers.firstIndex(of: selection) ?? 0
    }

    private var previousProvider: LLMProvider? {
        guard selectedIndex > 0 else { return nil }
        return providers[selectedIndex - 1]
    }

    private var nextProvider: LLMProvider? {
        let nextIndex = selectedIndex + 1
        guard nextIndex < providers.count else { return nil }
        return providers[nextIndex]
    }

    @ViewBuilder private func providerItem(_ provider: LLMProvider) -> some View {
        if allowsReordering {
            providerButton(provider)
                .onDrag {
                    draggedProvider = provider
                    hoveredProvider = nil
                    return NSItemProvider(object: provider.rawValue as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: ProviderOrderDropDelegate(
                        destination: provider,
                        draggedProvider: $draggedProvider,
                        hoveredProvider: $hoveredProvider,
                        onMove: onMoveProvider
                    )
                )
                .overlay(alignment: dropIndicatorAlignment(for: provider)) {
                    if hoveredProvider == provider, draggedProvider != provider {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 22)
                            .offset(x: dropIndicatorOffset(for: provider))
                    }
                }
        } else {
            providerButton(provider)
        }
    }

    private func providerButton(_ provider: LLMProvider) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { selection = provider }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: provider.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(provider.name)
                    .font(.caption.weight(.semibold))
                Text("\(accountCounts[provider, default: 0])")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(selection == provider ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(selection == provider ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(selection == provider ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func dropIndicatorAlignment(for destination: LLMProvider) -> Alignment {
        guard let draggedProvider,
              let sourceIndex = providers.firstIndex(of: draggedProvider),
              let destinationIndex = providers.firstIndex(of: destination) else { return .leading }
        return sourceIndex < destinationIndex ? .trailing : .leading
    }

    private func dropIndicatorOffset(for destination: LLMProvider) -> CGFloat {
        dropIndicatorAlignment(for: destination) == .trailing ? 4 : -4
    }

    private func navigationButton(
        systemImage: String,
        isDisabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 25, height: 30)
                .background(Color.primary.opacity(isDisabled ? 0.025 : 0.055), in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ProviderOrderDropDelegate: DropDelegate {
    let destination: LLMProvider
    @Binding var draggedProvider: LLMProvider?
    @Binding var hoveredProvider: LLMProvider?
    let onMove: ((LLMProvider, LLMProvider) -> Void)?

    func dropEntered(info: DropInfo) {
        guard draggedProvider != destination else { return }
        hoveredProvider = destination
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let source = draggedProvider, source != destination else { return false }
        onMove?(source, destination)
        draggedProvider = nil
        hoveredProvider = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if hoveredProvider == destination { hoveredProvider = nil }
    }
}

struct MockProviderAccountRow: View {
    let account: MockProviderAccount
    let isActive: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button(action: onSelect) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .focusable(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(account.plan)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(relativeText(account.lastUpdatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            ForEach(account.quotas) { quota in
                quotaRow(quota)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func quotaRow(_ quota: MockProviderQuota) -> some View {
        HStack(spacing: 6) {
            Text(quota.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(progressColor(quota.remainingPercent))
                                .frame(width: geometry.size.width * quota.remainingPercent / 100)
                        }
                    }
                    .frame(height: 6)
                    Text(localization.format("remaining", Int(quota.remainingPercent.rounded())))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: 78, alignment: .trailing)
                }
                Text(ResetTimeText.format(resetAt: quota.resetsAt, language: localization.language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressColor(_ value: Double) -> Color {
        if value < 10 { return .red }
        if value <= 30 { return .orange }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.86, blue: 0.43)
            : Color(red: 0.00, green: 0.48, blue: 0.20)
    }

    private func relativeText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return localization.text("just_updated") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ClaudeProviderAccountRow: View {
    let account: ClaudeAccount
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.setActiveClaude(account.id)
            } label: {
                Group {
                    if model.switchingClaudeAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .allowsHitTesting(model.switchingClaudeAccountID == nil && !account.isActive)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email ?? account.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.refreshingClaudeIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else if let date = account.lastRefreshAt {
                Text(relativeText(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private func relativeText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return localization.text("just_updated") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CursorProviderAccountRow: View {
    let account: CursorAccount
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { model.setActiveCursor(account.id) } label: {
                Group {
                    if model.switchingCursorAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .allowsHitTesting(model.switchingCursorAccountID == nil && !account.isActive)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email ?? account.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.refreshingCursorIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else if let date = account.lastRefreshAt {
                Text(relativeText(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private func relativeText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return localization.text("just_updated") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct AntigravityProviderAccountRow: View {
    let account: AntigravityAccount
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { model.setActiveAntigravity(account.id) } label: {
                Group {
                    if model.switchingAntigravityAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .allowsHitTesting(model.switchingAntigravityAccountID == nil && !account.isActive)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email ?? account.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.refreshingAntigravityIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else if let date = account.lastRefreshAt {
                Text(relativeText(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private func relativeText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return localization.text("just_updated") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CopilotProviderAccountRow: View {
    let account: CopilotAccount
    @Bindable var model: AppModel
    @State private var localization = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { model.setActiveCopilot(account.id) } label: {
                Group {
                    if model.switchingCopilotAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.isActive ? Color.accentColor : .secondary)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .allowsHitTesting(model.switchingCopilotAccountID == nil && !account.isActive)
            .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.login)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.host.replacingOccurrences(of: "https://", with: ""))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.refreshingCopilotIDs.contains(account.id) {
                ProgressView().controlSize(.small)
            } else if let date = account.lastRefreshAt {
                Text(relativeText(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private func relativeText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return localization.text("just_updated") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct MockSettingsAccountRow: View {
    let account: MockProviderAccount
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .font(.title3)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .focusable(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.email)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.plan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(L10n.text("preview"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 14)
        .frame(height: 61)
        .contentShape(Rectangle())
    }
}
