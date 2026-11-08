import AppKit

enum Theme {
    static let fontSize: CGFloat = 18
    static let bodyFont = NSFont.systemFont(ofSize: fontSize)
    static let tail: CGFloat = 5
    static let runGap: CGFloat = 3.5
    static let quoteFont = NSFont.systemFont(ofSize: 10)
    static let quoteParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 11.5
        style.maximumLineHeight = 11.5
        return style
    }()
    static let horizontalPadding: CGFloat = 12
    static let lineHeight: CGFloat = NSLayoutManager().defaultLineHeight(for: bodyFont)
    static let verticalPadding: CGFloat = (35 - lineHeight) / 2
    static let bubbleParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(0, 22.4 - lineHeight)
        return style
    }()
    static let sideMargin: CGFloat = 15
    static let avatarGutter: CGFloat = 35

    static let blue = NSColor(srgbRed: 0.16, green: 0.6, blue: 1, alpha: 1)
    static let selection = NSColor(srgbRed: 0.064, green: 0.569, blue: 1, alpha: 1)
    static let green = NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
    static let incoming = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)
            : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1)
    }
}

enum Format {
    private static func make(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let time = make("jmm")
    private static let weekday = make("EEEE")
    private static let short = make("yMd")
    private static let longDay = make("EEE, MMM d")

    static func sidebar(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return weekday.string(from: date)
        }
        return short.string(from: date)
    }

    static func transcript(_ date: Date) -> (day: String, time: String) {
        let calendar = Calendar.current
        let clock = time.string(from: date)
        if calendar.isDateInToday(date) { return ("Today", clock) }
        if calendar.isDateInYesterday(date) { return ("Yesterday", clock) }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return (weekday.string(from: date), clock)
        }
        return (longDay.string(from: date), "at \(clock)")
    }

    static func clock(_ date: Date) -> String {
        time.string(from: date)
    }

    static func receipt(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return short.string(from: date)
    }
}

enum BubblePath {
    static let tailDrop: CGFloat = 6.5

    private static func mirrored(_ path: NSBezierPath, width: CGFloat, fromMe: Bool) -> NSBezierPath {
        guard !fromMe else { return path }
        var transform = AffineTransform(translationByX: width, byY: 0)
        transform.scale(x: -1, y: 1)
        path.transform(using: transform)
        return path
    }

    static func body(size: CGSize, fromMe: Bool) -> NSBezierPath {
        let radius = min(17.5, size.height / 2)
        let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size.width - Theme.tail, height: size.height), xRadius: radius, yRadius: radius)
        return mirrored(path, width: size.width, fromMe: fromMe)
    }

    static func tail(size: CGSize, fromMe: Bool) -> NSBezierPath {
        let r = size.width - Theme.tail
        let h = size.height
        let path = NSBezierPath()
        path.move(to: CGPoint(x: r - 19, y: h - 0.5))
        path.line(to: CGPoint(x: r - 19, y: h))
        path.curve(to: CGPoint(x: r - 9.3, y: h + 5.7), controlPoint1: CGPoint(x: r - 16, y: h + 1.4), controlPoint2: CGPoint(x: r - 12.4, y: h + 4.2))
        path.curve(to: CGPoint(x: r - 7.7, y: h + 5.4), controlPoint1: CGPoint(x: r - 8.4, y: h + 6.3), controlPoint2: CGPoint(x: r - 7.4, y: h + 6.2))
        path.curve(to: CGPoint(x: r - 6.2, y: h - 4.6), controlPoint1: CGPoint(x: r - 10.3, y: h + 2.5), controlPoint2: CGPoint(x: r - 10, y: h - 1.5))
        path.line(to: CGPoint(x: r - 19, y: h - 4.6))
        path.close()
        return mirrored(path, width: size.width, fromMe: fromMe)
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NSGlassEffectView {
    func applyMessagesStyle(tinted: Bool = true) {
        tintColor = !tinted ? nil : NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.black.withAlphaComponent(0.14)
                : NSColor.white.withAlphaComponent(0.0)
        }
        #if canImport(AppKit, _version: 2700)
        if #available(macOS 27.0, *) { effectIsInteractive = true }
        #endif
    }
}

final class PillView: NSView {
    var fill = NSColor.separatorColor
    var radius: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}
