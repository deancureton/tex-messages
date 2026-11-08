import AppKit
import ImageIO

final class BubbleTextView: NSTextView {
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        let target = range.length > 0 ? range : NSRange(location: 0, length: storage.length)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BubbleText.plainSource(storage.attributedSubstring(from: target)), forType: .string)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        var ancestor = superview
        while let view = ancestor {
            if let row = view as? BubbleRowView { return row.menu(for: event) }
            ancestor = view.superview
        }
        return nil
    }

    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: 0, length: 0))
        return super.resignFirstResponder()
    }
}

final class BubbleShapeView: NSView {
    var fill: NSColor?
    var tail = false
    var fromMe = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let fill else { return }
        fill.setFill()
        let size = CGSize(width: bounds.width, height: bounds.height - (tail ? BubblePath.tailDrop : 0))
        BubblePath.body(size: size, fromMe: fromMe).fill()
        if tail { BubblePath.tail(size: size, fromMe: fromMe).fill() }
    }
}

final class BubbleImageView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var tail = false
    var fromMe = false
    var clips = true
    var isVideo = false
    var url: URL?
    private(set) var showingFrames = false
    private let frameLayer = CALayer()
    private var animationSource: URL?
    private var sourceIsAnimated = false
    private var playback: UUID?
    private var occlusionObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    func setAnimation(_ source: URL?) {
        guard source != animationSource else { return }
        animationSource = source
        sourceIsAnimated = false
        playback = nil
        if showingFrames {
            showingFrames = false
            frameLayer.contents = nil
            frameLayer.isHidden = true
            needsDisplay = true
        }
        guard let source else { return }
        ImageLoader.shared.isAnimated(source) { [weak self] animated in
            guard let self, self.animationSource == source, animated else { return }
            self.sourceIsAnimated = true
            self.updatePlayback()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                self?.updatePlayback()
            }
        }
        updatePlayback()
    }

    private func updatePlayback() {
        let visible = window?.occlusionState.contains(.visible) == true
        guard sourceIsAnimated, visible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let source = animationSource else {
            playback = nil
            return
        }
        guard playback == nil else { return }
        if frameLayer.superlayer == nil {
            wantsLayer = true
            frameLayer.isHidden = true
            layer?.addSublayer(frameLayer)
            needsLayout = true
        }
        let token = UUID()
        playback = token
        let status = CGAnimateImageAtURLWithBlock(source as CFURL, nil) { [weak self] _, frame, stop in
            guard let self, self.playback == token else {
                stop.pointee = true
                return
            }
            self.show(frame)
        }
        if status != noErr { playback = nil }
    }

    private func show(_ frame: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.contents = frame
        frameLayer.isHidden = false
        CATransaction.commit()
        if !showingFrames {
            showingFrames = true
            needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        guard frameLayer.superlayer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.frame = bounds
        if clips {
            let mask = frameLayer.mask as? CAShapeLayer ?? CAShapeLayer()
            mask.path = BubblePath.body(size: bounds.size, fromMe: fromMe).cgPath
            frameLayer.mask = mask
        } else {
            frameLayer.mask = nil
        }
        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        if clips { BubblePath.body(size: bounds.size, fromMe: fromMe).addClip() }
        if showingFrames {
        } else if let image {
            let rect = clips ? NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height) : bounds
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        } else if clips {
            NSColor.quaternaryLabelColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if isVideo, let play = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Play")?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .regular).applying(.init(hierarchicalColor: .white))) {
            let size = play.size
            play.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 0.9, respectFlipped: true, hints: nil)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2, let url { NSWorkspace.shared.open(url) }
    }
}

final class TapbackView: NSView {
    static let tailRoom: CGFloat = 18

    var tapbacks: [Tapback] = [] { didSet { needsDisplay = true } }
    var mirrored = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    static func width(count: Int) -> CGFloat { 28 + CGFloat(max(0, min(count, 3) - 1)) * 16 }

