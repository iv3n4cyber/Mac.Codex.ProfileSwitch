import AppKit

@MainActor
enum Prompt {
    static func show(label: String, title: String, defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = label
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField

        alert.addButton(withTitle: AppText.s("OK", "确定"))
        alert.addButton(withTitle: AppText.s("Cancel", "取消"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return textField.stringValue
    }
}

@MainActor
enum Dialogs {
    static func showInfo(_ message: String) {
        show(message, style: .informational)
    }

    static func showWarning(_ message: String) {
        show(message, style: .warning)
    }

    static func showError(_ error: Error) {
        show(error.localizedDescription, style: .critical)
    }

    private static func show(_ message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = "Mac.Codex.ProfileSwitch"
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: AppText.s("OK", "确定"))
        alert.runModal()
    }
}
