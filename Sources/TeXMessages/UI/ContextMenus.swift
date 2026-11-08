import AppKit
import Quartz
import Photos

final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
    }
}

final class QuickLookController: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookController()

    private(set) var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.updateController()
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}

final class MenuCloseObserver: NSObject, NSMenuDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func menuDidClose(_ menu: NSMenu) {
        onClose()
    }
}

final class MenuContext {
    var showTimes = false
    var toggleTimes: () -> Void = {}
    var setBackground: (URL) -> Void = { _ in }
    var tapbackDetails: ([Tapback], NSView, NSPoint) -> Void = { _, _, _ in }
}

enum ContextMenus {
    static var openWindow: ((Conversation) -> Void)?

    static func menu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.showsStateColumn = false
        return menu
    }

    @discardableResult
    static func add(_ menu: NSMenu, _ title: String, symbol: String? = nil, _ action: (() -> Void)? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            #if canImport(AppKit, _version: 2700)
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            #endif
        }
        if let action {
            let target = MenuAction(action)
            item.target = target
            item.action = #selector(MenuAction.fire)
            item.representedObject = target
            item.isEnabled = true
        } else {
            item.isEnabled = false
        }
        menu.addItem(item)
        return item
    }

    private static func tapbackRow(_ menu: NSMenu) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .equalSpacing
        row.edgeInsets = NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16)
        row.alphaValue = 0.45
        for glyph in ["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F44E}", "HA", "\u{203C}\u{FE0F}", "\u{2753}"] {
            let label = NSTextField(labelWithString: glyph)
            label.font = .systemFont(ofSize: 20)
            row.addArrangedSubview(label)
        }
        row.frame = NSRect(x: 0, y: 0, width: 250, height: 38)
        row.setAccessibilityLabel("Tapbacks are not available")
        let item = NSMenuItem()
        item.view = row
        item.isEnabled = false
        menu.addItem(item)
    }

    static func messageHeader(_ menu: NSMenu, tapbackDetails: (() -> Void)?) {
        add(menu, "Ask Siri", symbol: "sparkle")
        tapbackRow(menu)
        add(menu, "Tapback Details\u{2026}", symbol: "magnifyingglass.circle", tapbackDetails)
        add(menu, "Reply\u{2026}", symbol: "arrowshape.turn.up.left")
        add(menu, "Attach Sticker\u{2026}", symbol: "seal")
        menu.addItem(.separator())
    }

    static func background(_ context: MenuContext?) -> NSMenu {
        let result = menu()
        add(result, "Ask Siri", symbol: "sparkle")
        if let context {
            add(result, context.showTimes ? "Hide Times" : "Show Times") { context.toggleTimes() }
        } else {
            add(result, "Show Times")
        }
        return result
    }

    static func conversation(_ conversation: Conversation, pinned: Bool) -> NSMenu {
        let result = menu()
        add(result, "Ask Siri", symbol: "sparkle")
        add(result, pinned ? "Unpin" : "Pin") { AppModel.shared.setPinned(conversation, !pinned) }
        result.addItem(.separator())
        if conversation.unreadCount > 0 {
            add(result, "Mark as Read") { AppModel.shared.markRead(conversation) }
        } else {
            add(result, "Mark as Unread") { AppModel.shared.markUnread(conversation) }
        }
        add(result, conversation.isMuted ? "Show Alerts" : "Hide Alerts") { AppModel.shared.toggleMuted(conversation) }
        result.addItem(.separator())
        add(result, "Open in New Window") { openWindow?(conversation) }
        result.addItem(.separator())
        add(result, "Delete\u{2026}")
        return result
    }

    static func share(_ items: [Any], from view: NSView, at point: NSPoint) {
        let host = view.window?.contentView ?? view
        let anchor = view.convert(point, to: host)
        DispatchQueue.main.async {
            guard host.window != nil else { return }
            NSSharingServicePicker(items: items).show(relativeTo: NSRect(origin: anchor, size: .zero), of: host, preferredEdge: .minY)
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func copyFile(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    static func header(_ conversation: Conversation, faceTime: @escaping () -> Void, editBackground: @escaping () -> Void, removeBackground: (() -> Void)?) -> NSMenu {
        let result = menu()
        add(result, "Ask Siri", symbol: "sparkle")
        result.addItem(.separator())

        let handle = conversation.isGroup ? nil : conversation.participants.first
        let isPhone = handle.map { !$0.contains("@") } ?? false
        if let handle, isPhone {
            add(result, "Call", symbol: "phone") { open("tel:\(handle)") }
        } else {
            add(result, "Call", symbol: "phone")
        }
        add(result, "FaceTime", symbol: "video", faceTime)
        if let handle, !isPhone {
            add(result, "Mail", symbol: "envelope") { open("mailto:\(handle)") }
        } else {
            add(result, "Mail", symbol: "envelope")
        }
        if let handle, let person = Contacts.shared.person(for: handle) {
            add(result, "Show Contact Card", symbol: "person.crop.circle") { open("addressbook://\(person.id)") }
        } else {
            add(result, "Show Contact Card", symbol: "person.crop.circle")
        }

        if let handle {
            result.addItem(.separator())
            add(result, Contacts.formatted(handle))
            add(result, "Copy") { copy(handle) }
        }
        result.addItem(.separator())
        add(result, "Edit Background") { editBackground() }
        if let removeBackground { add(result, "Remove Background", removeBackground) }
        return result
    }

    static func tapbackGlyph(_ tapback: Tapback) -> String {
        switch tapback.type {
        case 2000: return "\u{2764}\u{FE0F}"
        case 2001: return "\u{1F44D}"
        case 2002: return "\u{1F44E}"
        case 2003: return "HA"
        case 2004: return "\u{203C}\u{FE0F}"
        case 2005: return "\u{2753}"
        default: return tapback.emoji ?? "\u{1F642}"
        }
    }

    static func addToPhotos(_ url: URL, isVideo: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } completionHandler: { success, _ in
                if !success { DispatchQueue.main.async { NSSound.beep() } }
            }
        }
    }

    private static func open(_ string: String) {
        guard let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: encoded) else { return }
        NSWorkspace.shared.open(url)
    }
}
