import AppKit
import JavaScriptCore

final class MathEngine {
    static let shared = MathEngine()

    private struct Key: Hashable {
        let source: String
        let display: Bool
    }

    private let queue = DispatchQueue(label: "math.engine", qos: .userInitiated)
    private var context: JSContext?
    private var typeset: JSValue?
    private var cache: [Key: MathGlyphs] = [:]
    private var failed = Set<Key>()

    func warm() {
        queue.async { self.prepare() }
    }

    private func prepare() {
        guard context == nil,
              let url = Bundle.main.url(forResource: "mathjax", withExtension: "js")
                ?? ProcessInfo.processInfo.environment["LM_MATHJAX"].map({ URL(fileURLWithPath: $0) }),
              let script = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return }
        context.evaluateScript(script)
        self.context = context
        typeset = context.objectForKeyedSubscript("typeset")
    }

    func render(_ source: String, display: Bool) -> MathGlyphs? {
        queue.sync {
            let key = Key(source: Self.normalize(source), display: display)
            if let hit = cache[key] { return hit }
            if failed.contains(key) { return nil }
            guard let glyphs = typesetLocked(key) else {
                failed.insert(key)
                return nil
            }
            if cache.count > 5000 { cache.removeAll(keepingCapacity: true) }
            cache[key] = glyphs
            return glyphs
        }
    }

    private func typesetLocked(_ key: Key) -> MathGlyphs? {
        guard !key.source.isEmpty, key.source.utf8.count <= 4096 else { return nil }
        prepare()
        guard let context, let typeset else { return nil }
        context.exception = nil
        let value = typeset.call(withArguments: [key.source, key.display])
        if context.exception != nil {
            context.exception = nil
            return nil
        }
        guard let value, value.isString, let svg = value.toString() else { return nil }
        return SVGGlyphParser.parse(svg)
    }

    private static func normalize(_ source: String) -> String {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        for (from, to) in [("’", "'"), ("‘", "`"), ("”", "''"), ("“", "``"), ("—", "--"), ("–", "-"), ("…", "\\ldots ")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }
}

final class MathCell: NSTextAttachmentCell {
    static let unitScale: CGFloat = 0.0165

    let glyphs: MathGlyphs
    let source: String
    let isDisplay: Bool
    let color: NSColor
    private let baseScale: CGFloat
    private var fit: CGFloat = 1

    init(glyphs: MathGlyphs, source: String, display: Bool, color: NSColor, fontSize: CGFloat) {
        self.glyphs = glyphs
        self.source = source
        self.isDisplay = display
        self.color = color
        baseScale = MathCell.unitScale * fontSize / 14
        super.init()
    }

    required init(coder: NSCoder) { fatalError("unsupported") }

    private var scale: CGFloat { baseScale * fit }

    var naturalWidth: CGFloat { glyphs.viewBox.width * baseScale }

    func fit(to width: CGFloat, maxHeight: CGFloat = 480) {
        let height = glyphs.viewBox.height * baseScale
        fit = min(1, width / max(naturalWidth, 1), maxHeight / max(height, 1))
    }

    override func cellSize() -> NSSize {
        NSSize(width: ceil(glyphs.viewBox.width * scale), height: ceil(glyphs.viewBox.height * scale))
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -glyphs.descent * scale)
    }

    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in view: NSView?) {
        guard let graphics = NSGraphicsContext.current else { return }
        let context = graphics.cgContext
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldSmoothFonts(false)
        if graphics.isFlipped {
            context.translateBy(x: frame.minX, y: frame.minY)
        } else {
            context.translateBy(x: frame.minX, y: frame.maxY)
            context.scaleBy(x: 1, y: -1)
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -glyphs.viewBox.minX, y: -glyphs.viewBox.minY)
        glyphs.draw(in: context, default: color.cgColor)
    }

    override func draw(withFrame frame: NSRect, in view: NSView?, characterIndex: Int) {
        draw(withFrame: frame, in: view)
    }

    override func draw(withFrame frame: NSRect, in view: NSView?, characterIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: frame, in: view)
    }
}
