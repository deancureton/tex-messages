import AppKit

extension NSAttributedString.Key {
    static let mathSource = NSAttributedString.Key("LMMathSource")
}

struct BubbleTextResult {
    let string: NSAttributedString
    let cells: [MathCell]
    let jumbo: Bool
}

enum BubbleText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.date.rawValue)

    static func make(_ text: String, color: NSColor) -> BubbleTextResult {
        let segments = MathSegmenter.split(text)
        let hasMath = segments.contains { if case .math = $0 { true } else { false } }
        if !hasMath, let size = jumboSize(text) {
            let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
            return BubbleTextResult(string: string, cells: [], jumbo: true)
        }

        let output = NSMutableAttributedString()
        var cells: [MathCell] = []
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.bodyFont, .foregroundColor: color, .paragraphStyle: Theme.bubbleParagraph]

        func appendRaw(_ string: String) {
            output.append(NSAttributedString(string: string, attributes: attributes))
        }

        var previousWasDisplay = false
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .text(var string):
                if previousWasDisplay { string = string.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression) }
                if index + 1 < segments.count, case .math(_, true, _) = segments[index + 1] {
                    string = string.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                }
                guard !string.isEmpty else { break }
                if previousWasDisplay { appendRaw("\n") }
                output.append(linked(string, attributes: attributes))
                previousWasDisplay = false
            case .math(let source, let display, let raw):
                guard let glyphs = MathEngine.shared.render(source, display: display) else {
                    if previousWasDisplay { appendRaw("\n") }
                    appendRaw(raw)
                    previousWasDisplay = false
                    break
                }
                if display, output.length > 0 { appendRaw("\n") }
                if !display, previousWasDisplay { appendRaw("\n") }
                let cell = MathCell(glyphs: glyphs, source: source, display: display, color: color, fontSize: Theme.fontSize)
                cells.append(cell)
                output.append(attachment(cell: cell, source: raw, font: Theme.bodyFont, color: color, centered: display))
                previousWasDisplay = display
            }
        }
        return BubbleTextResult(string: output, cells: cells, jumbo: false)
    }

    static func preview(_ text: String, color: NSColor) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let output = NSMutableAttributedString()
        for segment in MathSegmenter.split(text.replacingOccurrences(of: "\n", with: " ")) {
            switch segment {
            case .text(let string):
                output.append(NSAttributedString(string: string, attributes: attributes))
            case .math(let source, _, let raw):
                if let glyphs = MathEngine.shared.render(source, display: false) {
                    let cell = MathCell(glyphs: glyphs, source: source, display: false, color: color, fontSize: 12)
                    cell.fit(to: 10_000, maxHeight: 16)
                    output.append(attachment(cell: cell, source: raw, font: font, color: color, centered: false))
                } else {
                    output.append(NSAttributedString(string: raw, attributes: attributes))
                }
            }
        }
        return output
    }

    static func plainSource(_ attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            if let source = attributes[.mathSource] as? String {
                result += source
            } else {
                result += (attributed.string as NSString).substring(with: range)
            }
        }
        return result.replacingOccurrences(of: "\u{200B}", with: "")
    }

    private static func attachment(cell: MathCell, source: String, font: NSFont, color: NSColor, centered: Bool) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        let string = NSMutableAttributedString(attachment: attachment)
        let range = NSRange(location: 0, length: string.length)
        string.addAttributes([.font: font, .foregroundColor: color, .mathSource: source], range: range)
        string.append(NSAttributedString(string: "\u{200B}", attributes: [.font: font, .foregroundColor: color]))
        if centered {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.paragraphSpacing = 2
            style.paragraphSpacingBefore = 2
            string.addAttribute(.paragraphStyle, value: style, range: range)
        } else if font == Theme.bodyFont {
            string.addAttribute(.paragraphStyle, value: Theme.bubbleParagraph, range: range)
        }
        return string
    }

    private static func linked(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        let range = NSRange(location: 0, length: (text as NSString).length)
        detector?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            if let url = match.url {
                result.addAttribute(.link, value: url, range: match.range)
            } else if match.resultType == .date {
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            }
        }
        return result
    }

    static func jumboSize(_ text: String) -> CGFloat? {
        let emoji = text.filter { !$0.isWhitespace }
        guard !emoji.isEmpty, emoji.count <= 3 else { return nil }
        let allEmoji = emoji.allSatisfy { character in
            guard let first = character.unicodeScalars.first else { return false }
            return first.properties.isEmojiPresentation || (character.unicodeScalars.count > 1 && first.properties.isEmoji)
        }
        guard allEmoji else { return nil }
        return emoji.count == 1 ? 72 : 44
    }
}

enum TextMeasure {
    static func size(_ string: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        let storage = NSTextStorage(attributedString: string)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let rect = manager.usedRect(for: container)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}
