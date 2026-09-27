import Foundation

struct AntigravityBinaryInfo: Sendable {
    let path: String
    let version: String
}

struct AntigravityBinaryResolver: Sendable {
    func resolve(savedPath: String?) async -> AntigravityBinaryInfo? {
        var candidates: [String] = []
        if let savedPath { candidates.append(savedPath) }
        if let shellPath = await loginShellPath() { candidates.append(shellPath) }
        candidates += [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path,
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted
            && FileManager.default.isExecutableFile(atPath: path) {
            if let version = await verify(path: path) {
                return AntigravityBinaryInfo(path: path, version: version)
            }
        }
        return nil
    }

    func verify(path: String) async -> String? {
        await run(executable: path, arguments: ["--version"], timeout: 8)
    }

    private func loginShellPath() async -> String? {
        guard let result = await run(
            executable: "/bin/zsh",
            arguments: ["-lc", "command -v agy"],
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
