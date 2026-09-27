import AppKit

@MainActor
enum NativeDeleteAlert {
    static func confirm(
        title: String,
        message: String,
        deleteTitle: String,
        cancelTitle: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = Bundle.main.url(forResource: "llm-account-switcher-icon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
        alert.messageText = title
        alert.informativeText = message

        let deleteButton = alert.addButton(withTitle: deleteTitle)
        let cancelButton = alert.addButton(withTitle: cancelTitle)
        cancelButton.keyEquivalent = "\u{1b}"

        styleDeleteButton(deleteButton, title: deleteTitle)
        deleteButton.keyEquivalent = ""
        deleteButton.refusesFirstResponder = true
        cancelButton.refusesFirstResponder = true
        alert.window.initialFirstResponder = nil
        let equalWidth = deleteButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor)
        equalWidth.priority = .required
        equalWidth.isActive = true

        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func styleDeleteButton(_ button: NSButton, title: String) {
        button.isBordered = true
        button.bezelStyle = .rounded
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
    }

}

@MainActor
enum NativeErrorAlert {
    static func show(title: String, message: String, closeTitle: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = Bundle.main.url(forResource: "llm-account-switcher-icon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
        alert.messageText = title
        alert.informativeText = message

        let closeButton = alert.addButton(withTitle: closeTitle)
        closeButton.keyEquivalent = ""
        closeButton.refusesFirstResponder = true
        alert.window.initialFirstResponder = nil
        _ = alert.runModal()
    }
}

@MainActor
enum NativeReauthenticationAlert {
    static func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = Bundle.main.url(forResource: "llm-account-switcher-icon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
        alert.messageText = title
        alert.informativeText = message

        let confirmButton = alert.addButton(withTitle: confirmTitle)
        let cancelButton = alert.addButton(withTitle: cancelTitle)
        cancelButton.keyEquivalent = "\u{1b}"
        confirmButton.refusesFirstResponder = true
        cancelButton.refusesFirstResponder = true
        alert.window.initialFirstResponder = nil

        return alert.runModal() == .alertFirstButtonReturn
    }
}
