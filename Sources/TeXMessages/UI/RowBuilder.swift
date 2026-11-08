import AppKit
import ImageIO

enum BubbleContent {
    case text(BubbleTextResult, natural: CGSize)
    case image(URL, pixels: CGSize, sticker: Bool)
    case video(URL)
    case voice(URL)
    case file(name: String, detail: String, url: URL?, symbol: String?)
    case link(LinkCard, image: URL?, pixels: CGSize?, footer: NSAttributedString, fill: NSColor)
}

final class BubbleModel {
    let content: BubbleContent
    let fromMe: Bool
    let fill: NSColor?
    let textColor: NSColor
    let hasTail: Bool
    let topGap: CGFloat
    let sender: String?
    let avatarHandle: String?
    let reservesAvatar: Bool
    let reply: ReplyOriginal?
    let quoteCount: Int
    let replyCount: Int
    let tapbacks: [Tapback]
    let footer: String?
    let footerIsError: Bool
    let spoken: String
    let effect: MessageEffect?
    let time: String

    private(set) var contentSize = CGSize.zero
    private(set) var quoteSize = CGSize.zero
    var threadLine = false
    var threadAbove = false
    var threadBelow = false
    private var measuredAt: CGFloat = -1

    init(content: BubbleContent, fromMe: Bool, fill: NSColor?, textColor: NSColor, hasTail: Bool, topGap: CGFloat, sender: String?, avatarHandle: String?, reservesAvatar: Bool, reply: ReplyOriginal?, quoteCount: Int = 0, tapbacks: [Tapback], footer: String?, footerIsError: Bool, spoken: String, effect: MessageEffect? = nil, time: String = "", replyCount: Int = 0) {
        self.content = content
        self.fromMe = fromMe
        self.fill = fill
        self.textColor = textColor
        self.hasTail = hasTail
        self.topGap = topGap
        self.sender = sender
        self.avatarHandle = avatarHandle
        self.reservesAvatar = reservesAvatar
        self.reply = reply
        self.quoteCount = quoteCount
        self.replyCount = replyCount
        self.tapbacks = tapbacks
        self.footer = footer
        self.footerIsError = footerIsError
        self.spoken = spoken
        self.effect = effect
        self.time = time
    }

    var usesBubbleChrome: Bool { fill != nil }
    var totalSize: CGSize { CGSize(width: contentSize.width + chromeWidth, height: contentSize.height + chromeHeight) }

    private var chromeWidth: CGFloat {
        guard usesBubbleChrome else { return 0 }
        if case .text = content { return Theme.horizontalPadding * 2 + Theme.tail }
        if case .file = content { return Theme.horizontalPadding * 2 + Theme.tail }
        return Theme.tail
    }

    private var chromeHeight: CGFloat {
        guard usesBubbleChrome, case .text = content else { return 0 }
        return Theme.verticalPadding * 2
    }

