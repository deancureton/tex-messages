import AppKit

final class DropRootView: FlippedView {
    var onDrop: (([URL]) -> Void)?
    var menuContext: MenuContext?

    override func menu(for event: NSEvent) -> NSMenu? {
        ContextMenus.background(menuContext)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

final class TranscriptViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSControlTextEditingDelegate {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerChevron = NSTextField(labelWithString: "›")
    private let composeButton = NSButton()
    private let headerGlass = NSGlassEffectView()
    private let headerHost = FlippedView()
    private let headerAvatar = AvatarView()
    private let headerTitle = NSTextField(labelWithString: "")
    private let headerButton = NSButton()
    private let facetimeButton = NSButton()
    private let toLabel = NSTextField(labelWithString: "To:")
    private let toField = NSTextField()
    private let composer = ComposerView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    private var conversation: Conversation?
    private var isComposingNew = false
    private var rows: [Row] = []
    private var messages: [Int64: Message] = [:]
    private var tapbacks: [String: [Tapback]] = [:]
    private var replies: [String: ReplyOriginal] = [:]
    private var pending: [PendingMessage] = []
    private var hasMore = false
    private var loadingOlder = false
    private var generation = 0
    private var builder = RowBuilder()
    private let buildQueue = DispatchQueue(label: "transcript.build", qos: .userInitiated)
    private var lastWidth: CGFloat = 0
    private var drafts: [String: String] = [:]
    private var refreshRunning = false
    private var refreshQueued = false
    private var suppressCompletion = false
    private var appliedInsets = NSEdgeInsetsZero
    private var stuck = true
    private var lastClipSize = NSSize.zero
    private var flightPill: NSRect?
    private var flightActive = false
    private var effectPlaying = false
    private let menuContext = MenuContext()
    private let backgroundView = NSView()
    private let composerPreview = ComposerPreviewView()
    private var effectHiddenID: String?

    var onNewConversationSent: ((String) -> Void)?
    var onCompose: (() -> Void)?

    private var sortedMessages: [Message] {
        messages.values.sorted { ($0.rawDate, $0.rowID) < ($1.rawDate, $1.rowID) }
    }

    override func loadView() {
        let root = DropRootView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        root.onDrop = { [weak self] urls in self?.composer.add(files: urls) }
        root.menuContext = menuContext
        view = root
        backgroundView.wantsLayer = true
        backgroundView.layer?.contentsGravity = .resizeAspectFill
        backgroundView.layer?.masksToBounds = true
        backgroundView.isHidden = true
        root.addSubview(backgroundView)
        menuContext.toggleTimes = { [weak self] in
            guard let self else { return }
            self.menuContext.showTimes.toggle()
            self.tableView.reloadData()
        }
        menuContext.setBackground = { [weak self] url in self?.setBackground(url) }
        menuContext.tapbackDetails = { [weak self] tapbacks, source, point in self?.showTapbackDetails(tapbacks, from: source, at: point) }

        let column = NSTableColumn(identifier: .init("main"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Messages")

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        root.addSubview(scrollView)

        root.addSubview(headerAvatar)
        headerGlass.cornerRadius = 14
        headerGlass.applyMessagesStyle()
        headerGlass.contentView = headerHost
        root.addSubview(headerGlass)
        headerChevron.textColor = .secondaryLabelColor
        headerChevron.font = .systemFont(ofSize: 18, weight: .light)
        headerTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        headerTitle.lineBreakMode = .byTruncatingTail
        headerButton.isTransparent = true
        headerButton.target = self
        headerButton.action = #selector(showDetails)
        headerButton.setAccessibilityLabel("Conversation details")
        toField.isBordered = false
        toField.drawsBackground = false
        toField.focusRingType = .none
        toField.placeholderString = "Name, phone, or email"
        toField.delegate = self
        toField.font = .systemFont(ofSize: 13)
        toField.setAccessibilityLabel("Recipient")
        toLabel.textColor = .secondaryLabelColor
        for item in [headerTitle, headerChevron, headerButton, toLabel, toField] as [NSView] { headerHost.addSubview(item) }

        configureGlassButton(facetimeButton, symbol: "video", label: "FaceTime", action: #selector(startFaceTime))
        configureGlassButton(composeButton, symbol: "square.and.pencil", label: "New Message", action: #selector(composeTapped))
        root.addSubview(facetimeButton)
        root.addSubview(composeButton)

        composer.onSend = { [weak self] text, files in self?.send(text: text, files: files) }
        composer.onHeightChange = { [weak self] in self?.view.needsLayout = true }
        composer.onTextChange = { [weak self] text in self?.updateComposerPreview(text) }
        composer.placeholder = "iMessage"
        composerPreview.isHidden = true
        root.addSubview(composerPreview)
        root.addSubview(composer)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        root.addSubview(emptyLabel)

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        root.addSubview(spinner)

        showEmptyState()
    }

    private func configureGlassButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.toolTip = label
    }

    private func showEmptyState() {
        emptyLabel.stringValue = "No Conversation Selected"
        updateChromeVisibility()
    }

    private func updateChromeVisibility() {
        let hasConversation = conversation != nil
        let active = hasConversation || isComposingNew
        headerGlass.isHidden = !active
        composer.isHidden = !active
        emptyLabel.isHidden = active
        facetimeButton.isHidden = !hasConversation
        headerAvatar.isHidden = !hasConversation
        headerChevron.isHidden = isComposingNew
        headerTitle.isHidden = isComposingNew
        headerButton.isHidden = isComposingNew
        toLabel.isHidden = !isComposingNew
        toField.isHidden = !isComposingNew
        view.needsLayout = true
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        backgroundView.frame = bounds
        scrollView.frame = bounds

        let composerHeight = composer.preferredHeight
        let horizontal: CGFloat = 12
        composer.frame = NSRect(x: horizontal, y: bounds.height - composerHeight - 12, width: bounds.width - horizontal * 2, height: composerHeight)
        if !composerPreview.isHidden {
            let size = composerPreview.preferredSize
            composerPreview.frame = NSRect(x: bounds.width - Theme.sideMargin - size.width, y: composer.frame.minY - size.height - 8, width: size.width, height: size.height)
        }
        emptyLabel.frame = NSRect(x: 20, y: bounds.midY - 10, width: bounds.width - 40, height: 20)
        spinner.frame = NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)

        let title = headerTitle.attributedStringValue.size().width
        let headerWidth: CGFloat
        if isComposingNew {
            headerWidth = min(bounds.width - 40, 460)
        } else {
            headerWidth = min(bounds.width - 100, ceil(title) + 30)
        }
        headerGlass.frame = NSRect(x: round(bounds.midX - headerWidth / 2), y: 44, width: max(headerWidth, 44), height: 28)
        headerAvatar.frame = NSRect(x: round(bounds.midX - 20), y: 7, width: 40, height: 40)
        headerTitle.frame = NSRect(x: 9, y: 5, width: max(0, headerGlass.bounds.width - 23), height: 18)
        headerChevron.frame = NSRect(x: headerGlass.bounds.width - 16, y: 2, width: 10, height: 22)
        headerButton.frame = headerGlass.bounds
        toLabel.frame = NSRect(x: 12, y: 5, width: 26, height: 18)
        toField.frame = NSRect(x: 40, y: 5, width: max(0, headerGlass.bounds.width - 52), height: 18)
        composeButton.frame = NSRect(x: 9, y: 8, width: 36, height: 36)
        facetimeButton.frame = NSRect(x: bounds.width - 44, y: 8, width: 36, height: 36)

        let previewHeight = composerPreview.isHidden ? 0 : composerPreview.preferredSize.height + 8
        let insets = NSEdgeInsets(top: 80, left: 0, bottom: composerHeight + 24 + previewHeight, right: 0)
        if !NSEdgeInsetsEqual(insets, appliedInsets) {
            appliedInsets = insets
            scrollView.contentInsets = insets
            if stuck { scrollToBottom() }
        }

        let width = scrollView.contentSize.width
        if width != lastWidth {
            lastWidth = width
            tableView.tableColumns.first?.width = width
            rows.forEach { $0.layout(rowWidth: width) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
            }
        }

        let clipSize = scrollView.contentView.bounds.size
        if clipSize != lastClipSize {
            lastClipSize = clipSize
            if stuck {
                DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
            }
        }
    }

    private var isAtBottom: Bool {
        let clip = scrollView.contentView
        return clip.bounds.maxY >= tableView.frame.height + appliedInsets.bottom - 48
    }

    private func scrollToBottom() {
        tableView.tile()
        tableView.layoutSubtreeIfNeeded()
        let clip = scrollView.contentView
        let y = max(-appliedInsets.top, tableView.frame.height + appliedInsets.bottom - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    func showNewMessage() {
        saveDraft()
        conversation = nil
        isComposingNew = true
        clearTranscript()
        composer.placeholder = "iMessage"
        composer.text = ""
        updateChromeVisibility()
        view.window?.makeFirstResponder(toField)
    }

    func focusComposer() {
        composer.focus()
    }

    func show(_ next: Conversation?, focusComposer shouldFocus: Bool = true) {
        saveDraft()
        if conversation?.key != next?.key { VoicePlayback.shared.stop() }
        conversation = next
        isComposingNew = false
        clearTranscript()
        guard let next else {
            showEmptyState()
            return
        }

        headerTitle.stringValue = next.headerTitle
        headerAvatar.configure(handles: next.avatarHandles, photo: next.groupPhotoURL)
        composer.placeholder = next.isSMS ? "Text Message" : "iMessage"
        composer.text = drafts[next.key] ?? ""
        updateChromeVisibility()
        if shouldFocus { composer.focus() }
        refreshHeaderMenu()
        AppModel.shared.markOpen(next, userOpened: true)
        applyBackground()

        guard let database = AppModel.shared.database else { return }
        generation += 1
        let token = generation
        let spinnerWork = DispatchWorkItem { [weak self] in
            if self?.generation == token { self?.spinner.startAnimation(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: spinnerWork)

        Task {
            do {
                let page = try await database.page(chatIDs: next.chatIDs)
                await MainActor.run {
                    guard self.generation == token else { return }
                    spinnerWork.cancel()
                    self.spinner.stopAnimation(nil)
                    self.absorb(page)
                    self.hasMore = page.hasMore
                    self.rebuild(mode: .bottom)
                }
            } catch {
                await MainActor.run {
                    guard self.generation == token else { return }
                    spinnerWork.cancel()
                    self.spinner.stopAnimation(nil)
                    self.emptyLabel.stringValue = "Couldn’t load messages: \(error.localizedDescription)"
                    self.emptyLabel.isHidden = false
                }
            }
        }
    }

    var currentKey: String? { conversation?.key }

    func contactsLoaded() {
        guard let conversation else { return }
        headerAvatar.configure(handles: conversation.avatarHandles, photo: conversation.groupPhotoURL)
        rebuild(mode: .refresh)
    }

    private func updateComposerPreview(_ text: String) {
        let visible = composerPreview.configure(text, isSMS: conversation?.isSMS == true, maxWidth: max(120, view.bounds.width * 0.62))
        composerPreview.isHidden = !visible
        view.needsLayout = true
    }

    private func applyBackground() {
        guard let conversation, let url = AppModel.shared.background(for: conversation.key), let image = NSImage(contentsOf: url) else {
            backgroundView.layer?.contents = nil
            backgroundView.isHidden = true
            return
        }
        backgroundView.layer?.contents = image
        backgroundView.isHidden = false
    }

    private func setBackground(_ url: URL?) {
        guard let conversation else { return }
        AppModel.shared.setBackground(url, for: conversation.key)
        applyBackground()
        refreshHeaderMenu()
    }

    private func editBackground() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.setBackground(url) }
        }
    }

    private func showTapbackDetails(_ tapbacks: [Tapback], from source: NSView, at point: NSPoint) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        for tapback in tapbacks {
            let who = tapback.isFromMe ? "You" : tapback.sender.map { Contacts.shared.displayName(for: $0) } ?? "Unknown"
            stack.addArrangedSubview(NSTextField(labelWithString: "\(ContextMenus.tapbackGlyph(tapback))   \(who)"))
        }
        let controller = NSViewController()
        controller.view = stack
        controller.preferredContentSize = stack.fittingSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        let anchor = source.convert(point, to: view)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            popover.show(relativeTo: NSRect(origin: anchor, size: CGSize(width: 1, height: 1)), of: self.view, preferredEdge: .maxY)
        }
    }

    private func refreshHeaderMenu() {
        guard let conversation else { return }
        let hasBackground = AppModel.shared.background(for: conversation.key) != nil
        let menu = ContextMenus.header(
            conversation,
            faceTime: { [weak self] in self?.startFaceTime() },
            editBackground: { [weak self] in self?.editBackground() },
            removeBackground: hasBackground ? { [weak self] in self?.setBackground(nil) } : nil
        )
        headerButton.menu = menu
        headerAvatar.menu = menu
    }

    func updateCurrent(from conversations: [Conversation]) {
        guard let current = conversation,
              let updated = conversations.first(where: { $0.key == current.key })
                ?? conversations.first(where: { !Set($0.chatIDs).isDisjoint(with: current.chatIDs) }) else { return }
        conversation = updated
        refreshHeaderMenu()
        if headerTitle.stringValue != updated.headerTitle {
            headerTitle.stringValue = updated.headerTitle
            view.needsLayout = true
        }
    }

    private func saveDraft() {
        if let conversation { drafts[conversation.key] = composer.text }
    }

    private func clearTranscript() {
        generation += 1
        messages = [:]
        tapbacks = [:]
        replies = [:]
        pending = []
        rows = []
        hasMore = false
        loadingOlder = false
        builder = RowBuilder()
        spinner.stopAnimation(nil)
        tableView.reloadData()
    }

    private func absorb(_ page: MessagePage) {
        for message in page.messages { messages[message.rowID] = message }
        tapbacks = page.tapbacks
        replies.merge(page.replyPreviews) { new, _ in new }
    }

    func databaseChanged() {
        guard conversation != nil else { return }
        if refreshRunning {
            refreshQueued = true
            return
        }
        refresh()
    }

    private func refresh() {
        guard let conversation, let database = AppModel.shared.database else { return }
        let token = generation
        let sorted = sortedMessages
        let window = sorted.suffix(80)
        let since = window.first?.rawDate
        let oldest = sorted.first?.rawDate
        refreshRunning = true

        Task {
            let page = try? await database.page(chatIDs: conversation.chatIDs, since: since, oldestLoaded: oldest, limit: 2000)
            await MainActor.run {
                self.refreshRunning = false
                defer {
                    if self.refreshQueued {
                        self.refreshQueued = false
                        self.databaseChanged()
                    }
                }
                guard self.generation == token, let page else { return }
                if let since, !page.hasMore {
                    let live = Set(page.messages.map(\.rowID))
                    for (id, message) in self.messages where message.rawDate >= since && !live.contains(id) {
                        self.messages[id] = nil
                    }
                }
                self.absorb(page)
                self.reconcilePending(with: page.messages)
                AppModel.shared.markOpen(conversation)
                self.rebuild(mode: .refresh)
            }
        }
    }

    private func reconcilePending(with incoming: [Message]) {
        pending.removeAll { item in
            guard !item.failed else { return false }
            return incoming.contains { message in
                guard message.isFromMe, message.date >= item.date.addingTimeInterval(-15) else { return false }
                if let text = item.text { return message.text == text }
                if let file = item.file { return message.attachments.contains { $0.displayName == file.lastPathComponent } }
                return false
            }
        }
    }

    private enum ApplyMode {
        case bottom
        case refresh
        case prepend
        case send
    }

    private func rebuild(mode: ApplyMode) {
        let input = TranscriptInput(messages: sortedMessages, tapbacks: tapbacks, replies: replies, replyCounts: sortedMessages.reduce(into: [:]) { counts, message in
            if let guid = message.threadOriginatorGuid { counts[guid, default: 0] += 1 }
        }, pending: pending, isGroup: conversation?.isGroup == true, isSMS: conversation?.isSMS == true, width: max(lastWidth, 320))
        let token = generation
        let builder = self.builder
        buildQueue.async {
            let built = builder.build(input)
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.apply(built, mode: mode)
            }
        }
    }

    private func apply(_ built: [Row], mode: ApplyMode) {
        let clip = scrollView.contentView
        let oldHeight = tableView.frame.height
        let oldY = clip.bounds.origin.y
        let hadRows = !rows.isEmpty
        let oldPositions = visiblePositions()
        let oldLastID = rows.last?.id
        let oldIDs = Set(rows.map(\.id))
        let oldFooters = Set(rows.compactMap { row -> String? in
            if case .bubble(let model) = row.kind, model.footer != nil { return row.id }
            return nil
        })

        rows = built
        tableView.reloadData()
        tableView.tile()
        tableView.layoutSubtreeIfNeeded()

        switch mode {
        case .bottom:
            scrollToBottom()
        case .prepend:
            let delta = tableView.frame.height - oldHeight
            clip.scroll(to: NSPoint(x: 0, y: oldY + delta))
            scrollView.reflectScrolledClipView(clip)
            loadingOlder = false
        case .send:
            launchFlight()
        case .refresh:
            if stuck { scrollToBottom() }
            glideRows(from: oldPositions, oldLastID: oldLastID)
            if hadRows {
                fadeNewFooters(excluding: oldFooters)
                playNewEffect(excluding: oldIDs)
            }
        }
    }

    private var bottomOffset: CGFloat {
        max(-appliedInsets.top, tableView.frame.height + appliedInsets.bottom - scrollView.contentView.bounds.height)
    }

    private func animateToBottom() {
        let clip = scrollView.contentView
        let target = NSPoint(x: 0, y: bottomOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(target)
        }
    }

    private func launchFlight() {
        guard let pill = flightPill else {
            scrollToBottom()
            return
        }
        flightPill = nil
        stuck = true
        let last = rows.count - 1
        guard last >= 0, case .bubble(let model) = rows[last].kind,
              let row = tableView.view(atColumn: 0, row: last, makeIfNecessary: true) as? BubbleRowView else {
            scrollToBottom()
            return
        }
        row.layoutSubtreeIfNeeded()

        let shift = bottomOffset - scrollView.contentView.bounds.minY
        var body = row.convert(row.bubbleFrame, to: view)
        body.origin.y -= shift
        body.size.width -= Theme.tail

        var text = row.textSnapshot()
        if let snapshot = text {
            var frame = row.convert(snapshot.frame, to: view)
            frame.origin.y -= shift
            text = (snapshot.image, frame)
        }

        flightActive = true
        row.alphaValue = 0
        animateToBottom()
        SendFlight.run(in: view, pill: pill, body: body, composerTop: composer.frame.minY, color: model.fill, text: text) { [weak self] in
            guard let self else { return }
            self.flightActive = false
            guard !self.rows.isEmpty else { return }
            self.tableView.view(atColumn: 0, row: self.rows.count - 1, makeIfNecessary: false)?.alphaValue = 1
        }
    }

    private func visiblePositions() -> [String: CGFloat] {
        let clipY = scrollView.contentView.bounds.minY
        let range = tableView.rows(in: tableView.visibleRect)
        var positions: [String: CGFloat] = [:]
        for index in range.location..<(range.location + range.length) where index < rows.count {
            positions[rows[index].id] = tableView.rect(ofRow: index).minY - clipY
        }
        return positions
    }

    private func glideRows(from old: [String: CGFloat], oldLastID: String?) {
        guard !old.isEmpty else { return }
        let clipY = scrollView.contentView.bounds.minY
        let range = tableView.rows(in: tableView.visibleRect)
        var shift: CGFloat = 0
        for index in range.location..<(range.location + range.length) where index < rows.count {
            let current = tableView.rect(ofRow: index).minY - clipY
            var previous = old[rows[index].id]
            if previous == nil, index == rows.count - 1, let oldLastID, !rows.contains(where: { $0.id == oldLastID }) {
                previous = old[oldLastID]
            }
            if previous == nil, case .bubble(let model) = rows[index].kind, !model.fromMe,
               let view = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) {
                arrive(view)
                continue
            }
            let delta = previous.map { $0 - current } ?? shift
            if previous != nil { shift = delta }
            guard abs(delta) >= 0.5, let layer = tableView.view(atColumn: 0, row: index, makeIfNecessary: false)?.layer else { continue }
            let animation = CABasicAnimation(keyPath: "transform.translation.y")
            animation.fromValue = delta
            animation.toValue = 0
            animation.duration = 0.26
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "glide")
        }
    }

