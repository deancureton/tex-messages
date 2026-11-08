import AppKit

final class PinnedRingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Theme.selection.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        path.lineWidth = 2
        path.stroke()
    }
}

final class PinnedBubbleTail: NSView {
    static let fill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.237, green: 0.237, blue: 0.237, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    }

    var pointsUp = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.line(to: CGPoint(x: 0, y: h * 0.62))
        path.curve(to: CGPoint(x: w * 0.16, y: h), controlPoint1: CGPoint(x: 0, y: h * 0.86), controlPoint2: CGPoint(x: w * 0.07, y: h))
        path.curve(to: CGPoint(x: w, y: 0), controlPoint1: CGPoint(x: w * 0.42, y: h), controlPoint2: CGPoint(x: w * 0.78, y: h * 0.32))
        path.close()
        if pointsUp {
            var flip = AffineTransform(translationByX: 0, byY: h)
            flip.scale(x: 1, y: -1)
            path.transform(using: flip)
        }
        Self.fill.setFill()
        path.fill()
    }
}

final class PinnedBubbleText: FlippedView {
    static let limit: CGFloat = 90

    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: PinnedBubbleText.limit, height: .greatestFiniteMagnitude))

    var scale: CGFloat = 1 { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 2
        container.lineBreakMode = .byTruncatingTail
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    func setText(_ text: NSAttributedString) {
        storage.setAttributedString(text)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: .zero)
    }
}

final class PinnedItemView: FlippedView {
    private static let avatarSize: CGFloat = 73

    private let selection = PillView()
    private let avatar = AvatarView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let dot = PillView()
    private let bubble = FlippedView()
    private let bubbleFill = PillView()
    private let bubbleTail = PinnedBubbleTail()
    private let bubbleText = PinnedBubbleText()
    private(set) var hasBubble = false
    private var bubbleScale: CGFloat = 1
    private var bubbleBelow = false
    private var bubbleTextSize = CGSize.zero
    private let ring = PinnedRingView()
    private var closeObserver: MenuCloseObserver?

    var conversation: Conversation?
    var onClick: ((Conversation) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        selection.radius = 12
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        dot.fill = Theme.blue
        dot.radius = 4.5
        bubbleFill.fill = PinnedBubbleTail.fill
        bubbleFill.radius = 12
        bubble.wantsLayer = true
        bubble.layer?.shadowColor = NSColor.black.cgColor
        bubble.layer?.shadowOpacity = 0.28
        bubble.layer?.shadowRadius = 5
        bubble.layer?.shadowOffset = CGSize(width: 0, height: -2)
        ring.isHidden = true
        avatar.wantsLayer = true
        for view in [selection, avatar, nameLabel, dot, bubbleTail, bubble, ring] as [NSView] { addSubview(view) }
        bubble.addSubview(bubbleFill)
        bubble.addSubview(bubbleText)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let conversation else { return nil }
        let menu = ContextMenus.conversation(conversation, pinned: true)
        ring.isHidden = false
        let observer = MenuCloseObserver { [weak self] in self?.ring.isHidden = true }
        closeObserver = observer
        menu.delegate = observer
        return menu
    }

    override func mouseUp(with event: NSEvent) {
        if let conversation { onClick?(conversation) }
    }

    func configure(_ conversation: Conversation, selected: Bool, focused: Bool) {
        self.conversation = conversation
        avatar.configure(handles: conversation.avatarHandles, photo: conversation.groupPhotoURL)
        nameLabel.stringValue = conversation.headerTitle
        selection.isHidden = !selected
        selection.fill = focused ? Theme.selection : NSColor.labelColor.withAlphaComponent(0.12)
        selection.needsDisplay = true
        nameLabel.textColor = selected && focused ? .white : .secondaryLabelColor
        dot.isHidden = conversation.unreadCount == 0
        dot.fill = selected && focused ? .white : Theme.blue
        dot.needsDisplay = true
        hasBubble = conversation.unreadCount > 0 && !conversation.preview.isEmpty
        bubble.isHidden = !hasBubble
        bubbleTail.isHidden = !hasBubble
        applyGlow(conversation)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Pinned, \(conversation.title)\(conversation.unreadCount > 0 ? ", unread" : "")")
        needsLayout = true
    }

