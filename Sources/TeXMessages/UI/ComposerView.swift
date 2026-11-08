import AppKit
import UniformTypeIdentifiers

final class ComposerTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        NSAttributedString(string: placeholder, attributes: [
            .font: font ?? Theme.bodyFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.33),
        ]).draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y))
    }

    var onPasteFiles: (([URL]) -> Void)?

    override func paste(_ sender: Any?) {
        if !pasteAttachments(from: .general) { pasteAsPlainText(sender) }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(paste(_:)), Self.holdsAttachment(.general) { return true }
        return super.validateMenuItem(item)
    }

    @discardableResult
    func pasteAttachments(from pasteboard: NSPasteboard) -> Bool {
        let files = Self.attachmentFiles(from: pasteboard)
        guard !files.isEmpty else { return false }
        onPasteFiles?(files)
        return true
    }

    private static func pastedFiles(_ pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
    }

    private static func holdsImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.string(forType: .string) == nil && pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    private static func holdsAttachment(_ pasteboard: NSPasteboard) -> Bool {
        !pastedFiles(pasteboard).isEmpty || holdsImage(pasteboard)
    }

    private static func attachmentFiles(from pasteboard: NSPasteboard) -> [URL] {
        let files = pastedFiles(pasteboard)
        if !files.isEmpty { return files }
        guard holdsImage(pasteboard), let data = pngData(pasteboard) else { return [] }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeXMessagesPaste")
            .appendingPathComponent(UUID().uuidString)
        let target = folder.appendingPathComponent("Image.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: target)
            return [target]
        } catch {
            return []
        }
    }

    private static func pngData(_ pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) { return data }
        guard let tiff = NSImage(pasteboard: pasteboard)?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        for title in ["Font", "Paste and Match Style"] {
            if let item = menu?.item(withTitle: title) { menu?.removeItem(item) }
        }
        return menu
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var wide = rect
        wide.size.width = 2
        super.drawInsertionPoint(in: wide, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var grown = rect
        grown.size.width += 2
        super.setNeedsDisplay(grown, avoidAdditionalLayout: flag)
    }
}

final class WaveformIcon: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.5).setFill()
        let heights: [CGFloat] = [4.5, 8.5, 14.5, 8.5, 4.5]
        for (index, height) in heights.enumerated() {
            let x = bounds.midX + (CGFloat(index) - 2) * 3.75 - 0.75
            let rect = NSRect(x: x, y: bounds.midY - height / 2, width: 1.5, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 0.75, yRadius: 0.75).fill()
        }
    }
}

private func grinningFace() -> NSImage {
    let side: CGFloat = 16
    let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { bounds in
        NSColor.black.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        guard let context = NSGraphicsContext.current else { return true }
        context.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: NSRect(x: 4.3, y: 4.4, width: 2.2, height: 3.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 9.5, y: 4.4, width: 2.2, height: 3.2)).fill()
        let mouth = NSBezierPath()
        mouth.move(to: CGPoint(x: 3.4, y: 9))
        mouth.line(to: CGPoint(x: 12.6, y: 9))
        mouth.curve(to: CGPoint(x: 3.4, y: 9), controlPoint1: CGPoint(x: 12.2, y: 15), controlPoint2: CGPoint(x: 3.8, y: 15))
        mouth.close()
        mouth.fill()
        context.compositingOperation = .sourceOver
        NSRect(x: 4.2, y: 9.8, width: 7.6, height: 1.3).fill()
        return true
    }
    image.isTemplate = true
    return image
}

final class AttachmentThumbView: NSView {
    var onRemove: (() -> Void)?
    private let imageView = NSImageView()
    private let removeButton = NSButton()

