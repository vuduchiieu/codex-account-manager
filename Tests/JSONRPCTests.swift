import Foundation
import Testing
@testable import LLMAccountSwitcher

struct JSONRPCTests {
    @Test func routesInterleavedResponsesByID() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "mock-app-server", withExtension: "sh", subdirectory: "Fixtures"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.path)
        let client = CodexAppServerClient()
        try await client.start(binaryPath: fixture.path, codexHome: nil)
        try await client.initialize(version: "test")
        async let a = client.request(method: "requestA", params: nil, timeout: 3)
        try await Task.sleep(for: .milliseconds(20))
        async let b = client.request(method: "requestB", params: nil, timeout: 3)
        let values = try await (a, b)
        #expect(values.0["value"]?.string == "A")
        #expect(values.1["value"]?.string == "B")
        await client.stop()
    }
}
