import Foundation
import Testing
@testable import CodexAccountManager

struct PlanAndNumberingTests {
    @Test func mapsKnownAndFuturePlans() {
        let expected = [
            "free": "FREE", "go": "GO", "plus": "PLUS", "pro": "PRO", "prolite": "PRO LITE",
            "team": "TEAM", "self_serve_business_prolite": "BUSINESS",
            "self_serve_business_usage_based": "BUSINESS", "business": "BUSINESS",
            "ent26": "ENTERPRISE", "enterprise_cbp_automation": "ENTERPRISE",
            "enterprise_cbp_usage_based": "ENTERPRISE", "enterprise": "ENTERPRISE",
            "edu": "EDU", "edu_plus": "EDU PLUS", "edu_pro": "EDU PRO", "unknown": "UNKNOWN",
        ]
        for (raw, display) in expected { #expect(CodexAccount.displayPlan(raw) == display) }
        #expect(CodexAccount.displayPlan("super_new_plan_2027") == "SUPER NEW PLAN 2027")
    }

    @Test func accountNumbersAreNeverReused() {
        var state = AppState()
        #expect(AccountNumbering.takeNext(from: &state) == "Account 1")
        #expect(AccountNumbering.takeNext(from: &state) == "Account 2")
        #expect(AccountNumbering.takeNext(from: &state) == "Account 3")
    }

    @Test func duplicateEmailsKeepActiveAccount() {
        let inactive = account(email: " User@Example.com ", active: false)
        let active = account(email: "user@example.com", active: true)
        let other = account(email: "other@example.com", active: false)
        let result = AccountDeduplicator.split([inactive, other, active])
        #expect(result.unique.map(\.id) == [other.id, active.id])
        #expect(result.duplicates.map(\.id) == [inactive.id])
    }

    private func account(email: String?, active: Bool) -> CodexAccount {
        let id = UUID()
        return CodexAccount(id: id, displayName: "", email: email, rawPlan: nil,
                            profileDirectoryName: id.uuidString, isActive: active, usage: nil,
                            lastRefreshAt: nil, lastSuccessfulRefreshAt: nil, lastError: nil)
    }
}