    init(url: URL) {
        super.init(frame: NSRect(x: 0, y: 0, width: 58, height: 58))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        imageView.frame = bounds
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSWorkspace.shared.icon(forFile: url.path)
        addSubview(imageView)

        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove attachment")
        removeButton.isBordered = false
        removeButton.contentTintColor = .white
        removeButton.target = self
        removeButton.action = #selector(remove)
        removeButton.toolTip = "Remove \(url.lastPathComponent)"
        removeButton.frame = NSRect(x: 2, y: bounds.height - 20, width: 18, height: 18)
        addSubview(removeButton)

        ImageLoader.shared.image(url: url, size: CGSize(width: 116, height: 116)) { [weak self] image in
            if let image { self?.imageView.image = image }
        }
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    @objc private func remove() {
        onRemove?()
    }
}

final class ComposerPreviewView: FlippedView {
    private var string = NSAttributedString()
    private var textSize = CGSize.zero
    private var fill = Theme.blue
    private var hasError = false

    var preferredSize: CGSize {
        CGSize(width: textSize.width + Theme.horizontalPadding * 2 + Theme.tail, height: textSize.height + Theme.verticalPadding * 2 + (hasError ? 18 : 0))
    }

    func configure(_ text: String, isSMS: Bool, maxWidth: CGFloat) -> Bool {
        let segments = MathSegmenter.split(text)
        let mathCount = segments.filter { if case .math = $0 { return true } else { return false } }.count
        guard mathCount > 0 else { return false }
        let result = BubbleText.make(text, color: .white)
        let width = max(40, maxWidth - Theme.horizontalPadding * 2 - Theme.tail)
        result.cells.forEach { $0.fit(to: width) }
        string = result.string
        textSize = TextMeasure.size(result.string, maxWidth: width)
        textSize.height = max(textSize.height, 17)
        fill = isSMS ? Theme.green : Theme.blue
        hasError = result.cells.count < mathCount
        alphaValue = 0.92
        setAccessibilityElement(true)
        setAccessibilityLabel(hasError ? "Preview, contains LaTeX that can't be rendered" : "Preview of your message")
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bubble = CGSize(width: bounds.width, height: bounds.height - (hasError ? 18 : 0))
        fill.setFill()
        BubblePath.body(size: bubble, fromMe: true).fill()
        string.draw(with: NSRect(x: Theme.horizontalPadding, y: Theme.verticalPadding, width: textSize.width + 1, height: textSize.height + 1), options: [.usesLineFragmentOrigin])
        if hasError {
            let caption = NSAttributedString(string: "Check your LaTeX", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.systemRed])
            caption.draw(at: NSPoint(x: bounds.width - Theme.tail - caption.size().width - 4, y: bubble.height + 2))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ComposerView: NSView, NSTextViewDelegate {
    static let minimumHeight: CGFloat = 36

    var onSend: ((String, [URL]) -> Void)?
    var onHeightChange: (() -> Void)?
    var onTextChange: ((String) -> Void)?

    private let plusButton = NSButton()
    private let glass = NSGlassEffectView()
    private let fieldHost = FlippedView()
    private let scrollView = NSScrollView()
    private let textView = ComposerTextView(usingTextLayoutManager: false)
    private let emojiButton = NSButton()
    private let voiceIcon = WaveformIcon()
    private let attachmentStrip = FlippedView()
    private(set) var attachments: [URL] = []
    private var textHeight: CGFloat = 18

    override var isFlipped: Bool { true }

    var placeholder: String {
        get { textView.placeholder }
        set { textView.placeholder = newValue }
    }

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            recalculate()
        }
    }

    private var maximumHeight: CGFloat {
        min(max(150, (superview?.bounds.height ?? 600) * 0.45), 420)
    }

    var preferredHeight: CGFloat {
        min(max(Self.minimumHeight, textHeight + 15), maximumHeight) + (attachments.isEmpty ? 0 : 66)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)

        plusButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add attachment")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        plusButton.bezelStyle = .glass
        plusButton.borderShape = .circle
        plusButton.contentTintColor = .labelColor
        plusButton.target = self
        plusButton.action = #selector(pickFiles)
        plusButton.toolTip = "Add attachment"
        addSubview(plusButton)

        glass.cornerRadius = 18
        glass.applyMessagesStyle(tinted: false)
        glass.contentView = fieldHost
        addSubview(glass)

