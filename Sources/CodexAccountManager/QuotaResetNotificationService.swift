import Foundation
import UserNotifications

enum QuotaResetKind: String, Sendable {
    case fiveHour
    case weekly

    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .fiveHour: "5h"
        case .weekly: L10n.text("week", language: language)
        }
    }
}

enum QuotaResetDetector {
    static func resets(
        previous: CodexUsageSnapshot?,
        current: CodexUsageSnapshot?,
        now: Date = Date()
    ) -> [QuotaResetKind] {
        guard let previous, let current else { return [] }
        var result: [QuotaResetKind] = []
        if didReset(previous: previous.fiveHour, current: current.fiveHour, now: now) {
            result.append(.fiveHour)
        }
        if didReset(previous: previous.weekly, current: current.weekly, now: now) {
            result.append(.weekly)
        }
        return result
    }

    private static func didReset(previous: UsageWindow?, current: UsageWindow?, now: Date) -> Bool {
        guard let previousReset = previous?.resetsAt,
              let currentReset = current?.resetsAt,
              previousReset <= now else { return false }
        return currentReset.timeIntervalSince(previousReset) > 60
    }
}

final class QuotaResetNotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendTestNotification(accountName: String, language: AppLanguage) {
        let title = L10n.text("quota_reset_title", language: language)
        let body = L10n.format(
            "quota_reset_message",
            language: language,
            arguments: [accountName, QuotaResetKind.fiveHour.localizedName(language: language)]
        )
        Task { [self] in
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "quota-reset-preview-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    func notify(account: CodexAccount, kind: QuotaResetKind, resetDate: Date?, language: AppLanguage) {
        let accountName = account.email ?? account.displayName
        let limitName = kind.localizedName(language: language)
        let content = UNMutableNotificationContent()
        content.title = L10n.text("quota_reset_title", language: language)
        content.body = L10n.format(
            "quota_reset_message",
            language: language,
            arguments: [accountName, limitName]
        )
        content.sound = .default

        let resetToken = Int((resetDate ?? Date()).timeIntervalSince1970)
        let identifier = "quota-reset-\(account.id.uuidString)-\(kind.rawValue)-\(resetToken)"
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
