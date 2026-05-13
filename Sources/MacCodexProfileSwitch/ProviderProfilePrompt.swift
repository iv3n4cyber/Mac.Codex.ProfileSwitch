import AppKit

@MainActor
enum ProviderProfilePrompt {
    static func run(
        mode: Mode = .add,
        defaultInput: ProviderProfileInput? = nil
    ) -> ProviderProfileInput? {
        let alert = NSAlert()
        alert.messageText = mode.title
        alert.informativeText = mode.message
        alert.addButton(withTitle: mode.confirmTitle)
        alert.addButton(withTitle: AppText.s("Cancel", "取消"))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let name = NSTextField(string: defaultInput?.name ?? "")
        let baseURL = NSTextField(string: defaultInput?.baseURL ?? "")
        let apiKey = NSSecureTextField(string: defaultInput?.apiKey ?? "")

        stack.addArrangedSubview(row(label: "Profile Name", field: name, placeholder: "relay"))
        stack.addArrangedSubview(row(label: "Base URL", field: baseURL, placeholder: "https://api.example.com/v1"))
        stack.addArrangedSubview(row(label: "API Key", field: apiKey, placeholder: "sk-..."))

        stack.frame = NSRect(x: 0, y: 0, width: 390, height: 98)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return ProviderProfileInput(
            name: name.stringValue,
            baseURL: baseURL.stringValue,
            apiKey: apiKey.stringValue
        )
    }

    private static func row(label: String, field: NSTextField, placeholder: String) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let row = NSStackView(views: [labelView, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    enum Mode {
        case add
        case edit

        @MainActor
        var title: String {
            switch self {
            case .add:
                return AppText.s("Add Provider", "添加 Provider")
            case .edit:
                return AppText.s("Edit Provider", "编辑 Provider")
            }
        }

        @MainActor
        var message: String {
            switch self {
            case .add:
                return AppText.s(
                    "Create an OpenAI-compatible provider profile.",
                    "创建一个 OpenAI 兼容 Provider profile。"
                )
            case .edit:
                return AppText.s(
                    "Update this OpenAI-compatible provider profile.",
                    "更新这个 OpenAI 兼容 Provider profile。"
                )
            }
        }

        @MainActor
        var confirmTitle: String {
            switch self {
            case .add:
                return AppText.s("Create", "创建")
            case .edit:
                return AppText.s("Save", "保存")
            }
        }
    }
}
