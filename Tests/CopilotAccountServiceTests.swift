import Foundation
import Testing
@testable import LLMAccountSwitcher

struct CopilotAccountServiceTests {
    @Test func parsesCamelAndSnakeCaseAccountState() throws {
        let camel = Data(#"""
        {
          "loggedInUsers": [
            {"host":"https://github.com","login":"alpha"},
            {"host":"https://github.com","login":"beta"}
          ],
          "lastLoggedInUser": {"host":"https://github.com","login":"beta"}
        }
        """#.utf8)
        let camelState = try CopilotAccountService.parseConfig(camel)
        #expect(camelState.identities.map(\.login) == ["alpha", "beta"])
        #expect(camelState.activeIdentity?.login == "beta")

        let snake = Data(#"""
        {
          "logged_in_users": [{"host":"github.com","login":"royal"}],
          "last_logged_in_user": {"host":"github.com","login":"royal"}
        }
        """#.utf8)
        let snakeState = try CopilotAccountService.parseConfig(snake)
        #expect(snakeState.activeIdentity == CopilotIdentity(host: "github.com", login: "royal"))
    }

    @Test func activatesKnownAccountWithoutTouchingOtherConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try Data(#"""
        {
          "banner":"never",
          "loggedInUsers":[
            {"host":"https://github.com","login":"alpha"},
            {"host":"https://github.com","login":"beta"}
          ],
          "lastLoggedInUser":{"host":"https://github.com","login":"alpha"}
        }
        """#.utf8).write(to: config)
        let service = CopilotAccountService(binaryPath: "/usr/bin/false", configURL: config)

        let state = try service.activate(CopilotIdentity(host: "https://github.com", login: "beta"))

        #expect(state.activeIdentity?.login == "beta")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        #expect(object?["banner"] as? String == "never")
    }

    @Test func rejectsUnknownAccountAndKeepsConfigUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        let original = Data(#"""
        {
          "loggedInUsers":[{"host":"https://github.com","login":"alpha"}],
          "lastLoggedInUser":{"host":"https://github.com","login":"alpha"}
        }
        """#.utf8)
        try original.write(to: config)
        let service = CopilotAccountService(binaryPath: "/usr/bin/false", configURL: config)

        #expect(throws: (any Error).self) {
            try service.activate(CopilotIdentity(host: "https://github.com", login: "missing"))
        }
        #expect(try Data(contentsOf: config) == original)
    }
}