    private func playNewEffect(excluding old: Set<String>) {
        let index = rows.lastIndex { row in
            guard !old.contains(row.id), case .bubble(let model) = row.kind else { return false }
            return model.effect != nil
        }
        if let index { playEffect(at: index) }
    }

    private func playEffect(at index: Int) {
        guard !effectPlaying, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              index < rows.count, case .bubble(let model) = rows[index].kind,
              let effect = model.effect, effect != .invisibleInk,
              let row = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? BubbleRowView else { return }
        row.layoutSubtreeIfNeeded()
        var snapshot = row.bubbleSnapshot()
        if let captured = snapshot { snapshot = (captured.image, row.convert(captured.frame, to: view)) }
        let bubble = row.convert(row.bubbleBodyFrame, to: view)
        let rowID = rows[index].id
        effectPlaying = true
        if effect.replacesBubble {
            effectHiddenID = rowID
            row.alphaValue = 0
        }
        MessageEffectPlayer.play(effect, in: view, bubble: bubble, snapshot: snapshot, shake: scrollView) { [weak self] in
            guard let self else { return }
            self.effectPlaying = false
            self.effectHiddenID = nil
            if let current = self.rows.firstIndex(where: { $0.id == rowID }) {
                self.tableView.view(atColumn: 0, row: current, makeIfNecessary: false)?.alphaValue = 1
            }
        }
    }

