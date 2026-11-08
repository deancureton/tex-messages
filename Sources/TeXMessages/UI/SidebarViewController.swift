import AppKit

final class ConversationTableView: NSTableView {
    var contextMenu: ((Int) -> NSMenu?)?
    private var closeObserver: MenuCloseObserver?
    private weak var ringedRow: ConversationRowView?

    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0, let menu = contextMenu?(index) else { return nil }
        ringedRow?.showsContextRing = false
        ringedRow = rowView(atRow: index, makeIfNecessary: false) as? ConversationRowView
        ringedRow?.showsContextRing = true
        let observer = MenuCloseObserver { [weak self] in
            self?.ringedRow?.showsContextRing = false
            self?.ringedRow = nil
        }
        closeObserver = observer
        menu.delegate = observer
        return menu
    }


    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var onTypeAhead: ((NSEvent) -> Void)?
    private(set) var isHandlingKey = false

    override func keyDown(with event: NSEvent) {
        let isShortcut = !event.modifierFlags.intersection([.command, .control]).isEmpty
        if !isShortcut, let scalar = event.characters?.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F, !(0xF700...0xF8FF).contains(scalar.value) {
            onTypeAhead?(event)
            return
        }
        isHandlingKey = true
        super.keyDown(with: event)
        isHandlingKey = false
    }
}

final class ConversationRowView: NSTableRowView {
    var showsContextRing = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsContextRing else { return }
        (isSelected && window?.isKeyWindow == true ? NSColor.white : Theme.selection).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 11, dy: 1), xRadius: 12, yRadius: 12)
        path.lineWidth = 2
        path.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var windowFocused: Bool { window?.isKeyWindow == true }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        (windowFocused ? Theme.selection : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 0), xRadius: 12, yRadius: 12).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && windowFocused ? .emphasized : .normal
    }
}

final class PreviewLabelCell: NSTextFieldCell {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            if oldValue != backgroundStyle {
                (controlView as? PreviewLabel)?.onStyleChange?(backgroundStyle == .emphasized)
            }
        }
    }
}

final class PreviewLabel: NSTextField {
    var onStyleChange: ((Bool) -> Void)?

    override class var cellClass: AnyClass? {
        get { PreviewLabelCell.self }
        set {}
    }
}

final class ConversationCell: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static let identifier = NSUserInterfaceItemIdentifier("conversation")

    private let dot = NSView()
    private let separator = PillView()
    private let muteIcon = NSImageView()
    private let avatar = AvatarView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let previewLabel = PreviewLabel(wrappingLabelWithString: "")
    private var preview = ""
    private var previewString = NSAttributedString()
    private let previewFade = CAGradientLayer()
    private var emphasized = false

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier

        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.blue.cgColor
        dot.layer?.cornerRadius = 4.5
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.alignment = .right
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.onStyleChange = { [weak self] emphasized in self?.setEmphasized(emphasized) }
        previewLabel.isSelectable = false
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.cell?.truncatesLastVisibleLine = true
        muteIcon.image = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: "Alerts hidden")
        muteIcon.contentTintColor = .tertiaryLabelColor
        muteIcon.imageScaling = .scaleProportionallyDown
        for view in [dot, avatar, nameLabel, timeLabel, previewLabel, separator, muteIcon] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    func setSeparatorHidden(_ hidden: Bool) {
        separator.isHidden = hidden
    }

    func configure(_ conversation: Conversation) {
        let title = conversation.title
        dot.isHidden = conversation.unreadCount == 0
        muteIcon.isHidden = !conversation.isMuted
        avatar.configure(handles: conversation.avatarHandles, photo: conversation.groupPhotoURL)
        nameLabel.stringValue = title
        timeLabel.stringValue = Format.sidebar(conversation.lastDate)
        preview = conversation.preview
        applyColors()
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel("\(title). \(conversation.unreadCount > 0 ? "Unread. " : "")\(conversation.preview)")
    }

    private func applyColors() {
        let primary: NSColor = emphasized ? .white : .labelColor
        let secondary: NSColor = emphasized ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
        dot.layer?.backgroundColor = (emphasized ? NSColor.white : Theme.blue).cgColor
        nameLabel.textColor = primary
        timeLabel.textColor = secondary
        previewString = BubbleText.preview(preview, color: secondary)
        previewLabel.attributedStringValue = previewString
        needsLayout = true
        previewLabel.lineBreakMode = .byTruncatingTail
    }

    @objc var backgroundStyle: NSView.BackgroundStyle = .normal {
        didSet { setEmphasized(backgroundStyle == .emphasized) }
    }

    private func setEmphasized(_ now: Bool) {
        guard now != emphasized else { return }
        emphasized = now
        applyColors()
    }

    private func updatePreviewFade() {
        let width = previewLabel.bounds.width
        var overflows = false
        previewString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: previewString.length)) { value, _, stop in
            if let cell = (value as? NSTextAttachment)?.attachmentCell, cell.cellSize().width > width {
                overflows = true
                stop.pointee = true
            }
        }
        previewLabel.wantsLayer = true
        guard overflows, width > 40 else {
            previewLabel.layer?.mask = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewFade.frame = previewLabel.bounds
        previewFade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        previewFade.locations = [0, NSNumber(value: Double((width - 36) / width)), 1]
        previewFade.startPoint = CGPoint(x: 0, y: 0.5)
        previewFade.endPoint = CGPoint(x: 1, y: 0.5)
        previewLabel.layer?.mask = previewFade
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        dot.frame = NSRect(x: 14.5, y: bounds.midY - 4.5, width: 9, height: 9)
        avatar.frame = NSRect(x: 28, y: bounds.midY - 20, width: 40, height: 40)
        separator.frame = NSRect(x: 74, y: bounds.height - 1, width: max(0, width - 96), height: 0.5)
        timeLabel.sizeToFit()
        let timeWidth = timeLabel.frame.width
        timeLabel.frame = NSRect(x: width - 20 - timeWidth, y: 17, width: timeWidth, height: 15)
        nameLabel.frame = NSRect(x: 72, y: 15, width: max(0, width - 72 - 28 - timeWidth - (muteIcon.isHidden ? 0 : 18)), height: 18)
        muteIcon.frame = NSRect(x: width - 20 - timeWidth - 18, y: 18, width: 13, height: 13)
        previewLabel.frame = NSRect(x: 72, y: 32, width: max(0, width - 72 - 20), height: 32)
        updatePreviewFade()
    }
}

