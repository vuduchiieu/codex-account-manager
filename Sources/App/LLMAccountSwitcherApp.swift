import AppKit
import SwiftUI

@main @MainActor
final class LLMAccountSwitcherApp: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusBarController: StatusBarController?

    static func main() {
        let application = NSApplication.shared
        let delegate = LLMAccountSwitcherApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(model: model)
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let settingsWindowController: SettingsWindowController
    private let onboardingWindowController: OnboardingWindowController
    private var outsideClickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        settingsWindowController = SettingsWindowController(model: model)
        onboardingWindowController = OnboardingWindowController(model: model)
        super.init()

        if let button = statusItem.button {
            let image = Bundle.main.url(forResource: "llm-account-switcher-status-icon", withExtension: "svg")
                .flatMap(NSImage.init(contentsOf:))
                ?? NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "LLM Account Switcher")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "LLM Account Switcher"
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingController = NSHostingController(rootView: MenuBarContentView(
            model: model,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenAccountSettings: { [weak self] in self?.openAccountSettings() }
        ))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        Task { [weak self] in
            guard let self else { return }
            while self.model.isLoading {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if self.model.needsOnboarding {
                self.onboardingWindowController.show()
            }
        }
    }

    @objc private func handleStatusItemClick() {
        if model.needsOnboarding {
            onboardingWindowController.show()
            return
        }
        guard let button = statusItem.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            popover.performClose(nil)
            showQuickActions()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            model.menuOpened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startOutsideClickMonitoring()
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func showQuickActions() {
        let menu = NSMenu(title: "LLM Account Switcher")
        menu.autoenablesItems = false
        menu.font = NSFont.menuFont(ofSize: 12)
        menu.addItem(menuItem(L10n.text("add_account"), action: #selector(showAccountSettings), enabled: true))
        if model.state.codexBinaryPath == nil {
            menu.addItem(menuItem(L10n.text("choose_binary"), action: #selector(chooseBinary), enabled: true))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text("settings"), action: #selector(showSettings), enabled: true))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text("quit"), action: #selector(quit), enabled: true))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func showAccountSettings() { openAccountSettings() }
    @objc private func chooseBinary() { model.chooseBinary() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { model.shutdownAndQuit() }

    private func openSettings() {
        guard !model.needsOnboarding else {
            onboardingWindowController.show()
            return
        }
        popover.performClose(nil)
        settingsWindowController.show()
    }

    private func openAccountSettings() {
        guard !model.needsOnboarding else {
            onboardingWindowController.show()
            return
        }
        popover.performClose(nil)
        settingsWindowController.showAccounts()
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }
}