    override func draw(_ dirtyRect: NSRect) {
        let origin = mirrored ? Self.tailRoom : 0
        for (index, tapback) in tapbacks.prefix(3).enumerated() {
            let rect = NSRect(x: origin + CGFloat(index) * 16, y: 0, width: 28, height: 28)
            let tint: NSColor = tapback.isFromMe ? Theme.blue : Theme.incoming
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)).fill()
            tint.setFill()
            NSBezierPath(ovalIn: rect).fill()
            if index == 0 {
                let direction: CGFloat = mirrored ? -1 : 1
                let center = CGPoint(x: rect.midX, y: rect.midY)
                NSBezierPath(ovalIn: NSRect(x: center.x + direction * 10 - 3.5, y: center.y + 10 - 3.5, width: 7, height: 7)).fill()
                NSBezierPath(ovalIn: NSRect(x: center.x + direction * 15 - 1.75, y: center.y + 18 - 1.75, width: 3.5, height: 3.5)).fill()
            }
            drawGlyph(tapback, in: rect, color: tapback.isFromMe ? .white : .secondaryLabelColor)
        }
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static let styles: [Int64: (symbol: String?, top: UInt32, bottom: UInt32, size: CGFloat)] = [
        2000: ("heart.fill", 0xFF7DB8, 0xFF2D78, 14),
        2001: ("hand.thumbsup.fill", 0xFFD84D, 0xFFA61F, 14),
        2002: ("hand.thumbsdown.fill", 0xFFB84D, 0xF2780A, 14),
        2003: (nil, 0xFFFFFF, 0xFFFFFF, 8.5),
        2004: ("exclamationmark.2", 0xFF7A70, 0xE5263A, 15),
        2005: ("questionmark", 0x9C9AFF, 0x5E5CE6, 15),
    ];

    private func drawGlyph(_ tapback: Tapback, in rect: NSRect, color: NSColor) {
        guard let style = Self.styles[tapback.type] else {
            let string = NSAttributedString(string: tapback.emoji ?? "🙂", attributes: [.font: NSFont.systemFont(ofSize: 15)])
            let size = string.size()
            string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return
        }
        let haColors: (UInt32, UInt32) = tapback.isFromMe ? (0xFFFFFF, 0xFFFFFF) : (0xE4E4E8, 0xC4C4CA)
        let top = tapback.type == 2003 ? haColors.0 : style.top
        let bottom = tapback.type == 2003 ? haColors.1 : style.bottom
        guard let mask = mask(for: style.symbol, size: style.size),
              let gradient = NSGradient(starting: Self.srgb(top), ending: Self.srgb(bottom)) else { return }
        let size = mask.size
        let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        let tinted = NSImage(size: size, flipped: true) { bounds in
            gradient.draw(in: bounds, angle: 90)
            mask.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func roundedBlack(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .black)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    private func mask(for symbol: String?, size: CGFloat) -> NSImage? {
        if let symbol {
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .bold))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.maximumLineHeight = size
        paragraph.minimumLineHeight = size
        let string = NSAttributedString(string: "HA\nHA", attributes: [.font: Self.roundedBlack(size), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        let textSize = CGSize(width: ceil(string.size().width), height: size * 2 + 1)
        return NSImage(size: textSize, flipped: false) { bounds in
            string.draw(in: bounds)
            return true
        }
    }
}

final class ReplyQuoteView: NSView {
    static let tailRoom: CGFloat = 6

    var text = "" { didSet { needsDisplay = true } }
    var originalFromMe = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = originalFromMe ? Theme.selection : .secondaryLabelColor
        let stroke = color.withAlphaComponent(originalFromMe ? 0.55 : 0.22)
        let body = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.tailRoom)
        let outline = Self.outline(width: body.width - 1, height: body.height - 1, originalFromMe: originalFromMe)
        NSColor.windowBackgroundColor.setFill()
        outline.fill()
        stroke.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        NSAttributedString(string: text, attributes: [.font: Theme.quoteFont, .paragraphStyle: Theme.quoteParagraph, .foregroundColor: color])
            .draw(with: NSRect(x: 8, y: 5, width: body.width - 16, height: body.height - 7), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private static func outline(width w: CGFloat, height h: CGFloat, originalFromMe: Bool) -> NSBezierPath {
        let r = min(13, h / 2)
        let k = r * 0.5523
        let joinX = r * 0.338
        let joinY = h - r * 0.25
        let handle = r * 0.287
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x + 0.5, y: y + 0.5) }
        let path = NSBezierPath()
        path.move(to: p(r, 0))
        path.line(to: p(w - r, 0))
        path.curve(to: p(w, r), controlPoint1: p(w - r + k, 0), controlPoint2: p(w, r - k))
        path.line(to: p(w, h - r))
        path.curve(to: p(w - r, h), controlPoint1: p(w, h - r + k), controlPoint2: p(w - r + k, h))
        path.line(to: p(14, h))
        path.curve(to: p(6, h + 4.75), controlPoint1: p(11.5, h + 1.9), controlPoint2: p(8.6, h + 3.9))
        path.curve(to: p(5.25, h + 4), controlPoint1: p(5.6, h + 5), controlPoint2: p(5, h + 4.5))
        path.curve(to: p(7, h - 0.75), controlPoint1: p(6.3, h + 2.9), controlPoint2: p(7.3, h + 1.1))
        path.curve(to: p(joinX, joinY), controlPoint1: p(6.7, h - 1.9), controlPoint2: p(joinX + 1.2, joinY + 0.9))
        path.curve(to: p(0, h - r), controlPoint1: p(joinX - 0.75 * handle, joinY - 0.66 * handle), controlPoint2: p(0, h - r + handle))
        path.line(to: p(0, r))
        path.curve(to: p(r, 0), controlPoint1: p(0, r - k), controlPoint2: p(r - k, 0))
        path.close()
        if originalFromMe {
            var flip = AffineTransform(translationByX: w + 1, byY: 0)
            flip.scale(x: -1, y: 1)
            path.transform(using: flip)
        }
        return path
    }
}

