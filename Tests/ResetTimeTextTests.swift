import Foundation
import Testing
@testable import LLMAccountSwitcher

struct ResetTimeTextTests {
    private let now = Date(timeIntervalSince1970: 0)
    private let utc = TimeZone(secondsFromGMT: 0)!

    @Test func formatsHoursAndMinutesBelowOneDay() {
        let reset = now.addingTimeInterval(6 * 3_600 + 20 * 60)
        #expect(ResetTimeText.format(resetAt: reset, now: now, language: .vietnamese, timeZone: utc) == "Đặt lại sau 6 giờ 20 phút")
    }

    @Test func formatsClockAndDaysBelowOneWeek() {
        let reset = now.addingTimeInterval(6 * 86_400 + 28 * 60)
        #expect(ResetTimeText.format(resetAt: reset, now: now, language: .vietnamese, timeZone: utc) == "Đặt lại sau 6 ngày 0 giờ")
    }

    @Test func formatsClockAndDateFromOneWeek() {
        let reset = now.addingTimeInterval(8 * 86_400 + 28 * 60)
        #expect(ResetTimeText.format(resetAt: reset, now: now, language: .vietnamese, timeZone: utc) == "Đặt lại lúc 00:28, 09/01/1970")
    }

    @Test func handlesMissingResetTime() {
        #expect(ResetTimeText.format(resetAt: nil, now: now, language: .vietnamese, timeZone: utc) == "Không có thời gian đặt lại")
    }

    @Test func formatsDayRangeInEverySupportedLanguage() {
        let reset = now.addingTimeInterval(6 * 86_400 + 28 * 60)
        #expect(ResetTimeText.format(resetAt: reset, now: now, language: .english, timeZone: utc) == "Resets in 6 days 0 hours")
        #expect(ResetTimeText.format(resetAt: reset, now: now, language: .japanese, timeZone: utc) == "6日0時間後にリセット")
        #expect(ResetTimeText.format(resetAt: reset, now: now, language: .chinese, timeZone: utc) == "6天0小时后重置")
    }

    @Test func advancesExpiredWindowsToTheNextCycle() {
        let reset = now.addingTimeInterval(-2 * 60)
        var usage = CodexUsageSnapshot(
            fiveHour: UsageWindow(usedPercent: 100, windowDurationMinutes: 300, resetsAt: reset),
            weekly: UsageWindow(usedPercent: 16, windowDurationMinutes: 10_080, resetsAt: reset)
        )

        let advanced = usage.advanceExpiredWindows(now: now)
        #expect(advanced)
        #expect(usage.fiveHour?.remainingPercent == 100)
        #expect(usage.weekly?.remainingPercent == 100)
        #expect(usage.fiveHour?.resetsAt == now.addingTimeInterval(4 * 60 * 60 + 58 * 60))
        #expect(usage.weekly?.resetsAt == now.addingTimeInterval(7 * 86_400 - 2 * 60))
    }
}