final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onSelect: ((Conversation?, Bool) -> Void)?
    var onFocusComposer: (() -> Void)?

    private let searchField = NSTextField()
    private let searchIcon = NSImageView()
    private let filterButton = NSButton()
    private let searchGlass = NSGlassEffectView()
    private let searchHost = FlippedView()
    private var unreadOnly = false
    private let scrollView = NSScrollView()
    private let tableView = ConversationTableView()
    private let spinner = NSProgressIndicator()
    private let pinnedGrid = PinnedGridView()
    private var pins: [Conversation] = []
    private var all: [Conversation] = []
    private var everything: [Conversation] = []
    private var visible: [Conversation] = []
    private var selectedKey: String?
    private var lastFiltering = false
    private var suppressSelection = false
    private var searchMatches: Set<Int64>?
    private var searchToken = UUID()

    override func loadView() {
        let root = FlippedView()
        root.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
        view = root

        filterButton.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        filterButton.bezelStyle = .glass
        filterButton.borderShape = .circle
        filterButton.contentTintColor = .labelColor
        filterButton.target = self
        filterButton.action = #selector(showFilter)
        filterButton.toolTip = "Filter"
        root.addSubview(filterButton)

        searchGlass.cornerRadius = 18
        searchGlass.contentView = searchHost
        searchGlass.applyMessagesStyle()
        root.addSubview(searchGlass)

        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 14)
        searchField.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchHost.addSubview(searchIcon)
        searchField.setAccessibilityLabel("Search conversations")
        searchHost.addSubview(searchField)

        let column = NSTableColumn(identifier: .init("main"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 80
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Conversations")
        tableView.allowsTypeSelect = false
        tableView.contextMenu = { [weak self] index in
            guard let self, index < self.visible.count else { return nil }
            return ContextMenus.conversation(self.visible[index], pinned: false)
        }
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.onTypeAhead = { [weak self] event in
            self?.onFocusComposer?()
            self?.view.window?.firstResponder?.keyDown(with: event)
        }

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        root.addSubview(scrollView)
        pinnedGrid.onSelect = { [weak self] conversation in
            guard let self else { return }
            self.selectedKey = conversation.key
            self.syncSelection()
            self.onSelect?(conversation, true)
        }
        root.addSubview(pinnedGrid)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.startAnimation(nil)
        root.addSubview(spinner)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = view.bounds.width
        filterButton.frame = NSRect(x: width - 44, y: 8, width: 36, height: 36)
        searchGlass.frame = NSRect(x: 8, y: 62, width: width - 16, height: 36)
        searchIcon.frame = NSRect(x: 11, y: 9, width: 18, height: 18)
        searchField.frame = NSRect(x: 35, y: 9, width: max(0, width - 16 - 45), height: 20)
        let gridHeight = pinnedGrid.isHidden ? 0 : pinnedGrid.height(count: pins.count)
        pinnedGrid.frame = NSRect(x: 0, y: 106, width: width, height: gridHeight)
        let listTop = 106 + gridHeight
        scrollView.frame = NSRect(x: 0, y: listTop, width: width, height: max(0, view.bounds.height - listTop))
        tableView.tableColumns.first?.width = scrollView.contentSize.width
        spinner.frame = NSRect(x: width / 2 - 8, y: 140, width: 16, height: 16)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowFocusChanged), name: name, object: window)
        }
        windowFocusChanged()
    }

    @objc private func windowFocusChanged() {
        refreshPins()
        tableView.enumerateAvailableRowViews { rowView, _ in
            rowView.needsDisplay = true
            (rowView.view(atColumn: 0) as? ConversationCell)?.backgroundStyle = rowView.interiorBackgroundStyle
        }
    }

    @objc private func rowClicked() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in self?.onFocusComposer?() }
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    func focusList() {
        view.window?.makeFirstResponder(tableView)
    }

    func update(_ conversations: [Conversation], pinned: [Conversation]) {
        spinner.stopAnimation(nil)
        let pinnedKeys = Set(pinned.map(\.key))
        pins = pinned
        everything = conversations
        all = conversations.filter { !pinnedKeys.contains($0.key) }
        view.needsLayout = true
        applyFilter()
    }

    func select(key: String?) {
        selectedKey = key
        syncSelection()
    }

    private func applyFilter() {
        let term = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let filtering = unreadOnly || !term.isEmpty
        let source = filtering ? everything : all
        let base = unreadOnly ? source.filter { $0.unreadCount > 0 } : source
        pinnedGrid.isHidden = filtering || pins.isEmpty
        view.needsLayout = true
        let pendingVisible: [Conversation]
        if term.isEmpty {
            pendingVisible = base
        } else {
            pendingVisible = base.filter { conversation in
                conversation.title.lowercased().contains(term)
                    || conversation.participants.contains { $0.lowercased().contains(term) }
                    || conversation.chatIDs.contains { searchMatches?.contains($0) == true }
            }
        }
        let previous = Dictionary(visible.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let wasFiltering = lastFiltering
        lastFiltering = filtering
        visible = pendingVisible
        tableView.reloadData()
        syncSelection()
        if !filtering, !wasFiltering, !previous.isEmpty { glideRows(from: previous) }
    }

    private func glideRows(from previous: [String: Int]) {
        let range = tableView.rows(in: tableView.visibleRect)
        var moved: CALayer?
        var distance = 0
        var animations: [(CALayer, CGFloat)] = []
        for row in range.location..<(range.location + range.length) where row < visible.count {
            guard let old = previous[visible[row].key], old != row,
                  let layer = tableView.rowView(atRow: row, makeIfNecessary: true)?.layer else { continue }
            animations.append((layer, CGFloat(old - row) * tableView.rowHeight))
            if abs(old - row) > distance {
                distance = abs(old - row)
                moved = layer
            }
        }
        guard !animations.isEmpty else { return }
        moved?.zPosition = 1
        CATransaction.begin()
        CATransaction.setCompletionBlock { moved?.zPosition = 0 }
        for (layer, delta) in animations {
            let animation = CABasicAnimation(keyPath: "transform.translation.y")
            animation.fromValue = delta
            animation.toValue = 0
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "reorder")
        }
        CATransaction.commit()
    }

    private func refreshPins() {
        pinnedGrid.update(pins, selectedKey: selectedKey, focused: view.window?.isKeyWindow == true)
    }

    private func syncSelection() {
        refreshPins()
        suppressSelection = true
        defer {
            suppressSelection = false
            refreshSeparators()
        }
        if let selectedKey, let index = visible.firstIndex(where: { $0.key == selectedKey }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
    }

    @objc private func showFilter() {
        let menu = NSMenu()
        let everything = menu.addItem(withTitle: "All Messages", action: #selector(filterAll), keyEquivalent: "")
        let unread = menu.addItem(withTitle: "Unread Messages", action: #selector(filterUnread), keyEquivalent: "")
        everything.target = self
        unread.target = self
        everything.state = unreadOnly ? .off : .on
        unread.state = unreadOnly ? .on : .off
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: filterButton.bounds.height + 4), in: filterButton)
    }

    @objc private func filterAll() {
        unreadOnly = false
        applyFilter()
    }

    @objc private func filterUnread() {
        unreadOnly = true
        applyFilter()
    }

    private func refreshSeparators() {
        let selected = tableView.selectedRow
        let range = tableView.rows(in: tableView.visibleRect)
        for row in range.location..<(range.location + range.length) {
            let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ConversationCell
            cell?.setSeparatorHidden(row == selected || row + 1 == selected)
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                cell?.backgroundStyle = rowView.interiorBackgroundStyle
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        searchField.stringValue = ""
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        focusList()
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        searchMatches = nil
        applyFilter()
        let term = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let token = UUID()
        searchToken = token
        guard term.count >= 2, let database = AppModel.shared.database else { return }
        Task {
            let matches = try? await database.search(term)
            await MainActor.run {
                guard self.searchToken == token else { return }
                self.searchMatches = matches
                self.applyFilter()
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ConversationRowView()
        rowView.wantsLayer = true
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ConversationCell.identifier, owner: self) as? ConversationCell ?? ConversationCell()
        cell.configure(visible[row])
        cell.backgroundStyle = row == tableView.selectedRow && view.window?.isKeyWindow == true ? .emphasized : .normal
        cell.setSeparatorHidden(row == tableView.selectedRow || row + 1 == tableView.selectedRow)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection else { return }
        refreshSeparators()
        let row = tableView.selectedRow
        guard row >= 0, row < visible.count else { return }
        selectedKey = visible[row].key
        refreshPins()
        onSelect?(visible[row], !tableView.isHandlingKey)
    }
}
