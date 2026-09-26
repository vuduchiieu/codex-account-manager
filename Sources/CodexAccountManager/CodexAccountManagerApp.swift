import AppKit
import SwiftUI

@main @MainActor
final class CodexAccountManagerApp: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusBarController: StatusBarController?

    static func main() {
        let application = NSApplication.shared
        let delegate = CodexAccountManagerApp()
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
    private var outsideClickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        settingsWindowController = SettingsWindowController(model: model)
        super.init()

        if let button = statusItem.button {
            let image = Bundle.main.url(forResource: "codex-account-manager-status-icon", withExtension: "svg")
                .flatMap(NSImage.init(contentsOf:))
                ?? NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "codex-account-manager")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "codex-account-manager"
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingController = NSHostingController(rootView: MenuBarContentView(
            model: model,
            onOpenSettings: { [weak self] in self?.openSettings() }
        ))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    @objc private func handleStatusItemClick() {
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
        let menu = NSMenu(title: "codex-account-manager")
        menu.autoenablesItems = false
        menu.font = NSFont.menuFont(ofSize: 12)
        menu.addItem(menuItem(L10n.text("add_account"), action: #selector(addAccount), enabled: canAddAccount))
        menu.addItem(menuItem(L10n.text("import_current"), action: #selector(importCurrentAccount), enabled: canImportAccount))
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

    private var canAddAccount: Bool {
        model.state.codexBinaryPath != nil && !model.isAddingAccount
    }

    private var canImportAccount: Bool {
        model.state.codexBinaryPath != nil && model.canImportCurrentAccount && !model.isImportingAccount
    }

    @objc private func addAccount() { model.addAccount() }
    @objc private func importCurrentAccount() { model.importCurrentAccount() }
    @objc private func chooseBinary() { model.chooseBinary() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { model.shutdownAndQuit() }

    private func openSettings() {
        popover.performClose(nil)
        settingsWindowController.show()
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }
}
