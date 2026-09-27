import Foundation

struct UsageWindow: Codable, Equatable, Sendable {
    var usedPercent: Double
    var windowDurationMinutes: Int?
    var resetsAt: Date?
    var limitID: String? = nil
    var limitName: String? = nil
    var normalModelSlug: String? = nil

    var remainingPercent: Double { min(100, max(0, 100 - usedPercent)) }

    @discardableResult
    mutating func advanceAfterResetIfNeeded(now: Date = Date()) -> Bool {
        guard let resetAt = resetsAt, resetAt <= now else { return false }

        usedPercent = 0
        guard let windowDurationMinutes, windowDurationMinutes > 0 else {
            resetsAt = nil
            return true
        }

        let duration = TimeInterval(windowDurationMinutes * 60)
        let elapsedCycles = max(1, Int((now.timeIntervalSince(resetAt) / duration).rounded(.down)) + 1)
        resetsAt = resetAt.addingTimeInterval(duration * Double(elapsedCycles))
        return true
    }
}

struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?
    var additionalWindows: [UsageWindow] = []
    var creditsBalance: String?
    var hasCredits: Bool?
    var unlimitedCredits: Bool?
    var sourcePlan: String?

    @discardableResult
    mutating func advanceExpiredWindows(now: Date = Date()) -> Bool {
        var changed = false
        if var fiveHour {
            changed = fiveHour.advanceAfterResetIfNeeded(now: now) || changed
            self.fiveHour = fiveHour
        }
        if var weekly {
            changed = weekly.advanceAfterResetIfNeeded(now: now) || changed
            self.weekly = weekly
        }
        for index in additionalWindows.indices {
            changed = additionalWindows[index].advanceAfterResetIfNeeded(now: now) || changed
        }
        return changed
    }
}

struct AccountRefreshError: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case loginRequired, usageUnavailable, workspaceDiscoveryTimedOut, codexUnavailable, unsupportedAccount, other
    }
    var kind: Kind
    var message: String
}

struct CodexAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var email: String?
    var rawPlan: String?
    var profileDirectoryName: String
    var isActive: Bool
    var usage: CodexUsageSnapshot?
    var lastRefreshAt: Date?
    var lastSuccessfulRefreshAt: Date?
    var lastError: AccountRefreshError?

    var planDisplayName: String {
        Self.displayPlan(rawPlan)
    }

    static func displayPlan(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "UNKNOWN" }
        let known: [String: String] = [
            "free": "FREE", "go": "GO", "plus": "PLUS", "pro": "PRO",
            "prolite": "PRO LITE", "team": "TEAM",
            "self_serve_business_prolite": "BUSINESS",
            "self_serve_business_usage_based": "BUSINESS", "business": "BUSINESS",
            "ent26": "ENTERPRISE", "enterprise_cbp_automation": "ENTERPRISE",
            "enterprise_cbp_usage_based": "ENTERPRISE", "enterprise": "ENTERPRISE",
            "edu": "EDU", "edu_plus": "EDU PLUS", "edu_pro": "EDU PRO",
            "unknown": "UNKNOWN",
        ]
        return known[raw.lowercased()] ?? raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

struct ClaudeAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var email: String?
    var rawPlan: String?
    var authMethod: String?
    var profileDirectoryName: String
    var usesDefaultProfile: Bool
    var isActive: Bool
    var lastRefreshAt: Date?

    var planDisplayName: String {
        guard let rawPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPlan.isEmpty else {
            return "CLAUDE"
        }
        return rawPlan.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

struct CursorAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var email: String?
    var rawPlan: String?
    var profileDirectoryName: String
    var usesDefaultProfile: Bool
    var usesFileCredentialStore: Bool
    var isActive: Bool
    var lastRefreshAt: Date?

    var planDisplayName: String {
        guard let rawPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPlan.isEmpty else {
            return "CURSOR"
        }
        return rawPlan.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

struct AntigravityAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var email: String?
    var rawPlan: String?
    var credentialKey: String
    var credentialFingerprint: String
    var isActive: Bool
    var lastRefreshAt: Date?

    var planDisplayName: String {
        guard let rawPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPlan.isEmpty else {
            return "ANTIGRAVITY"
        }
        return rawPlan.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

struct CopilotAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var login: String
    var host: String
    var isActive: Bool
    var lastRefreshAt: Date?

    var planDisplayName: String { "GITHUB COPILOT" }
}

struct AppState: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var activeAccountId: UUID?
    var nextAccountNumber = 1
    var codexBinaryPath: String?
    var launchAtLogin = false
    var launchAtLoginConfigured: Bool?
    var quotaResetNotificationsEnabled: Bool?
    var languageOverride: AppLanguage?
    var defaultAuthModificationDate: Date?
    var activeClaudeAccountId: UUID?
    var claudeBinaryPath: String?
    var activeCursorAccountId: UUID?
    var cursorBinaryPath: String?
    var activeAntigravityAccountId: UUID?
    var antigravityBinaryPath: String?
    var activeCopilotAccountId: UUID?
    var copilotBinaryPath: String?
    var onboardingCompleted: Bool?
}

enum LLMAccountSwitcherError: LocalizedError, Equatable {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): value }
    }
}

enum AccountNumbering {
    static func takeNext(from state: inout AppState) -> String {
        let name = "Account \(state.nextAccountNumber)"
        state.nextAccountNumber += 1
        return name
    }
}

enum AccountDeduplicator {
    static func normalizedEmail(_ email: String?) -> String? {
        guard let value = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        return value
    }

    static func split(_ accounts: [CodexAccount]) -> (unique: [CodexAccount], duplicates: [CodexAccount]) {
        var selectedIDs = Set<UUID>()
        var groups: [String: [CodexAccount]] = [:]

        for account in accounts {
            guard let email = normalizedEmail(account.email) else {
                selectedIDs.insert(account.id)
                continue
            }
            groups[email, default: []].append(account)
        }

        for group in groups.values {
            if let active = group.first(where: \.isActive) {
                selectedIDs.insert(active.id)
            } else if let first = group.first {
                selectedIDs.insert(first.id)
            }
        }

        return (
            accounts.filter { selectedIDs.contains($0.id) },
            accounts.filter { !selectedIDs.contains($0.id) }
        )
    }
}
