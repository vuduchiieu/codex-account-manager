import Foundation

struct CopilotBinaryInfo: Sendable {
    let path: String
    let version: String
}

struct CopilotBinaryResolver: Sendable {
    func resolve(savedPath: String?) async -> CopilotBinaryInfo? {
        var candidates: [String] = []
        if let savedPath { candidates.append(savedPath) }
        if let shellPath = await loginShellPath() { candidates.append(shellPath) }
        candidates += [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/copilot").path,
            "/opt/homebrew/bin/copilot",
            "/usr/local/bin/copilot",
        ]

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted
            && FileManager.default.isExecutableFile(atPath: path) {
            if let version = await verify(path: path) {
                return CopilotBinaryInfo(path: path, version: version)
            }
        }
        return nil
    }

    func verify(path: String) async -> String? {
        if let version = await run(executable: path, arguments: ["version"], timeout: 8) {
            return version
        }
        return await run(executable: path, arguments: ["--version"], timeout: 8)
    }

    private func loginShellPath() async -> String? {
        guard let result = await run(
            executable: "/bin/zsh",
            arguments: ["-lc", "command -v copilot"],
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
                process.standardError = output
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
