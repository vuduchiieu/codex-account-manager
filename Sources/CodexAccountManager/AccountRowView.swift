import SwiftUI

struct AccountRowView: View {
    let account: CodexAccount
    let isRefreshing: Bool
    let onBeginDrag: () -> NSItemProvider
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    model.setActive(account.id)
                } label: {
                    Group {
                        if isSwitching {
                            ProgressView()
                                .controlSize(.mini)
                        } else if account.isActive {
                            ZStack {
                                Circle().fill(activeGreen)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 15, height: 15)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .allowsHitTesting(model.switchingAccountID == nil && !account.isActive && !isProcessing)
                .accessibilityLabel(localization.text(account.isActive ? "active" : "switch_account"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? localization.text("unknown_email"))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(account.planDisplayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                if isProcessing && !isSwitching {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(localization.text("refreshing"))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                } else if let date = account.lastSuccessfulRefreshAt {
                    Text(updateStatusText(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            quotaContent

            if let creditsText {
                HStack(spacing: 10) {
                    Text(localization.text("credits"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .leading)
                    Text(creditsText)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
                .accessibilityLabel(localization.format("credits_accessibility", creditsText))
            }

            if !isProcessing, let error = account.lastError {
                Text(localizedError(error))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onDrag(onBeginDrag) {
            AccountDragPreview(account: account, activeGreen: activeGreen)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(account.email ?? localization.text("unknown_email")), \(account.planDisplayName)")
    }

    private var isProcessing: Bool {
        isRefreshing || model.processingIDs.contains(account.id)
    }

    private var isSwitching: Bool {
        model.switchingAccountID == account.id
    }

    @ViewBuilder private var quotaContent: some View {
        if account.rawPlan?.lowercased() == "free" {
            let windows = freeUsageWindows
            if windows.isEmpty {
                quotaRow(label: localization.text("quota"), window: nil)
            } else {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    quotaRow(label: label(for: window), window: window)
                }
            }
        } else {
            quotaRow(label: "5h", window: account.usage?.fiveHour)
            quotaRow(label: localization.text("week"), window: account.usage?.weekly)
            ForEach(Array((account.usage?.additionalWindows ?? []).enumerated()), id: \.offset) { _, window in
                quotaRow(label: label(for: window), window: window)
            }
        }
    }

    private var freeUsageWindows: [UsageWindow] {
        guard let usage = account.usage else { return [] }
        return ([usage.fiveHour, usage.weekly].compactMap { $0 } + usage.additionalWindows)
            .sorted { ($0.windowDurationMinutes ?? .max) < ($1.windowDurationMinutes ?? .max) }
    }

    private var creditsText: String? {
        guard let usage = account.usage else { return nil }
        if usage.unlimitedCredits == true { return localization.text("unlimited") }
        guard usage.hasCredits == true, let balance = usage.creditsBalance else { return nil }
        guard let decimal = Decimal(string: balance) else { return balance }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: decimal as NSDecimalNumber) ?? balance
    }

    private func label(for window: UsageWindow) -> String {
        let durationLabel: String
        guard let minutes = window.windowDurationMinutes else { return bucketLabel(for: window) ?? localization.text("quota") }
        switch minutes {
        case 300: durationLabel = "5h"
        case 1_440: durationLabel = localization.text("day")
        case 10_080: durationLabel = localization.text("week")
        case 43_200: durationLabel = localization.text("month")
        default:
            if minutes.isMultiple(of: 1_440) {
                durationLabel = localization.format("days", minutes / 1_440)
            } else if minutes.isMultiple(of: 60) {
                durationLabel = "\(minutes / 60)h"
            } else {
                durationLabel = "\(minutes)m"
            }
        }
        return bucketLabel(for: window).map { "\($0) \(durationLabel)" } ?? durationLabel
    }

    private func bucketLabel(for window: UsageWindow) -> String? {
        guard let limitID = window.limitID?.lowercased(), limitID != "codex" else { return nil }
        if let name = window.limitName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if window.normalModelSlug?.localizedCaseInsensitiveContains("spark") == true {
            return "Spark"
        }
        return limitID
            .replacingOccurrences(of: "codex_", with: "")
            .replacingOccurrences(of: "codex-", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func quotaRow(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 38, alignment: .leading)
            if let window {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        quotaProgress(value: window.remainingPercent)
                        Text(localization.format("remaining", Int(window.remainingPercent.rounded())))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(width: 78, alignment: .trailing)
                    }
                    Text(resetText(window.resetsAt)).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("—")
                    Text(localization.text("no_quota")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(localization.format(
            "quota_accessibility",
            label,
            window.map { localization.format("remaining", Int($0.remainingPercent.rounded())) }
                ?? localization.text("no_quota")
        ))
    }

    private func quotaProgress(value: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color(for: value))
                    .frame(width: geometry.size.width * value / 100)
            }
        }
        .frame(height: 6)
    }

    private func color(for value: Double) -> Color {
        if value < 10 { return .red }
        if value <= 30 { return .orange }
        return healthyGreen
    }

    private var activeGreen: Color {
        .accentColor
    }

    private var healthyGreen: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.86, blue: 0.43)
            : Color(red: 0.00, green: 0.48, blue: 0.20)
    }

    private func resetText(_ date: Date?) -> String {
        ResetTimeText.format(resetAt: date, language: localization.language)
    }

    private func relativeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func updateStatusText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 10 {
            return localization.text("just_updated")
        }
        return relativeText(date)
    }

    private func localizedError(_ error: AccountRefreshError) -> String {
        switch error.kind {
        case .usageUnavailable: localization.text("usage_unavailable")
        case .workspaceDiscoveryTimedOut: localization.text("workspace_discovery_timed_out")
        case .other where error.message.lowercased().contains("workspace routing discovery timed out"):
            localization.text("workspace_discovery_timed_out")
        default: error.message
        }
    }
}

struct AccountDragPreview: View {
    let account: CodexAccount
    let activeGreen: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(account.isActive ? activeGreen : .secondary)
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email ?? L10n.text("unknown_email"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.planDisplayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .primary.opacity(0.18), radius: 8, y: 4)
    }
}