    private func arrive(_ view: NSView) {
        guard let layer = view.layer else { return }
        let rowLayer = view.superview?.layer
        rowLayer?.zPosition = -1

        CATransaction.begin()
        CATransaction.setCompletionBlock { rowLayer?.zPosition = 0 }
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -22
        slide.toValue = 0
        slide.duration = 0.26
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(slide, forKey: "arrive")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.18
        layer.add(fade, forKey: "arriveFade")
        CATransaction.commit()
    }

    private func fadeNewFooters(excluding old: Set<String>) {
        for (index, row) in rows.enumerated() {
            guard case .bubble(let model) = row.kind, model.footer != nil, !old.contains(row.id),
                  let view = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? BubbleRowView else { continue }
            view.fadeInFooter()
        }
    }

    @objc private func scrolled() {
        if scrollView.contentView.bounds.size == lastClipSize { stuck = isAtBottom }
        guard hasMore, !loadingOlder, !rows.isEmpty, scrollView.contentView.bounds.minY < 400 else { return }
        guard let conversation, let database = AppModel.shared.database, let first = sortedMessages.first else { return }
        loadingOlder = true
        let token = generation
        Task {
            let page = try? await database.page(chatIDs: conversation.chatIDs, before: (first.rawDate, first.rowID))
            await MainActor.run {
                guard self.generation == token else { return }
                guard let page else {
                    self.loadingOlder = false
                    return
                }
                self.hasMore = page.hasMore
                for message in page.messages { self.messages[message.rowID] = message }
                self.tapbacks.merge(page.tapbacks) { new, _ in new }
                self.replies.merge(page.replyPreviews) { new, _ in new }
                self.rebuild(mode: .prepend)
            }
        }
    }