    func layout(rowWidth: CGFloat) -> CGFloat {
        let limit = min(rowWidth * 0.6 + Theme.tail, 560)
        if let reply {
            let text = NSAttributedString(string: reply.text, attributes: [.font: Theme.quoteFont, .paragraphStyle: Theme.quoteParagraph])
            let measured = TextMeasure.size(text, maxWidth: limit - Theme.tail - 23)
            quoteSize = CGSize(width: measured.width + 18, height: min(measured.height, 34.5) + 11)
        }
        switch content {
        case .text(let result, let natural):
            let width = max(40, limit - (usesBubbleChrome ? Theme.horizontalPadding * 2 + Theme.tail : 0))
            result.cells.forEach { $0.fit(to: width) }
            let mathOverflows = result.cells.contains { $0.naturalWidth > width }
            if natural.width <= width, !mathOverflows {
                contentSize = natural
            } else if measuredAt != width {
                contentSize = TextMeasure.size(result.string, maxWidth: width)
                measuredAt = width
            }
            if usesBubbleChrome { contentSize.height = max(contentSize.height, 17) }
        case .image(_, let pixels, let sticker):
            let maxWidth = min(limit - Theme.tail, sticker ? 140 : 266)
            let maxHeight: CGFloat = sticker ? 140 : 360
            let scale = min(1, maxWidth / max(pixels.width, 1), maxHeight / max(pixels.height, 1))
            contentSize = CGSize(width: max(48, round(pixels.width * scale)), height: max(48, round(pixels.height * scale)))
        case .video:
            contentSize = CGSize(width: min(limit - Theme.tail, 280), height: 180)
        case .voice:
            contentSize = CGSize(width: min(limit - Theme.tail, 226), height: 40)
        case .link(_, _, let pixels, let footer, _):
            let width = min(limit - Theme.tail, 266)
            let imageHeight = pixels.map { min(round(width * $0.height / max($0.width, 1)), 320) } ?? 0
            let text = TextMeasure.size(footer, maxWidth: width - 24)
            contentSize = CGSize(width: width, height: imageHeight + text.height + 18)
        case .file:
            contentSize = CGSize(width: min(limit - Theme.horizontalPadding * 2 - Theme.tail, 220), height: 52)
        }
        return height
    }

    var quoteBlock: CGFloat {
        guard reply != nil else { return 0 }
        return quoteSize.height + (quoteCount > 1 ? 33 : 21.5)
    }

    var overhang: CGFloat { tapbacks.isEmpty || topGap == Theme.runGap ? 0 : 14 }

    var height: CGFloat {
        topGap + (sender == nil ? 0 : 20) + quoteBlock + overhang + totalSize.height + (footer == nil ? 0 : 23) + (avatarHandle == nil ? 0 : 6) + (replyCount == 0 ? 0 : 24)
    }
}

final class Row {
    enum Kind {
        case centered(NSAttributedString)
        case bubble(BubbleModel)
    }

    let id: String
    let kind: Kind
    private(set) var height: CGFloat = 28

    init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    func layout(rowWidth: CGFloat) {
        switch kind {
        case .centered(let string):
            height = TextMeasure.size(string, maxWidth: max(100, rowWidth - 60)).height + 20
        case .bubble(let model):
            height = model.layout(rowWidth: rowWidth)
        }
    }
}

struct PendingMessage {
    let id = UUID()
    let text: String?
    let file: URL?
    let date: Date
    var failed = false
}

struct TranscriptInput {
    let messages: [Message]
    let tapbacks: [String: [Tapback]]
    let replies: [String: ReplyOriginal]
    let replyCounts: [String: Int]
    let pending: [PendingMessage]
    let isGroup: Bool
    let isSMS: Bool
    let width: CGFloat
}

final class RowBuilder {
    private var contentCache: [String: BubbleContent] = [:]

    private struct Part {
        let id: String
        let message: Message?
        let pending: PendingMessage?
        let build: () -> BubbleContent?
        let spoken: String

        var fromMe: Bool { message?.isFromMe ?? true }
        var sender: String? { message?.sender }
        var date: Date { message?.date ?? pending?.date ?? Date() }
    }

    func build(_ input: TranscriptInput) -> [Row] {
        let lastOutgoing = input.messages.last { $0.isFromMe && $0.itemType == 0 && $0.dateRetracted == nil && Self.hasReceipt($0) }?.rowID
        var rows: [Row] = []
        var previous: Part?
        var previousWasSystem = false
        let parts = flatten(input)

        for (index, entry) in parts.enumerated() {
            switch entry {
            case .system(let message, let text):
                appendTimestampIfNeeded(for: message.date, previous: previous?.date, into: &rows, id: "t\(message.rowID)")
                rows.append(Row(id: "s\(message.rowID)", kind: .centered(Self.system(text))))
                previous = nil
                previousWasSystem = true
            case .part(let part):
                let needsTime = previous.map { part.date.timeIntervalSince($0.date) >= 3600 } ?? !previousWasSystem
                if needsTime { rows.append(Self.timestamp(part.date, id: "t\(part.id)")) }

                let continues = !needsTime && previous.map { Self.sameRun($0, part) } == true
                var nextContinues = false
                if index + 1 < parts.count, case .part(let next) = parts[index + 1] {
                    nextContinues = next.date.timeIntervalSince(part.date) < 3600 && Self.sameRun(part, next)
                }

                let model = makeModel(part: part, input: input, continues: continues, hasTail: !nextContinues, afterTime: needsTime, isLastOfMessage: isLast(part, in: parts, at: index), lastOutgoing: lastOutgoing)
                if let model { rows.append(Row(id: part.id, kind: .bubble(model))) }
                previous = part
                previousWasSystem = false
            }
        }
        rows.forEach { $0.layout(rowWidth: input.width) }
        return rows
    }