final class ReplyBracketView: NSView {
    var hooksBottom = false { didSet { needsDisplay = true } }
    var straight = false { didSet { needsDisplay = true } }
    var continuesUp = false { didSet { needsDisplay = true } }
    var continuesDown = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        if straight {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: bounds.midX, y: continuesUp ? 0 : 1.5))
            line.line(to: CGPoint(x: bounds.midX, y: continuesDown ? bounds.height : max(1.5, bounds.height - 1.5)))
            line.lineWidth = 3
            line.lineCapStyle = .round
            NSColor.labelColor.withAlphaComponent(0.16).setStroke()
            line.stroke()
            return
        }
        let x: CGFloat = 1
        let right = bounds.width
        let radius: CGFloat = 14
        let top: CGFloat = 1
        let bottom = bounds.height - 1
        let path = NSBezierPath()
        path.move(to: CGPoint(x: right, y: top))
        path.line(to: CGPoint(x: x + radius, y: top))
        path.curve(to: CGPoint(x: x, y: top + radius), controlPoint1: CGPoint(x: x + radius * 0.45, y: top), controlPoint2: CGPoint(x: x, y: top + radius * 0.45))
        if hooksBottom {
            path.line(to: CGPoint(x: x, y: bottom - radius))
            path.curve(to: CGPoint(x: x + radius, y: bottom), controlPoint1: CGPoint(x: x, y: bottom - radius * 0.45), controlPoint2: CGPoint(x: x + radius * 0.45, y: bottom))
            path.line(to: CGPoint(x: right, y: bottom))
        } else {
            path.line(to: CGPoint(x: x, y: bottom))
        }
        path.lineWidth = 2
        path.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.16).setStroke()
        path.stroke()
    }
}

