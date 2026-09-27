import Foundation
import Testing
@testable import LLMAccountSwitcher

struct CursorBinaryResolverTests {
    @Test func acceptsOfficialCursorAgentBinaryName() async throws {
        let binary = try makeExecutable(
            named: "cursor-agent",
            version: "Cursor Agent 1.0",
            help: "Usage"
        )
        defer { try? FileManager.default.removeItem(at: binary.deletingLastPathComponent()) }

        #expect(await CursorBinaryResolver().verify(path: binary.path) == "Cursor Agent 1.0")
    }

    @Test func acceptsLegacyAgentOnlyWhenItIdentifiesAsCursor() async throws {
        let binary = try makeExecutable(
            named: "agent",
            version: "1.0",
            help: "Cursor Agent CLI"
        )
        defer { try? FileManager.default.removeItem(at: binary.deletingLastPathComponent()) }

        #expect(await CursorBinaryResolver().verify(path: binary.path) == "1.0")
    }

    @Test func rejectsUnrelatedGenericAgentBinary() async throws {
        let binary = try makeExecutable(
            named: "agent",
            version: "1.0",
            help: "A different coding agent"
        )
        defer { try? FileManager.default.removeItem(at: binary.deletingLastPathComponent()) }

        #expect(await CursorBinaryResolver().verify(path: binary.path) == nil)
    }

    private func makeExecutable(named name: String, version: String, help: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent(name)
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '%s\\n' '\(version)'
        else
          printf '%s\\n' '\(help)'
        fi
        """
        try Data(script.utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        return binary
    }
}