        textView.font = Theme.bodyFont
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = .width
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.delegate = self
        textView.onPasteFiles = { [weak self] files in self?.add(files: files) }
        textView.setAccessibilityLabel("Message")

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        fieldHost.addSubview(scrollView)

        emojiButton.image = grinningFace()
        emojiButton.setAccessibilityLabel("Emoji")
        emojiButton.bezelStyle = .glass
        emojiButton.borderShape = .circle
        emojiButton.contentTintColor = .labelColor
        emojiButton.target = self
        emojiButton.action = #selector(showEmoji)
        emojiButton.toolTip = "Emoji & Symbols"
        addSubview(emojiButton)

        voiceIcon.setAccessibilityLabel("Audio messages are not supported")
        voiceIcon.toolTip = "Audio messages are not supported"
        fieldHost.addSubview(voiceIcon)

        attachmentStrip.isHidden = true
        fieldHost.addSubview(attachmentStrip)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    func pillFrame(in view: NSView) -> NSRect {
        glass.convert(glass.bounds, to: view)
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }

    func add(files: [URL]) {
        attachments += files
        updateAttachmentLabel()
        recalculate()
        focus()
    }

    private func updateAttachmentLabel() {
        attachmentStrip.isHidden = attachments.isEmpty
        attachmentStrip.subviews.forEach { $0.removeFromSuperview() }
        for (index, url) in attachments.enumerated() {
            let thumb = AttachmentThumbView(url: url)
            thumb.frame.origin = NSPoint(x: CGFloat(index) * 64, y: 0)
            thumb.onRemove = { [weak self] in self?.removeAttachment(at: index) }
            attachmentStrip.addSubview(thumb)
        }
    }

    private func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
        updateAttachmentLabel()
        recalculate()
    }

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.add(files: panel.urls) }
        }
    }

    @objc private func showEmoji() {
        focus()
        NSApp.orderFrontCharacterPalette(nil)
    }

    func textDidChange(_ notification: Notification) {
        recalculate()
    }

    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true || NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            view.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        submit()
        return true
    }

    private func submit() {
        let body = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !attachments.isEmpty else { return }
        let files = attachments
        onSend?(body, files)
        textView.string = ""
        attachments = []
        updateAttachmentLabel()
        recalculate()
    }

    private func recalculate() {
        let font = BubbleText.jumboSize(textView.string).map { NSFont.systemFont(ofSize: $0) } ?? Theme.bodyFont
        if textView.font != font { textView.font = font }
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        textView.sizeToFit()
        let height = max(manager.usedRect(for: container).height, 17)
        let changed = height != textHeight
        textHeight = height
        if changed || bounds.height != preferredHeight {
            onHeightChange?()
        }
        textView.needsDisplay = true
        needsLayout = true
        onTextChange?(textView.string)
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        plusButton.frame = NSRect(x: 0, y: height - 33, width: 30, height: 30)
        emojiButton.frame = NSRect(x: bounds.width - 30, y: height - 33, width: 30, height: 30)
        glass.frame = NSRect(x: 40, y: 0, width: bounds.width - 80, height: height)
        let host = glass.bounds
        let top: CGFloat = attachments.isEmpty ? 0 : 66
        attachmentStrip.frame = NSRect(x: 12, y: 8, width: host.width - 24, height: 58)
        voiceIcon.frame = NSRect(x: host.width - 29.5, y: host.height - 28, width: 20, height: 20)
        scrollView.frame = NSRect(x: 12, y: top + 7.5, width: host.width - 48, height: max(21, host.height - top - 15))
        let width = scrollView.contentSize.width
        if textView.frame.width != width {
            textView.frame.size.width = width
            DispatchQueue.main.async { [weak self] in self?.recalculate() }
        }
        clampScroll()
    }

    private func clampScroll() {
        let clip = scrollView.contentView
        let limit = max(0, textView.frame.height - scrollView.contentSize.height)
        let y = min(max(clip.bounds.minY, 0), limit)
        guard y != clip.bounds.minY else { return }
        clip.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}
