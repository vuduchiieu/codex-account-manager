import Foundation

enum ResetTimeText {
    private static let day: TimeInterval = 86_400
    private static let week: TimeInterval = day * 7

    static func format(
        resetAt: Date?,
        now: Date = Date(),
        language: AppLanguage,
        timeZone: TimeZone = .current
    ) -> String {
        guard let resetAt else { return L10n.text("no_reset_time", language: language) }
        let interval = resetAt.timeIntervalSince(now)

        if interval > 0, interval < day {
            let totalMinutes = max(1, Int(interval / 60))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return hours > 0
                ? L10n.format("reset_after_hours", language: language, arguments: [hours, minutes])
                : L10n.format("reset_after_minutes", language: language, arguments: [minutes])
        }

        let clock = clockText(resetAt, language: language, timeZone: timeZone)
        if interval > 0, interval < week {
            let totalHours = Int(interval / 3_600)
            let days = max(1, totalHours / 24)
            let hours = totalHours % 24
            return L10n.format("reset_in_days", language: language, arguments: [days, hours])
        }

        let date = dateText(resetAt, language: language, timeZone: timeZone)
        return L10n.format("reset_on_date", language: language, arguments: [clock, date])
    }

    private static func clockText(_ date: Date, language: AppLanguage, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func dateText(_ date: Date, language: AppLanguage, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}