    func placeBubble(scale: CGFloat, below: Bool) {
        guard let conversation else { return }
        bubbleScale = scale
        bubbleBelow = below
        bubbleTail.pointsUp = below
        bubbleFill.radius = 12 * scale
        bubbleFill.needsDisplay = true
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = 11
        style.maximumLineHeight = 11
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = []
        let text = NSAttributedString(string: conversation.preview, attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ])
        bubbleText.setText(text)
        bubbleText.scale = scale
        bubbleTextSize = Self.measure(text, width: PinnedBubbleText.limit)
        needsLayout = true
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        let leading = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: leading.length)
        if let style = leading.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
           let copy = style.mutableCopy() as? NSMutableParagraphStyle {
            copy.alignment = .left
            leading.addAttribute(.paragraphStyle, value: copy, range: range)
        }
        let storage = NSTextStorage(attributedString: leading)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 2
        container.lineBreakMode = .byTruncatingTail
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).size
        return CGSize(width: ceil(used.width * 2) / 2, height: used.height)
    }

    private func applyGlow(_ conversation: Conversation) {
        guard let layer = avatar.layer else { return }
        var color: CGColor?
        if !conversation.isGroup, let handle = conversation.participants.first,
           let person = Contacts.shared.person(for: handle), let image = Contacts.shared.image(for: person) {
            color = Self.averageColor(image)
        }
        layer.shadowColor = color ?? NSColor.gray.cgColor
        layer.shadowOpacity = color == nil ? 0 : 0.55
        layer.shadowRadius = 13
        layer.shadowOffset = .zero
    }

    private static func averageColor(_ image: NSImage) -> CGColor? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: 0, y: 0)?.cgColor
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let side = Self.avatarSize
        selection.frame = bounds.insetBy(dx: 2, dy: 2)
        ring.frame = bounds.insetBy(dx: 2, dy: 2)
        avatar.frame = NSRect(x: round((width - side) / 2), y: 10, width: side, height: side)
        avatar.layer?.shadowPath = CGPath(ellipseIn: avatar.bounds, transform: nil)
        let textWidth = ceil(nameLabel.attributedStringValue.size().width)
        nameLabel.frame = NSRect(x: 8, y: 89, width: max(0, width - 16), height: 16)
        dot.frame = NSRect(x: max(2, (width - min(textWidth, width - 16)) / 2 - 12.3), y: 91.5, width: 9, height: 9)
        if hasBubble {
            let scale = bubbleScale
            let bubbleWidth = (bubbleTextSize.width + 16) * scale
            let bubbleHeight = (bubbleTextSize.height + 11.5) * scale
            let tipX = avatar.frame.midX + 0.2875 * bubbleWidth / scale
            let lowest = 8 - frame.minX
            let highest = (superview?.bounds.width ?? width) - 8 - frame.minX - bubbleWidth
            let x = max(lowest, min(tipX - 0.7875 * bubbleWidth, highest))
            let y = bubbleBelow ? avatar.frame.midY + 3.5 + 5 * scale : avatar.frame.midY - 1.8 - 5.7 * scale - bubbleHeight
            bubble.frame = NSRect(x: x, y: y, width: bubbleWidth, height: bubbleHeight)
            bubbleFill.frame = bubble.bounds
            bubble.layer?.shadowPath = CGPath(roundedRect: bubble.bounds, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)
            let textWidth = PinnedBubbleText.limit * scale
            let textHeight = bubbleTextSize.height * scale
            bubbleText.frame = NSRect(x: (bubbleWidth - textWidth) / 2, y: (bubbleHeight - textHeight) / 2, width: textWidth, height: textHeight)
            bubbleTail.frame = NSRect(x: x + 0.785 * bubbleWidth - 1.25 * scale, y: bubbleBelow ? y - 5.2 * scale : y + bubbleHeight - 0.5 * scale, width: 9.5 * scale, height: 5.7 * scale)
        }
    }
}

final class PinnedGridView: FlippedView {
    private static let columns = 3
    private static let rowHeight: CGFloat = 112
    private static let bubbleScales: [CGFloat] = [1, 0.8, 0.75]

    private var items: [PinnedItemView] = []
    var onSelect: ((Conversation) -> Void)?

    func height(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat((count - 1) / Self.columns + 1) * Self.rowHeight
    }

    func update(_ pins: [Conversation], selectedKey: String?, focused: Bool) {
        while items.count > pins.count { items.removeLast().removeFromSuperview() }
        while items.count < pins.count {
            let item = PinnedItemView()
            item.onClick = { [weak self] conversation in self?.onSelect?(conversation) }
            items.append(item)
            addSubview(item)
        }
        for (item, pin) in zip(items, pins) {
            item.configure(pin, selected: pin.key == selectedKey, focused: focused)
        }
        for start in stride(from: 0, to: items.count, by: Self.columns) {
            let row = Array(items[start..<min(start + Self.columns, items.count)])
            let unread = row.filter(\.hasBubble)
            for (rank, item) in unread.enumerated() {
                item.placeBubble(scale: Self.bubbleScales[rank], below: unread.count > 1 && row.count > 1 && item === row[1])
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let cell = (bounds.width - 10) / CGFloat(Self.columns)
        for (index, item) in items.enumerated() {
            item.frame = NSRect(
                x: 5 + CGFloat(index % Self.columns) * cell,
                y: CGFloat(index / Self.columns) * Self.rowHeight,
                width: cell,
                height: Self.rowHeight
            )
        }
    }
}

final class LinkCardView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var imageHeight: CGFloat = 0
    var fill: NSColor = Theme.incoming
    var footer = NSAttributedString()
    var url: URL?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 17.5, yRadius: 17.5).addClip()
        fill.setFill()
        bounds.fill()
        if imageHeight > 0 {
            let rect = NSRect(x: 0, y: 0, width: bounds.width, height: imageHeight)
            if let image {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            } else {
                NSColor.quaternaryLabelColor.setFill()
                rect.fill()
            }
        }
        footer.draw(with: NSRect(x: 12, y: imageHeight + 8, width: bounds.width - 24, height: bounds.height - imageHeight - 12), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseUp(with event: NSEvent) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }
}
