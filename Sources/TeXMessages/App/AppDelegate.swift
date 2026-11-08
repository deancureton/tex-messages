import AppKit
import Quartz

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let sidebar = SidebarViewController()
    private let transcript = TranscriptViewController()
    private var pendingHandle: String?
    private var didAutoSelect = false
    private var extraWindows: [NSWindow: TranscriptViewController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        MathEngine.shared.warm()
        NSApp.mainMenu = makeMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Messages"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 620, height: 420)
        window.isReleasedWhenClosed = false

        do {
            try AppModel.shared.connect()
            window.contentViewController = makeSplit()
            window.toolbar = NSToolbar()
            window.toolbarStyle = .unified
            bindModel()
        } catch {
            window.contentViewController = AccessViewController(detail: error.localizedDescription)
        }

        window.setFrameAutosaveName("Main")
        if !window.setFrameUsingName("Main") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    private func makeSplit() -> NSSplitViewController {
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 300)
        let contentItem = NSSplitViewItem(viewController: transcript)
        contentItem.minimumThickness = 360
        contentItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 240)
        if #available(macOS 26.1, *) {
            let edge = NSSplitViewItemAccessoryViewController()
            let spacer = PassThroughView(frame: NSRect(x: 0, y: 0, width: 100, height: 14))
            spacer.heightAnchor.constraint(equalToConstant: 14).isActive = true
            edge.view = spacer
            edge.automaticallyAppliesContentInsets = false
            edge.preferredScrollEdgeEffectStyle = .hard
            contentItem.addTopAlignedAccessoryViewController(edge)
        }
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        split.splitView.autosaveName = "MainSplit"
        return split
    }

    private func bindModel() {
        sidebar.onSelect = { [weak self] conversation, focus in self?.transcript.show(conversation, focusComposer: focus) }
        sidebar.onFocusComposer = { [weak self] in self?.transcript.focusComposer() }
        transcript.onCompose = { [weak self] in self?.newMessage() }
        transcript.onNewConversationSent = { [weak self] handle in self?.pendingHandle = handle }
        AppModel.shared.onConversations = { [weak self] in self?.conversationsChanged() }
        AppModel.shared.onDatabaseChange = { [weak self] in
            self?.transcript.databaseChanged()
            self?.extraWindows.values.forEach { $0.databaseChanged() }
        }
        ContextMenus.openWindow = { [weak self] conversation in self?.openWindow(for: conversation) }
        AppModel.shared.onContactsLoaded = { [weak self] in self?.transcript.contactsLoaded() }
    }

    private func conversationsChanged() {
        let conversations = AppModel.shared.conversations
        sidebar.update(conversations, pinned: AppModel.shared.pinned)
        transcript.updateCurrent(from: conversations)
        extraWindows.values.forEach { $0.updateCurrent(from: conversations) }
        if !didAutoSelect, let first = conversations.first {
            didAutoSelect = true
            sidebar.select(key: first.key)
            transcript.show(first)
        }
        if let key = transcript.currentKey { sidebar.select(key: key) }
        guard let handle = pendingHandle else { return }
        let key = Contacts.key(handle)
        if let match = conversations.first(where: { !$0.isGroup && $0.participants.contains { Contacts.key($0) == key } }) {
            pendingHandle = nil
            sidebar.select(key: match.key)
            transcript.show(match)
        }
    }

    private func openWindow(for conversation: Conversation) {
        let controller = TranscriptViewController()
        controller.onCompose = { [weak self] in self?.newMessage() }
        let extra = NSWindow(contentViewController: controller)
        extra.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        extra.titleVisibility = .hidden
        extra.titlebarAppearsTransparent = true
        extra.minSize = NSSize(width: 380, height: 420)
        extra.setContentSize(NSSize(width: 520, height: 720))
        extra.isReleasedWhenClosed = false
        extra.delegate = self
        extra.title = conversation.title
        extraWindows[extra] = controller
        controller.show(conversation)
        extra.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow { extraWindows[closing] = nil }
    }

    @objc func newMessage() {
        sidebar.select(key: nil)
        transcript.showNewMessage()
    }

    @objc func findConversation() {
        sidebar.focusSearch()
    }

    @objc func showEmoji() {
        NSApp.orderFrontCharacterPalette(nil)
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About TeX Messages", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide TeX Messages", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit TeX Messages", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, title: "TeX Messages", to: main)

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Message", action: #selector(newMessage), keyEquivalent: "n").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, title: "File", to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find", action: #selector(findConversation), keyEquivalent: "f").target = self
        let emoji = edit.addItem(withTitle: "Emoji & Symbols", action: #selector(showEmoji), keyEquivalent: " ")
        emoji.keyEquivalentModifierMask = [.command, .control]
        emoji.target = self
        add(edit, title: "Edit", to: main)

        let view = NSMenu(title: "View")
        let sidebarToggle = view.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebarToggle.keyEquivalentModifierMask = [.command, .control]
        add(view, title: "View", to: main)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        add(windowMenu, title: "Window", to: main)
        NSApp.windowsMenu = windowMenu

        return main
    }

    private func add(_ menu: NSMenu, title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