    private func send(text: String, files: [URL]) {
        if isComposingNew {
            sendNew(text: text, files: files)
            return
        }
        guard let conversation else { return }
        let guid = conversation.sendGuid
        let handle = conversation.isGroup ? nil : conversation.participants.first
        for file in files {
            let item = PendingMessage(text: nil, file: file, date: Date())
            pending.append(item)
            MessageSender.send(file: file, chatGuid: guid, handle: handle) { [weak self] error in self?.finish(item.id, error: error) }
        }
        if !text.isEmpty {
            let item = PendingMessage(text: text, file: nil, date: Date())
            pending.append(item)
            flightPill = composer.pillFrame(in: view)
            MessageSender.send(text: text, chatGuid: guid, handle: handle) { [weak self] error in self?.finish(item.id, error: error) }
        }
        drafts[conversation.key] = nil
        rebuild(mode: flightPill == nil ? .bottom : .send)
    }

    private func sendNew(text: String, files: [URL]) {
        let handle = Contacts.shared.resolve(toField.stringValue)
        guard !handle.isEmpty else {
            NSSound.beep()
            view.window?.makeFirstResponder(toField)
            return
        }
        for file in files {
            let item = PendingMessage(text: nil, file: file, date: Date())
            pending.append(item)
            MessageSender.sendNew(file: file, to: handle) { [weak self] error in self?.finish(item.id, error: error) }
        }
        if !text.isEmpty {
            let item = PendingMessage(text: text, file: nil, date: Date())
            pending.append(item)
            MessageSender.sendNew(text: text, to: handle) { [weak self] error in self?.finish(item.id, error: error) }
        }
        onNewConversationSent?(handle)
        rebuild(mode: .bottom)
    }

