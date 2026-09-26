import Foundation

struct RemoteAccount: Sendable {
    let email: String?
    let plan: String?
    let accountType: String?
}

struct LoginSession: Sendable {
    let loginID: String
    let authURL: URL
}

struct RefreshedAccount: Sendable {
    let remote: RemoteAccount
    let usage: CodexUsageSnapshot?
}

struct CodexAccountService: Sendable {
    let binaryPath: String
    let appVersion: String

    func readIdentity(profile: URL?) async throws -> RemoteAccount {
        let client = CodexAppServerClient()
        try await client.start(binaryPath: binaryPath, codexHome: profile)
        do {
            try await client.initialize(version: appVersion)
            let result = try await client.request(
                method: "account/read", params: .object(["refreshToken": .bool(false)]), timeout: 15
            )
            let remote = try parseAccount(result)
            await client.stop()
            return remote
        } catch {
            await client.stop()
            throw error
        }
    }

    func read(profile: URL?) async throws -> RefreshedAccount {
        let client = CodexAppServerClient()
        try await client.start(binaryPath: binaryPath, codexHome: profile)
        do {
            try await client.initialize(version: appVersion)
            let accountResult = try await client.request(
                method: "account/read", params: .object(["refreshToken": .bool(false)]), timeout: 15
            )
            let remote = try parseAccount(accountResult)
            let rateResult = try? await client.request(method: "account/rateLimits/read", params: .object([:]), timeout: 20)
            var usage = rateResult.map(UsageParser.parse)
            if remote.plan == nil, usage?.sourcePlan == nil {
                usage?.sourcePlan = accountResult["planType"]?.string
            }
            await client.stop()
            return RefreshedAccount(remote: remote, usage: usage)
        } catch {
            await client.stop()
            throw error
        }
    }

    func startLogin(profile: URL) async throws -> (CodexAppServerClient, LoginSession) {
        let client = CodexAppServerClient()
        try await client.start(binaryPath: binaryPath, codexHome: profile)
        do {
            try await client.initialize(version: appVersion)
            let result = try await client.request(
                method: "account/login/start", params: .object(["type": .string("chatgpt")]), timeout: 15
            )
            guard let loginID = result["loginId"]?.string,
                  let value = result["authUrl"]?.string,
                  let url = URL(string: value) else {
                throw CodexAccountManagerError.message(L10n.text("login_url_missing"))
            }
            return (client, LoginSession(loginID: loginID, authURL: url))
        } catch {
            await client.stop()
            throw error
        }
    }

    func finishLogin(client: CodexAppServerClient, loginID: String) async throws -> RefreshedAccount {
        let completion = try await client.waitForNotification(method: "account/login/completed", timeout: 600)
        if let completedID = completion["loginId"]?.string, completedID != loginID {
            throw CodexAccountManagerError.message(L10n.text("login_response_mismatch"))
        }
        if completion["success"]?.bool == false {
            throw CodexAccountManagerError.message(completion["error"]?.string ?? L10n.text("login_failed"))
        }
        let accountResult = try await client.request(
            method: "account/read", params: .object(["refreshToken": .bool(false)]), timeout: 15
        )
        let remote = try parseAccount(accountResult)
        let rateResult = try? await client.request(method: "account/rateLimits/read", params: .object([:]), timeout: 20)
        return RefreshedAccount(remote: remote, usage: rateResult.map(UsageParser.parse))
    }

    func cancelLogin(client: CodexAppServerClient, loginID: String) async {
        _ = try? await client.request(
            method: "account/login/cancel", params: .object(["loginId": .string(loginID)]), timeout: 5
        )
        await client.stop()
    }

    private func parseAccount(_ result: JSONValue) throws -> RemoteAccount {
        let account = result["account"] ?? result
        let type = account["type"]?.string ?? account["accountType"]?.string
        if let type, !["chatgpt", "chatGPT"].contains(type) {
            throw CodexAccountManagerError.message(L10n.text("chatgpt_only"))
        }
        return RemoteAccount(
            email: account["email"]?.string,
            plan: account["planType"]?.string ?? result["planType"]?.string,
            accountType: type
        )
    }
}
