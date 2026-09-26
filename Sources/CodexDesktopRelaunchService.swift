import AppKit
import Foundation

@MainActor
struct CodexDesktopRelaunchService {
    private let bundleIdentifier = "com.openai.codex"

    func relaunchIfRunning() async throws {
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }
        guard !applications.isEmpty else { return }

        let applicationURL = applications.compactMap(\.bundleURL).first
            ?? URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)

        for application in applications {
            _ = application.terminate()
        }

        let deadline = Date().addingTimeInterval(8)
        while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        if applications.contains(where: { !$0.isTerminated }) {
            for application in applications where !application.isTerminated {
                _ = application.forceTerminate()
            }
            try await Task.sleep(for: .milliseconds(500))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }
}