final class BubbleRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("bubble")

    private let shape = BubbleShapeView()
    private let textView = BubbleTextView(usingTextLayoutManager: false)
    private let imageBubble = BubbleImageView()
    private let fileIcon = NSImageView()
    private let fileName = NSTextField(labelWithString: "")
    private let fileDetail = NSTextField(labelWithString: "")
    private let senderLabel = NSTextField(labelWithString: "")
    private let replyQuote = ReplyQuoteView()
    private let replyAvatar = AvatarView()
    private let replyBracket = ReplyBracketView()
    private let quoteCountLabel = NSTextField(labelWithString: "")
    private let repliesLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "")
    private let avatar = AvatarView()
    private let tapbackView = TapbackView()
    private let saveButton = NSButton()
    private let linkCard = LinkCardView()
    private let voiceView = VoiceMessageView()
    private let inkHost = InkHostView()
    private var inkTracking: NSTrackingArea?
    private var isInk = false
    private var concealWork: DispatchWorkItem?
    var onReplay: (() -> Void)?
    var menuContext: MenuContext?
    private let timeLabel = NSTextField(labelWithString: "")
    private var model: BubbleModel?
    private var fileURL: URL?
    private var loadToken = UUID()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        wantsLayer = true
        clipsToBounds = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticLinkDetectionEnabled = false

        senderLabel.font = .systemFont(ofSize: 14.75)
        senderLabel.textColor = .secondaryLabelColor
        repliesLabel.font = .systemFont(ofSize: 15, weight: .medium)
        repliesLabel.textColor = Theme.selection
        quoteCountLabel.font = .systemFont(ofSize: 15, weight: .medium)
        quoteCountLabel.textColor = Theme.selection
        footerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        fileName.font = .systemFont(ofSize: 13, weight: .medium)
        fileName.lineBreakMode = .byTruncatingMiddle
        fileDetail.font = .systemFont(ofSize: 11)
        fileIcon.imageScaling = .scaleProportionallyUpOrDown

        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save to Downloads")
        saveButton.bezelStyle = .glass
        saveButton.borderShape = .circle
        saveButton.contentTintColor = .labelColor
        saveButton.target = self
        saveButton.action = #selector(saveAttachment)
        saveButton.toolTip = "Save to Downloads"
        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.alignment = .right
        for view in [shape, imageBubble, linkCard, senderLabel, replyBracket, replyAvatar, replyQuote, quoteCountLabel, repliesLabel, footerLabel, avatar, tapbackView, saveButton, timeLabel] as [NSView] { addSubview(view) }
        for view in [textView, fileIcon, fileName, fileDetail, voiceView, inkHost] as [NSView] { shape.addSubview(view) }
        inkHost.isHidden = true
        footerLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(replayEffect)))
        shape.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openFile)))
        (shape.gestureRecognizers.first as? NSClickGestureRecognizer)?.numberOfClicksRequired = 2
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    @objc private func saveAttachment() {
        guard let source = imageBubble.url,
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let stem = source.deletingPathExtension().lastPathComponent
        let suffix = source.pathExtension
        var target = downloads.appendingPathComponent(source.lastPathComponent)
        var attempt = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = downloads.appendingPathComponent("\(stem) \(attempt)").appendingPathExtension(suffix)
            attempt += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            NSSound.beep()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard bubbleBodyFrame.insetBy(dx: -2, dy: -2).contains(point) || imageBubble.frame.contains(point) else {
            return ContextMenus.background(menuContext)
        }

        let menu = ContextMenus.menu()
        let details: (() -> Void)? = model.tapbacks.isEmpty ? nil : { [weak self] in
            guard let self else { return }
            self.menuContext?.tapbackDetails(model.tapbacks, self, point)
        }
        ContextMenus.messageHeader(menu, tapbackDetails: details)
        switch model.content {
        case .text(let result, _):
            let selection = textView.selectedRange()
            let storage = textView.textStorage
            ContextMenus.add(menu, "Copy") {
                let source = selection.length > 0 ? storage?.attributedSubstring(from: selection) ?? result.string : result.string
                ContextMenus.copy(BubbleText.plainSource(source))
            }
            menu.addItem(.separator())
            ContextMenus.add(menu, "Share\u{2026}", symbol: "square.and.arrow.up") { [weak self] in
                guard let self else { return }
                ContextMenus.share([BubbleText.plainSource(result.string)], from: self, at: point)
            }
        case .image(let url, _, _), .video(let url):
            var isVideo = false
            if case .video = model.content { isVideo = true }
            ContextMenus.add(menu, "Quick Look") { QuickLookController.shared.show(url) }
            ContextMenus.add(menu, "Open") { NSWorkspace.shared.open(url) }
            ContextMenus.add(menu, "Copy") { ContextMenus.copyFile(url) }
            menu.addItem(.separator())
            ContextMenus.add(menu, "Share\u{2026}", symbol: "square.and.arrow.up") { [weak self] in
                guard let self else { return }
                ContextMenus.share([url], from: self, at: point)
            }
            ContextMenus.add(menu, "Add to Photos Library") { ContextMenus.addToPhotos(url, isVideo: isVideo) }
            menu.addItem(.separator())
            if isVideo {
                ContextMenus.add(menu, "Set as Background")
            } else {
                ContextMenus.add(menu, "Set as Background") { [weak self] in self?.menuContext?.setBackground(url) }
            }
        case .voice(let url):
            addFileItems(menu, url, point)
        case .file(_, _, let url, _):
            if let url {
                addFileItems(menu, url, point)
            } else {
                ContextMenus.add(menu, "Copy")
            }
        case .link(let card, _, _, _, _):
            if let link = card.url {
                ContextMenus.add(menu, "Copy") { ContextMenus.copy(link.absoluteString) }
                menu.addItem(.separator())
                ContextMenus.add(menu, "Share\u{2026}", symbol: "square.and.arrow.up") { [weak self] in
                    guard let self else { return }
                    ContextMenus.share([link], from: self, at: point)
                }
            } else {
                ContextMenus.add(menu, "Copy")
            }
            menu.addItem(.separator())
            ContextMenus.add(menu, "Pin")
        }
        menu.addItem(.separator())
        ContextMenus.add(menu, "Delete\u{2026}")
        return menu
    }

    private func addFileItems(_ menu: NSMenu, _ url: URL, _ point: NSPoint) {
        ContextMenus.add(menu, "Quick Look") { QuickLookController.shared.show(url) }
        ContextMenus.add(menu, "Open") { NSWorkspace.shared.open(url) }
        ContextMenus.add(menu, "Copy") { ContextMenus.copyFile(url) }
        menu.addItem(.separator())
        ContextMenus.add(menu, "Share\u{2026}", symbol: "square.and.arrow.up") { [weak self] in
            guard let self else { return }
            ContextMenus.share([url], from: self, at: point)
        }
    }

    @objc private func replayEffect() {
        onReplay?()
    }

    var bubbleBodyFrame: NSRect { shape.isHidden ? imageBubble.frame : shape.frame }

    func bubbleSnapshot() -> (image: NSImage, frame: NSRect)? {
        let source: NSView = !shape.isHidden ? shape : (!imageBubble.isHidden ? imageBubble : linkCard)
        guard !source.isHidden, let rep = source.bitmapImageRepForCachingDisplay(in: source.bounds) else { return nil }
        source.cacheDisplay(in: source.bounds, to: rep)
        let image = NSImage(size: source.bounds.size)
        image.addRepresentation(rep)
        return (image, source.convert(source.bounds, to: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInk else { return }
        concealWork?.cancel()
        setInkRevealed(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isInk else { return }
        let work = DispatchWorkItem { [weak self] in self?.setInkRevealed(false) }
        concealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func setInkRevealed(_ revealed: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            textView.animator().alphaValue = revealed ? 1 : 0
            inkHost.animator().alphaValue = revealed ? 0 : 1
        }
    }

    private func resetInk() {
        concealWork?.cancel()
        if let inkTracking { removeTrackingArea(inkTracking) }
        inkTracking = nil
        isInk = false
        inkHost.isHidden = true
        inkHost.alphaValue = 1
        textView.alphaValue = 1
    }

    @objc private func openFile() {
        if let fileURL { NSWorkspace.shared.open(fileURL) }
    }

    var bubbleFrame: NSRect { imageBubble.frame }

    func textSnapshot() -> (image: NSImage, frame: NSRect)? {
        guard !textView.isHidden, let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return nil }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        let image = NSImage(size: textView.bounds.size)
        image.addRepresentation(rep)
        return (image, textView.convert(textView.bounds, to: self))
    }

    func fadeInFooter() {
        footerLabel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            footerLabel.animator().alphaValue = 1
        }
    }

    func configure(_ model: BubbleModel) {
        footerLabel.alphaValue = 1
        self.model = model
        loadToken = UUID()
        let token = loadToken
        resetInk()
        isInk = model.effect == .invisibleInk

        senderLabel.isHidden = model.sender == nil
        senderLabel.stringValue = model.sender ?? ""
        replyQuote.isHidden = model.reply == nil
        replyQuote.text = model.reply?.text ?? ""
        replyQuote.originalFromMe = model.reply?.isFromMe ?? false
        replyBracket.isHidden = model.reply == nil && !model.threadLine
        replyBracket.hooksBottom = model.fromMe
        replyBracket.straight = model.threadLine
        replyBracket.continuesUp = model.threadAbove
        replyBracket.continuesDown = model.threadBelow
        replyAvatar.isHidden = !model.threadLine || model.reply == nil
        if model.threadLine, let handle = model.reply?.handle { replyAvatar.configure(handles: [handle]) }
        quoteCountLabel.isHidden = model.reply == nil || model.quoteCount < 2
        quoteCountLabel.stringValue = "\(model.quoteCount) Replies"
        repliesLabel.isHidden = model.replyCount == 0
        repliesLabel.stringValue = model.replyCount == 1 ? "1 Reply" : "\(model.replyCount) Replies"
        footerLabel.isHidden = model.footer == nil
        footerLabel.stringValue = model.footer ?? ""
        footerLabel.textColor = model.footerIsError ? .systemRed : .secondaryLabelColor
        avatar.isHidden = model.avatarHandle == nil
        avatar.configure(handles: model.avatarHandle.map { [$0] } ?? [])
        tapbackView.isHidden = model.tapbacks.isEmpty
        tapbackView.tapbacks = model.tapbacks

        shape.fill = model.fill
        shape.tail = model.hasTail
        shape.fromMe = model.fromMe
        shape.needsDisplay = true
        imageBubble.tail = model.hasTail
        imageBubble.fromMe = model.fromMe

        textView.isHidden = true
        imageBubble.isHidden = true
        if case .image(let source, _, _) = model.content { imageBubble.setAnimation(source) } else { imageBubble.setAnimation(nil) }
        saveButton.isHidden = true
        linkCard.isHidden = true
        fileIcon.isHidden = true
        fileName.isHidden = true
        fileDetail.isHidden = true
        voiceView.isHidden = true
        fileURL = nil
        shape.isHidden = false

        switch model.content {
        case .text(let result, _):
            textView.isHidden = false
            textView.textStorage?.setAttributedString(result.string)
            textView.linkTextAttributes = [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: model.textColor,
                .cursor: NSCursor.pointingHand,
            ]
            textView.selectedTextAttributes = [
                .backgroundColor: model.fromMe ? NSColor.white.withAlphaComponent(0.35) : NSColor.selectedTextBackgroundColor,
            ]
            textView.setAccessibilityLabel(model.spoken)
            if isInk {
                textView.alphaValue = 0
                inkHost.isHidden = false
            }
        case .image(let url, _, let sticker):
            shape.isHidden = true
            imageBubble.isHidden = false
            imageBubble.clips = !sticker
            saveButton.isHidden = model.fromMe || sticker
            imageBubble.isVideo = false
            imageBubble.url = url
            imageBubble.image = nil
            imageBubble.setAccessibilityLabel(model.spoken)
            ImageLoader.shared.image(url: url, size: model.contentSize) { [weak self] image in
                guard self?.loadToken == token else { return }
                self?.imageBubble.image = image
            }
        case .video(let url):
            shape.isHidden = true
            imageBubble.isHidden = false
            imageBubble.clips = true
            imageBubble.isVideo = true
            saveButton.isHidden = model.fromMe
            imageBubble.url = url
            imageBubble.image = nil
            imageBubble.setAccessibilityLabel(model.spoken)
            ImageLoader.shared.poster(url: url, size: model.contentSize) { [weak self] image in
                guard self?.loadToken == token else { return }
                self?.imageBubble.image = image
            }
        case .voice(let url):
            voiceView.isHidden = false
            voiceView.configure(url: url, color: model.textColor)
            setAccessibilityLabel(model.spoken)
        case .link(let card, let image, _, let footer, let fill):
            shape.isHidden = true
            linkCard.isHidden = false
            linkCard.fill = fill
            linkCard.footer = footer
            linkCard.url = card.url
            linkCard.image = nil
            linkCard.setAccessibilityLabel(model.spoken)
            if case .link(_, _, let pixels, _, _) = model.content, let pixels {
                linkCard.imageHeight = min(round(model.contentSize.width * pixels.height / max(pixels.width, 1)), 320)
            } else {
                linkCard.imageHeight = 0
            }
            if let image {
                ImageLoader.shared.image(url: image, size: CGSize(width: model.contentSize.width, height: linkCard.imageHeight)) { [weak self] loaded in
                    guard self?.loadToken == token else { return }
                    self?.linkCard.image = loaded
                }
            }
        case .file(let name, let detail, let url, let symbol):
            fileIcon.isHidden = false
            fileName.isHidden = false
            fileDetail.isHidden = false
            fileName.stringValue = name
            fileDetail.stringValue = detail
            fileName.textColor = model.textColor
            fileDetail.textColor = model.textColor.withAlphaComponent(0.75)
            fileURL = url
            if let symbol {
                fileIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                fileIcon.contentTintColor = model.textColor
            } else if let url {
                fileIcon.image = NSWorkspace.shared.icon(forFile: url.path)
                fileIcon.contentTintColor = nil
            }
            setAccessibilityLabel(model.spoken)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let model else { return }
        let total = model.totalSize
        let width = bounds.width
        let leading = Theme.sideMargin + (model.reservesAvatar ? Theme.avatarGutter : 0)
        let timesVisible = menuContext?.showTimes == true
        let timeGutter: CGFloat = timesVisible ? 66 : 0
        let x = model.fromMe ? width - Theme.sideMargin - total.width - timeGutter : leading
        timeLabel.isHidden = !timesVisible
        timeLabel.stringValue = model.time
        var y = model.topGap

        var quoteFrame = NSRect.zero
        if let reply = model.reply {
            let size = model.quoteSize
            let quoteX = reply.isFromMe ? width - Theme.sideMargin - Theme.tail - size.width - timeGutter : leading + Theme.tail
            quoteFrame = NSRect(x: quoteX, y: y, width: size.width, height: size.height + ReplyQuoteView.tailRoom)
            replyQuote.frame = quoteFrame
            replyAvatar.frame = NSRect(x: 25, y: y + size.height + 4.75 - 18, width: 18, height: 18)
            if model.quoteCount > 1 {
                quoteCountLabel.alignment = reply.isFromMe ? .right : .left
                let labelX = reply.isFromMe ? width - Theme.sideMargin - Theme.tail - 16 - 200 - timeGutter : leading + Theme.tail + 10
                quoteCountLabel.frame = NSRect(x: labelX, y: y + size.height + 5, width: 200, height: 18)
            }
            y += model.quoteBlock
        }
        if model.sender != nil {
            senderLabel.frame = NSRect(x: x + Theme.tail + Theme.horizontalPadding - 2, y: y - 1, width: 300, height: 18)
            y += 20
        }
        y += model.overhang

        let bubbleFrame = NSRect(x: x, y: y, width: total.width, height: total.height)
        shape.frame = NSRect(x: bubbleFrame.minX, y: bubbleFrame.minY, width: bubbleFrame.width, height: bubbleFrame.height + (model.hasTail ? BubblePath.tailDrop : 0))
        timeLabel.frame = NSRect(x: width - 74, y: bubbleFrame.midY - 8, width: 64, height: 16)
        imageBubble.frame = bubbleFrame
        if model.threadLine {
            let top = model.threadAbove ? 0 : replyAvatar.frame.maxY + 6.5
            let bottom = model.avatarHandle != nil ? bubbleFrame.maxY - 29 : (model.threadBelow ? bounds.height : bubbleFrame.minY - 6)
            replyBracket.frame = NSRect(x: 32.5, y: top, width: 3, height: max(3, bottom - top))
        } else if model.reply != nil {
            let bracketTop = quoteFrame.minY + (quoteFrame.height - ReplyQuoteView.tailRoom) / 2
            let bracketBottom = model.fromMe ? bubbleFrame.maxY : (model.avatarHandle != nil ? bubbleFrame.maxY - 31 : bubbleFrame.minY - 6)
            replyBracket.frame = NSRect(x: 34, y: bracketTop, width: 30, height: max(2, bracketBottom - bracketTop))
        }
        linkCard.frame = NSRect(x: model.fromMe ? bubbleFrame.minX : bubbleFrame.minX + Theme.tail, y: bubbleFrame.minY, width: bubbleFrame.width - Theme.tail, height: bubbleFrame.height)
        saveButton.frame = NSRect(x: bubbleFrame.maxX + 8, y: bubbleFrame.midY - 14, width: 28, height: 28)

        if case .text = model.content {
            let inset = model.usesBubbleChrome ? Theme.horizontalPadding : 0
            let lead = model.usesBubbleChrome ? (model.fromMe ? inset : inset + Theme.tail) : (model.fromMe ? 0 : 17)
            textView.frame = NSRect(x: lead, y: model.usesBubbleChrome ? Theme.verticalPadding : 0, width: model.contentSize.width + 1, height: model.contentSize.height + 1)
            if isInk {
                inkHost.frame = textView.frame
                inkHost.configure(size: textView.frame.size, color: model.textColor)
                if inkTracking == nil {
                    let area = NSTrackingArea(rect: bubbleFrame, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
                    addTrackingArea(area)
                    inkTracking = area
                }
            }
        } else if case .voice = model.content {
            voiceView.leadingInset = model.fromMe ? 0 : Theme.tail
            voiceView.frame = NSRect(x: 0, y: 0, width: bubbleFrame.width - (model.fromMe ? Theme.tail : 0), height: bubbleFrame.height)
        } else if case .file = model.content {
            let lead = (model.fromMe ? 0 : Theme.tail) + Theme.horizontalPadding
            fileIcon.frame = NSRect(x: lead, y: 10, width: 32, height: 32)
            fileName.frame = NSRect(x: lead + 40, y: 10, width: model.contentSize.width - 40, height: 17)
            fileDetail.frame = NSRect(x: lead + 40, y: 28, width: model.contentSize.width - 40, height: 14)
        }

        if !model.tapbacks.isEmpty {
            let tapWidth = TapbackView.width(count: model.tapbacks.count)
            let tapX = model.fromMe ? bubbleFrame.minX - 11 - TapbackView.tailRoom : bubbleFrame.maxX - 16
            tapbackView.mirrored = model.fromMe
            tapbackView.frame = NSRect(x: tapX, y: bubbleFrame.minY - 22, width: tapWidth + TapbackView.tailRoom, height: 46)
        }

        if model.avatarHandle != nil {
            avatar.frame = NSRect(x: 20, y: bubbleFrame.maxY - 22, width: 28, height: 28)
        }

        if model.replyCount > 0 {
            let labelY = bubbleFrame.maxY + (model.footer == nil ? 4 : 22)
            repliesLabel.alignment = model.fromMe ? .right : .left
            let labelX = model.fromMe ? width - Theme.sideMargin - Theme.tail - 16 - 200 - timeGutter : x + Theme.tail + 4
            repliesLabel.frame = NSRect(x: labelX, y: labelY, width: 200, height: 18)
        }

        if model.footer != nil {
            footerLabel.alignment = model.fromMe ? .right : .left
            let footerWidth: CGFloat = 320
            let footerX = model.fromMe ? width - Theme.sideMargin - Theme.tail - 16 - footerWidth - timeGutter : x + Theme.tail
            footerLabel.frame = NSRect(x: footerX, y: bubbleFrame.maxY + 4.5, width: footerWidth, height: 18)
        }
    }
}

final class CenteredRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("centered")
    private let label = NSTextField(wrappingLabelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        wantsLayer = true
        label.isSelectable = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    var menuContext: MenuContext?

    override func menu(for event: NSEvent) -> NSMenu? {
        ContextMenus.background(menuContext)
    }

    func configure(_ string: NSAttributedString) {
        label.attributedStringValue = string
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 30, y: 15, width: max(0, bounds.width - 60), height: max(0, bounds.height - 15))
    }
}
