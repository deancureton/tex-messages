import AppKit

final class AccessViewController: NSViewController {
    private let detail: String

    init(detail: String) {
        self.detail = detail
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
        let title = NSTextField(labelWithString: "Allow access to your messages")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: "This app reads your Messages database directly, which macOS only allows with Full Disk Access. Turn it on for TeX Messages in System Settings, then reopen the app.")
        body.alignment = .center
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 420

        let error = NSTextField(wrappingLabelWithString: detail)
        error.alignment = .center
        error.font = .systemFont(ofSize: 11)
        error.textColor = .tertiaryLabelColor
        error.preferredMaxLayoutWidth = 420

        let open = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        open.keyEquivalent = "\r"
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))

        let buttons = NSStackView(views: [quit, open])
        let stack = NSStackView(views: [title, body, buttons, error])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
        ])
        view = root
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
