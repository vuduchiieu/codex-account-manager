import Foundation
import Testing
@testable import LLMAccountSwitcher

struct QuotaResetDetectorTests {
    @Test func detectsFiveHourAndWeeklyResets() {
        let now = Date(timeIntervalSince1970: 10_000)
        let previous = snapshot(fiveHourReset: now.addingTimeInterval(-10), weeklyReset: now)
        let current = snapshot(
            fiveHourReset: now.addingTimeInterval(18_000),
            weeklyReset: now.addingTimeInterval(604_800)
        )

        #expect(QuotaResetDetector.resets(previous: previous, current: current, now: now) == [.fiveHour, .weekly])
    }

    @Test func ignoresFirstSnapshotAndUnchangedCycle() {
        let now = Date(timeIntervalSince1970: 10_000)
        let current = snapshot(fiveHourReset: now.addingTimeInterval(18_000), weeklyReset: nil)

        #expect(QuotaResetDetector.resets(previous: nil, current: current, now: now).isEmpty)
        #expect(QuotaResetDetector.resets(previous: current, current: current, now: now).isEmpty)
    }

    @Test func waitsUntilPreviousDeadlinePasses() {
        let now = Date(timeIntervalSince1970: 10_000)
        let previous = snapshot(fiveHourReset: now.addingTimeInterval(60), weeklyReset: nil)
        let current = snapshot(fiveHourReset: now.addingTimeInterval(18_000), weeklyReset: nil)

        #expect(QuotaResetDetector.resets(previous: previous, current: current, now: now).isEmpty)
    }

    private func snapshot(fiveHourReset: Date?, weeklyReset: Date?) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            fiveHour: UsageWindow(usedPercent: 0, windowDurationMinutes: 300, resetsAt: fiveHourReset),
            weekly: UsageWindow(usedPercent: 0, windowDurationMinutes: 10_080, resetsAt: weeklyReset)
        )
    }
}
