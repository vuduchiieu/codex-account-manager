import Foundation

struct ClaudeEnvironmentService: Sendable {
    func activate(profile: URL) async {
        let profilePath = profile.path
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["setenv", "CLAUDE_CONFIG_DIR", profilePath]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    // The generated launcher remains the source of truth if launchctl is unavailable.
                }
                continuation.resume()
            }
        }
    }
}
