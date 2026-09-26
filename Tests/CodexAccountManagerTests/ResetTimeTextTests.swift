import Foundation
import Testing
@testable import CodexAccountManager

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
}