    private enum Entry {
        case system(Message, String)
        case part(Part)
    }

    private func isLast(_ part: Part, in parts: [Entry], at index: Int) -> Bool {
        guard index + 1 < parts.count, case .part(let next) = parts[index + 1] else { return true }
        if let id = part.message?.rowID, id == next.message?.rowID { return false }
        return true
    }

    private func appendTimestampIfNeeded(for date: Date, previous: Date?, into rows: inout [Row], id: String) {
        if previous == nil, rows.isEmpty { rows.append(Self.timestamp(date, id: id)) }
    }

    private func flatten(_ input: TranscriptInput) -> [Entry] {
        var entries: [Entry] = []
        for message in input.messages {
            if let text = Self.systemText(message) {
                entries.append(.system(message, text))
                continue
            }
            if let card = message.linkCard {
                entries.append(.part(Part(id: "\(message.guid):l", message: message, pending: nil, build: { Self.linkContent(card, attachments: message.attachments) }, spoken: card.title ?? "Link")))
                continue
            }
            let visibleAttachments = message.attachments.filter { !$0.isPluginPayload }
            for attachment in visibleAttachments {
                let id = "\(message.guid):\(attachment.guid)"
                entries.append(.part(Part(id: id, message: message, pending: nil, build: { Self.attachmentContent(attachment) }, spoken: "Attachment \(attachment.displayName)")))
            }
            if let text = message.text {
                let color: NSColor = message.isFromMe ? .white : .labelColor
                let key = "\(message.guid):\(message.fingerprint)"
                entries.append(.part(Part(id: "\(message.guid):t", message: message, pending: nil, build: { [unowned self] in self.textContent(text, color: color, key: key) }, spoken: text)))
            } else if visibleAttachments.isEmpty, let bundle = message.balloonBundleID {
                let name = bundle.split(separator: ":").last.map(String.init) ?? "an app"
                let result = BubbleText.make("Sent with \(name)", color: message.isFromMe ? .white : .labelColor)
                let natural = TextMeasure.size(result.string, maxWidth: 10_000)
                entries.append(.part(Part(id: "\(message.guid):b", message: message, pending: nil, build: { .text(result, natural: natural) }, spoken: "App message")))
            }
        }
        for item in input.pending {
            if let text = item.text {
                entries.append(.part(Part(id: item.id.uuidString, message: nil, pending: item, build: { [unowned self] in self.textContent(text, color: .white, key: item.id.uuidString) }, spoken: text)))
            } else if let file = item.file {
                entries.append(.part(Part(id: item.id.uuidString, message: nil, pending: item, build: {
                    .file(name: file.lastPathComponent, detail: "Sending…", url: file, symbol: nil)
                }, spoken: file.lastPathComponent)))
            }
        }
        return entries
    }

    private func textContent(_ text: String, color: NSColor, key: String) -> BubbleContent {
        if let cached = contentCache[key] { return cached }
        let result = BubbleText.make(text, color: color)
        result.cells.forEach { $0.fit(to: 10_000) }
        let content = BubbleContent.text(result, natural: TextMeasure.size(result.string, maxWidth: 10_000))
        contentCache[key] = content
        return content
    }

