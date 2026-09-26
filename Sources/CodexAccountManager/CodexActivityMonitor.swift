import Darwin
import Foundation

@MainActor
final class CodexActivityMonitor {
    private let codexHome: URL
    private let onPossibleAuthChange: @MainActor () -> Void
    private let onCodexActivity: @MainActor () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var activityDebounce: Task<Void, Never>?
    private var authDebounce: Task<Void, Never>?

    init(
        codexHome: URL,
        onPossibleAuthChange: @escaping @MainActor () -> Void,
        onCodexActivity: @escaping @MainActor () -> Void
    ) {
        self.codexHome = codexHome
        self.onPossibleAuthChange = onPossibleAuthChange
        self.onCodexActivity = onCodexActivity
    }

    func start() {
        stop()
        monitor(
            url: codexHome,
            events: [.write, .rename, .delete],
            handler: { [weak self] in self?.scheduleAuthCheck() }
        )
        monitor(
            url: codexHome.appendingPathComponent("auth.json"),
            events: [.write, .extend, .attrib, .rename, .delete],
            handler: { [weak self] in self?.scheduleAuthCheck() }
        )
        monitorActivityFile(named: "state_5.sqlite-wal")
        monitorActivityFile(named: "logs_2.sqlite-wal")
    }

    func stop() {
        activityDebounce?.cancel()
        authDebounce?.cancel()
        activityDebounce = nil
        authDebounce = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func monitorActivityFile(named name: String) {
        monitor(
            url: codexHome.appendingPathComponent(name),
            events: [.write, .extend, .attrib, .rename, .delete],
            handler: { [weak self] in self?.scheduleActivityRefresh() }
        )
    }

    private func monitor(url: URL, events: DispatchSource.FileSystemEvent, handler: @escaping @MainActor () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: events,
            queue: .main
        )
        source.setEventHandler {
            Task { @MainActor in handler() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }

    private func scheduleAuthCheck() {
        authDebounce?.cancel()
        authDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.onPossibleAuthChange()
        }
    }

    private func scheduleActivityRefresh() {
        activityDebounce?.cancel()
        activityDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.onCodexActivity()
        }
    }
}
