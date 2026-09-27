import Foundation

struct CursorBinaryInfo: Sendable {
    let path: String
    let version: String
}

struct CursorBinaryResolver: Sendable {
    func resolve(savedPath: String?) async -> CursorBinaryInfo? {
        var candidates: [String] = []
        if let savedPath { candidates.append(savedPath) }
        if let shellPath = await loginShellPath(command: "cursor-agent") { candidates.append(shellPath) }
        if let shellPath = await loginShellPath(command: "agent") { candidates.append(shellPath) }
        candidates += [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/cursor-agent").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agent").path,
            "/opt/homebrew/bin/cursor-agent",
            "/opt/homebrew/bin/agent",
            "/usr/local/bin/cursor-agent",
            "/usr/local/bin/agent",
        ]

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted
            && FileManager.default.isExecutableFile(atPath: candidate) {
            if let version = await verify(path: candidate) {
                return CursorBinaryInfo(path: candidate, version: version)
            }
        }
        return nil
    }

    func verify(path: String) async -> String? {
        guard let version = await run(executable: path, arguments: ["--version"], timeout: 8) else {
            return nil
        }
        if URL(fileURLWithPath: path).lastPathComponent == "cursor-agent" {
            return version
        }
        guard let help = await run(executable: path, arguments: ["--help"], timeout: 8),
              help.localizedCaseInsensitiveContains("cursor") else {
            return nil
        }
        return version
    }

    private func loginShellPath(command: String) async -> String? {
        guard let result = await run(
            executable: "/bin/zsh",
            arguments: ["-lc", "command -v \(command)"],
            timeout: 8
        ) else { return nil }
        return result.split(separator: "\n").first.map(String.init)
    }

    private func run(executable: String, arguments: [String], timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = Pipe()
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                guard !process.isRunning else {
                    process.terminate()
                    continuation.resume(returning: nil)
                    return
                }
                guard process.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
    }
}