    private func finish(_ id: UUID, error: Error?) {
        guard let error, let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].failed = true
        NSLog("send failed: %@", error.localizedDescription)
        rebuild(mode: .refresh)
    }

    @objc private func composeTapped() {
        onCompose?()
    }

    @objc private func startFaceTime() {
        if conversation?.isGroup == true {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/FaceTime.app"))
            return
        }
        guard let handle = conversation?.participants.first,
              let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "facetime://\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showDetails() {
        guard let conversation else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        let title = NSTextField(labelWithString: conversation.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(title)
        for handle in conversation.participants {
            let label = NSTextField(labelWithString: "\(Contacts.shared.displayName(for: handle))   \(handle)")
            label.textColor = .secondaryLabelColor
            label.isSelectable = true
            stack.addArrangedSubview(label)
        }
        let controller = NSViewController()
        controller.view = stack
        controller.preferredContentSize = stack.fittingSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: headerGlass.bounds, of: headerGlass, preferredEdge: .minY)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !suppressCompletion, let editor = toField.currentEditor() as? NSTextView else { return }
        suppressCompletion = true
        editor.complete(nil)
        suppressCompletion = false
    }

    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        index.pointee = -1
        let prefix = (textView.string as NSString).substring(with: charRange)
        return Contacts.shared.matches(prefix: prefix).map(\.name)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            composer.focus()
            return true
        }
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { max(1, rows[row].height) }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.clipsToBounds = false
        rowView.wantsLayer = true
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row].kind {
        case .centered(let string):
            let view = tableView.makeView(withIdentifier: CenteredRowView.identifier, owner: self) as? CenteredRowView ?? CenteredRowView()
            view.menuContext = menuContext
            view.configure(string)
            return view
        case .bubble(let model):
            let view = tableView.makeView(withIdentifier: BubbleRowView.identifier, owner: self) as? BubbleRowView ?? BubbleRowView()
            view.menuContext = menuContext
            view.configure(model)
            view.alphaValue = (flightActive && row == rows.count - 1) || rows[row].id == effectHiddenID ? 0 : 1
            let replayRow = rows[row].id
            view.onReplay = { [weak self] in
                guard let self, let index = self.rows.firstIndex(where: { $0.id == replayRow }) else { return }
                self.playEffect(at: index)
            }
            return view
        }
    }
}