    private static func linkContent(_ card: LinkCard, attachments: [AttachmentInfo]) -> BubbleContent {
        let payloads = attachments.filter(\.isPluginPayload)
        var image: URL?
        var pixels: CGSize?
        if let index = card.imageIndex, payloads.indices.contains(index), let url = payloads[index].url,
           let size = ImageLoader.pixelSize(of: url) {
            image = url
            pixels = size
        }

        var fill = Theme.incoming
        var primary = NSColor.labelColor
        var secondary = NSColor.secondaryLabelColor
        if let theme = card.theme {
            fill = NSColor(srgbRed: theme.red, green: theme.green, blue: theme.blue, alpha: 1)
            let isLight = 0.299 * theme.red + 0.587 * theme.green + 0.114 * theme.blue > 0.6
            primary = isLight ? .black : .white
            secondary = primary.withAlphaComponent(0.6)
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let footer = NSMutableAttributedString()
        if let title = card.title, !title.isEmpty {
            footer.append(NSAttributedString(string: String(title.prefix(90)) + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: primary, .paragraphStyle: style]))
        }
        footer.append(NSAttributedString(string: card.domain ?? card.url?.absoluteString ?? "", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary, .paragraphStyle: style]))
        return .link(card, image: image, pixels: pixels, footer: footer, fill: fill)
    }

    private static func attachmentContent(_ attachment: AttachmentInfo) -> BubbleContent {
        let size = ByteCountFormatter.string(fromByteCount: attachment.bytes, countStyle: .file)
        guard let url = attachment.url, FileManager.default.fileExists(atPath: url.path) else {
            return .file(name: attachment.displayName, detail: "Not downloaded", url: nil, symbol: "icloud.and.arrow.down")
        }
        switch attachment.kind {
        case .image:
            if let pixels = ImageLoader.pixelSize(of: url) {
                return .image(url, pixels: pixels, sticker: attachment.isSticker)
            }
            return .file(name: attachment.displayName, detail: size, url: url, symbol: nil)
        case .video:
            return .video(url)
        case .audio:
            if attachment.isVoiceMessage { return .voice(url) }
            return .file(name: attachment.displayName, detail: size, url: url, symbol: "waveform")
        case .file:
            return .file(name: attachment.displayName, detail: size, url: url, symbol: nil)
        }
    }

    private func makeModel(part: Part, input: TranscriptInput, continues: Bool, hasTail: Bool, afterTime: Bool, isLastOfMessage: Bool, lastOutgoing: Int64?) -> BubbleModel? {
        guard let content = part.build() else { return nil }
        let message = part.message
        let isGreen = message == nil ? input.isSMS : Self.isSMS(message)
        var fill: NSColor? = part.fromMe ? (isGreen ? Theme.green : Theme.blue) : Theme.incoming
        var drawsTail = hasTail
        switch content {
        case .link(_, _, _, _, let cardFill):
            fill = cardFill
            drawsTail = false
        case .text(let result, _) where result.jumbo:
            fill = nil
            drawsTail = false
        case .image(_, _, let sticker) where sticker:
            fill = nil
            drawsTail = false
        default:
            break
        }

        let incomingGroup = input.isGroup && !part.fromMe
        let senderName = incomingGroup && !continues ? part.sender.map { Contacts.shared.displayName(for: $0) } : nil
        let avatar = incomingGroup && hasTail ? part.sender : nil
        let original = message?.threadOriginatorGuid.flatMap { guid in input.replies[guid] ?? ReplyOriginal(text: "Reply", isFromMe: false) }
        let reply = continues ? nil : original
        let quoteCount = message?.threadOriginatorGuid.flatMap { input.replyCounts[$0] } ?? 0
        let tapbacks = isLastOfMessage ? (message.flatMap { input.tapbacks[$0.guid] } ?? []) : []

        var footer: String?
        var isError = false
        if isLastOfMessage {
            if let message {
                var notes: [String] = []
                if message.error != 0 {
                    isError = true
                    notes.append("Not Delivered")
                } else if message.rowID == lastOutgoing {
                    if let read = message.dateRead, !input.isGroup {
                        notes.append("Read \(Format.receipt(read))")
                    } else if message.isDelivered || message.dateDelivered != nil {
                        notes.append("Delivered")
                    } else if Self.isSMS(message), message.isSent {
                        notes.append("Sent as Text Message")
                    }
                }
                if message.dateEdited != nil { notes.insert("Edited", at: 0) }
                if let effect = MessageEffect(style: message.expressiveStyle) { notes.append("Sent with \(effect.title)") }
                footer = notes.isEmpty ? nil : notes.joined(separator: " · ")
            } else if part.pending?.failed == true {
                footer = "Not Delivered"
                isError = true
            }
        }

        let who = part.fromMe ? "You" : part.sender.map { Contacts.shared.displayName(for: $0) } ?? "Message"
        let model = BubbleModel(
            content: content,
            fromMe: part.fromMe,
            fill: fill,
            textColor: part.fromMe ? .white : .labelColor,
            hasTail: drawsTail,
            topGap: afterTime ? 2 : (reply != nil ? 26 : (continues ? Theme.runGap : (input.isGroup ? 12 : 8.5))),
            sender: senderName,
            avatarHandle: avatar,
            reservesAvatar: incomingGroup,
            reply: reply,
            quoteCount: quoteCount,
            tapbacks: tapbacks,
            footer: footer,
            footerIsError: isError,
            spoken: "\(who): \(part.spoken)",
            effect: isLastOfMessage ? MessageEffect(style: message?.expressiveStyle) : nil,
            time: Format.clock(part.date),
            replyCount: isLastOfMessage ? (message.flatMap { input.replyCounts[$0.guid] } ?? 0) : 0
        )
        if incomingGroup, let original, !original.isFromMe, original.handle != nil {
            model.threadLine = true
            model.threadAbove = continues
            model.threadBelow = !hasTail
        }
        return model
    }

    private static func hasReceipt(_ message: Message) -> Bool {
        message.dateRead != nil || message.isDelivered || message.dateDelivered != nil || (isSMS(message) && message.isSent)
    }

    private static func sameRun(_ a: Part, _ b: Part) -> Bool {
        guard a.fromMe == b.fromMe, a.sender == b.sender else { return false }
        guard a.message?.threadOriginatorGuid == b.message?.threadOriginatorGuid else { return false }
        if a.message?.threadOriginatorGuid != nil { return true }
        return b.date.timeIntervalSince(a.date) < 60
    }

    private static func isSMS(_ message: Message?) -> Bool {
        let service = message?.service?.lowercased() ?? ""
        return service == "sms" || service == "rcs"
    }

    private static func systemText(_ message: Message) -> String? {
        let actor = message.isFromMe ? "You" : message.sender.map { Contacts.shared.displayName(for: $0) } ?? "Someone"
        if message.dateRetracted != nil { return "\(actor) unsent a message" }
        let other = message.otherHandle.map { Contacts.shared.displayName(for: $0) } ?? "someone"
        switch message.itemType {
        case 0:
            return nil
        case 1:
            return message.groupActionType == 1 ? "\(actor) removed \(other) from the conversation" : "\(actor) added \(other) to the conversation"
        case 2:
            return message.groupTitle.map { "\(actor) named the conversation “\($0)”" } ?? "\(actor) removed the conversation name"
        case 3:
            return message.groupActionType == 0 ? "\(actor) left the conversation" : "\(actor) changed the group photo"
        case 4:
            return "\(actor) shared a location update"
        default:
            return message.text
        }
    }

    private static func timestamp(_ date: Date, id: String) -> Row {
        let parts = Format.transcript(date)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let string = NSMutableAttributedString(string: parts.day, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ])
        string.append(NSAttributedString(string: " \(parts.time)", attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]))
        return Row(id: id, kind: .centered(string))
    }

    private static func system(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ])
    }
}
