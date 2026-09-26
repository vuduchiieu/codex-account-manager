import Foundation
import Testing
@testable import CodexAccountManager

struct UsageParserTests {
    private func window(_ used: Double, _ duration: Int) -> JSONValue {
        .object(["usedPercent": .number(used), "windowDurationMins": .number(Double(duration)), "resetsAt": .number(2_000_000_000)])
    }

    @Test func identifiesWindowsByDurationNotPosition() {
        let result: JSONValue = .object(["rateLimits": .object([
            "primary": window(59, 10_080), "secondary": window(28, 300), "planType": .string("plus")
        ])])
        let parsed = UsageParser.parse(result)
        #expect(parsed.fiveHour?.remainingPercent == 72)
        #expect(parsed.weekly?.remainingPercent == 41)
        #expect(parsed.sourcePlan == "plus")
    }

    @Test func handlesMissingAndUnknownWindows() {
        let weeklyOnly = UsageParser.parse(.object(["primary": window(5, 10_080)]))
        #expect(weeklyOnly.fiveHour == nil)
        #expect(weeklyOnly.weekly != nil)
        let unknown = UsageParser.parse(.object(["secondary": window(20, 60)]))
        #expect(unknown.additionalWindows.count == 1)
        let empty = UsageParser.parse(.object(["primary": .null, "secondary": .null]))
        #expect(empty.fiveHour == nil && empty.weekly == nil)
    }

    @Test func clampsRemainingPercentage() {
        #expect(UsageWindow(usedPercent: -10, windowDurationMinutes: 300, resetsAt: nil).remainingPercent == 100)
        #expect(UsageWindow(usedPercent: 0, windowDurationMinutes: 300, resetsAt: nil).remainingPercent == 100)
        #expect(UsageWindow(usedPercent: 100, windowDurationMinutes: 300, resetsAt: nil).remainingPercent == 0)
        #expect(UsageWindow(usedPercent: 120, windowDurationMinutes: 300, resetsAt: nil).remainingPercent == 0)
    }

    @Test func parsesFreeMonthlyQuotaAndCredits() {
        let result: JSONValue = .object([
            "rateLimits": .object([
                "planType": .string("free"),
                "primary": window(100, 43_200),
                "secondary": .null,
                "credits": .object([
                    "hasCredits": .bool(true),
                    "unlimited": .bool(false),
                    "balance": .string("296.5560130000"),
                ]),
            ]),
        ])
        let parsed = UsageParser.parse(result)
        #expect(parsed.fiveHour == nil)
        #expect(parsed.weekly == nil)
        #expect(parsed.additionalWindows.first?.windowDurationMinutes == 43_200)
        #expect(parsed.additionalWindows.first?.remainingPercent == 0)
        #expect(parsed.creditsBalance == "296.5560130000")
        #expect(parsed.hasCredits == true)
    }

    @Test func keepsSeparateProModelBucket() {
        let codex: JSONValue = .object([
            "limitId": .string("codex"),
            "planType": .string("pro"),
            "primary": window(20, 300),
            "secondary": window(30, 10_080),
        ])
        let spark: JSONValue = .object([
            "limitId": .string("codex_spark"),
            "limitName": .string("Spark"),
            "normalModelSlug": .string("gpt-5.3-codex-spark"),
            "primary": window(40, 300),
        ])
        let result: JSONValue = .object([
            "rateLimits": codex,
            "rateLimitsByLimitId": .object([
                "codex": codex,
                "codex_spark": spark,
            ]),
        ])

        let parsed = UsageParser.parse(result)
        #expect(parsed.sourcePlan == "pro")
        #expect(parsed.fiveHour?.remainingPercent == 80)
        #expect(parsed.weekly?.remainingPercent == 70)
        #expect(parsed.additionalWindows.count == 1)
        #expect(parsed.additionalWindows.first?.limitID == "codex_spark")
        #expect(parsed.additionalWindows.first?.normalModelSlug == "gpt-5.3-codex-spark")
        #expect(parsed.additionalWindows.first?.remainingPercent == 60)
    }
}
