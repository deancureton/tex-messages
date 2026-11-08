import AppKit
import CoreText

final class MathGlyphs {
    struct Layer {
        let path: CGPath
        let color: CGColor?
    }

    struct TextRun {
        let string: String
        let transform: CGAffineTransform
        let fontSize: CGFloat
        let color: CGColor?
    }

    let layers: [Layer]
    let runs: [TextRun]
    let viewBox: CGRect

    init(layers: [Layer], runs: [TextRun], viewBox: CGRect) {
        self.layers = layers
        self.runs = runs
        self.viewBox = viewBox
    }

    var ascent: CGFloat { -viewBox.minY }
    var descent: CGFloat { viewBox.maxY }

    func draw(in context: CGContext, default color: CGColor) {
        for layer in layers {
            context.setFillColor(layer.color ?? color)
            context.addPath(layer.path)
            context.fillPath()
        }
        for run in runs {
            context.saveGState()
            context.concatenate(run.transform)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.setFillColor(run.color ?? color)
            let font = NSFont(name: "Times New Roman", size: run.fontSize) ?? .systemFont(ofSize: run.fontSize)
            let string = NSAttributedString(string: run.string, attributes: [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ])
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
            context.restoreGState()
        }
    }
}

final class SVGGlyphParser: NSObject, XMLParserDelegate {
    private enum Paint: Equatable {
        case none
        case current
        case color(CGColor)
    }

    private struct State {
        var transform = CGAffineTransform.identity
        var fill = Paint.current
        var stroke = Paint.none
        var strokeWidth: CGFloat = 1
    }

    private var stack = [State()]
    private var viewBox: CGRect?
    private var layers: [MathGlyphs.Layer] = []
    private var runs: [MathGlyphs.TextRun] = []
    private var pendingPath = CGMutablePath()
    private var pendingColor: CGColor?
    private var textBuffer: String?
    private var textAttributes: [String: String] = [:]

    static func parse(_ svg: String) -> MathGlyphs? {
        guard let data = svg.data(using: .utf8) else { return nil }
        let delegate = SVGGlyphParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let box = delegate.viewBox else { return nil }
        delegate.flush()
        return MathGlyphs(layers: delegate.layers, runs: delegate.runs, viewBox: box)
    }

    private func flush() {
        guard !pendingPath.isEmpty else { return }
        layers.append(.init(path: pendingPath, color: pendingColor))
        pendingPath = CGMutablePath()
    }

    private func add(_ path: CGPath, paint: Paint) {
        let color: CGColor?
        switch paint {
        case .none: return
        case .current: color = nil
        case .color(let value): color = value
        }
        if color != pendingColor {
            flush()
            pendingColor = color
        }
        pendingPath.addPath(path)
    }

    private func emit(_ path: CGPath, state: State) {
        add(path, paint: state.fill)
        if state.stroke != .none, state.strokeWidth > 0 {
            add(path.copy(strokingWithWidth: state.strokeWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10), paint: state.stroke)
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        var state = stack.last ?? State()
        if let fill = attributes["fill"] { state.fill = Self.paint(fill) }
        if let stroke = attributes["stroke"] { state.stroke = Self.paint(stroke) }
        if let width = attributes["stroke-width"] { state.strokeWidth = CGFloat(Double(width) ?? 1) }
        if let transform = attributes["transform"] {
            state.transform = Self.transform(transform).concatenating(state.transform)
        }

        func number(_ key: String) -> CGFloat { CGFloat(Double(attributes[key] ?? "") ?? 0) }
        let ctm = state.transform

        switch name {
        case "svg":
            if viewBox == nil, let box = attributes["viewBox"] {
                let v = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                if v.count == 4 { viewBox = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }
            }
        case "path":
            if let d = attributes["d"] {
                let path = CGMutablePath()
                Self.appendPath(d, to: path, transform: ctm)
                add(path, paint: state.fill)
                if state.stroke != .none, state.strokeWidth > 0 {
                    add(path.copy(strokingWithWidth: state.strokeWidth * Self.scale(of: ctm), lineCap: .butt, lineJoin: .miter, miterLimit: 10), paint: state.stroke)
                }
            }
        case "rect":
            let rect = CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
            let r = min(number("rx"), min(rect.width, rect.height) / 2)
            let path = CGMutablePath()
            if r > 0 {
                path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r, transform: ctm)
            } else {
                path.addRect(rect, transform: ctm)
            }
            emit(path, state: scaled(state))
        case "line":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: number("x1"), y: number("y1")), transform: ctm)
            path.addLine(to: CGPoint(x: number("x2"), y: number("y2")), transform: ctm)
            var lineState = scaled(state)
            lineState.fill = .none
            emit(path, state: lineState)
        case "ellipse", "circle":
            let rx = name == "circle" ? number("r") : number("rx")
            let ry = name == "circle" ? number("r") : number("ry")
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: number("cx") - rx, y: number("cy") - ry, width: rx * 2, height: ry * 2), transform: ctm)
            emit(path, state: scaled(state))
        case "polygon":
            let v = (attributes["points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }.map { CGFloat($0) }
            guard v.count >= 4 else { break }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: v[0], y: v[1]), transform: ctm)
            for i in stride(from: 2, to: v.count - 1, by: 2) {
                path.addLine(to: CGPoint(x: v[i], y: v[i + 1]), transform: ctm)
            }
            path.closeSubpath()
            emit(path, state: scaled(state))
        case "text":
            textBuffer = ""
            textAttributes = attributes
        default:
            break
        }
        stack.append(state)
    }

    private func scaled(_ state: State) -> State {
        var copy = state
        copy.strokeWidth *= Self.scale(of: state.transform)
        return copy
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer?.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let state = stack.removeLast()
        guard name == "text", let string = textBuffer else { return }
        textBuffer = nil
        let size = CGFloat(Double((textAttributes["font-size"] ?? "").replacingOccurrences(of: "px", with: "")) ?? 1000)
        var color: CGColor?
        if case .color(let value) = state.fill { color = value }
        runs.append(.init(string: string, transform: state.transform, fontSize: size, color: color))
    }

    private static func scale(of t: CGAffineTransform) -> CGFloat {
        sqrt(abs(t.a * t.d - t.b * t.c))
    }

    private static let named: [String: (CGFloat, CGFloat, CGFloat)] = [
        "black": (0, 0, 0), "white": (1, 1, 1), "red": (1, 0, 0), "green": (0, 0.5, 0), "lime": (0, 1, 0),
        "blue": (0, 0, 1), "yellow": (1, 1, 0), "cyan": (0, 1, 1), "aqua": (0, 1, 1), "magenta": (1, 0, 1),
        "fuchsia": (1, 0, 1), "gray": (0.5, 0.5, 0.5), "grey": (0.5, 0.5, 0.5), "silver": (0.75, 0.75, 0.75),
        "maroon": (0.5, 0, 0), "navy": (0, 0, 0.5), "olive": (0.5, 0.5, 0), "purple": (0.5, 0, 0.5),
        "teal": (0, 0.5, 0.5), "orange": (1, 0.65, 0), "pink": (1, 0.75, 0.8), "brown": (0.65, 0.16, 0.16),
    ]

    private static func paint(_ value: String) -> Paint {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "none" || text == "transparent" { return .none }
        if text == "currentcolor" { return .current }
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 6, let v = UInt32(hex, radix: 16) {
                return .color(CGColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1))
            }
        }
        if text.hasPrefix("rgb") {
            let parts = text.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 3 {
                return .color(CGColor(srgbRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1))
            }
        }
        if let (r, g, b) = named[text] { return .color(CGColor(srgbRed: r, green: g, blue: b, alpha: 1)) }
        return .current
    }

    private static func transform(_ text: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            let v = rest[rest.index(after: open)..<close].split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }.map { CGFloat($0) }
            var t = CGAffineTransform.identity
            switch name {
            case "translate" where v.count >= 1:
                t = CGAffineTransform(translationX: v[0], y: v.count > 1 ? v[1] : 0)
            case "scale" where v.count >= 1:
                t = CGAffineTransform(scaleX: v[0], y: v.count > 1 ? v[1] : v[0])
            case "matrix" where v.count == 6:
                t = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            case "rotate" where v.count >= 1:
                t = CGAffineTransform(rotationAngle: v[0] * .pi / 180)
            case "skewX" where v.count == 1:
                t = CGAffineTransform(a: 1, b: 0, c: tan(v[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            default:
                break
            }
            result = t.concatenating(result)
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    static func appendPath(_ d: String, to path: CGMutablePath, transform t: CGAffineTransform) {
        d.withCString { start in
            var cursor = start
            var command: CChar = 0
            var current = CGPoint.zero
            var subpath = CGPoint.zero
            var lastControl = CGPoint.zero
            var lastKind: CChar = 0

            func skip() {
                while cursor.pointee == 32 || cursor.pointee == 44 || cursor.pointee == 10 || cursor.pointee == 9 || cursor.pointee == 13 {
                    cursor += 1
                }
            }

            func number() -> CGFloat? {
                skip()
                var end: UnsafeMutablePointer<CChar>?
                let value = strtod(cursor, &end)
                guard let end, UnsafePointer(end) != cursor else { return nil }
                cursor = UnsafePointer(end)
                return CGFloat(value)
            }

            func point(relative: Bool) -> CGPoint? {
                guard let x = number(), let y = number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            func isLetter(_ c: CChar) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
            func ascii(_ s: Unicode.Scalar) -> CChar { CChar(s.value) }

            loop: while true {
                skip()
                if cursor.pointee == 0 { break }
                if isLetter(cursor.pointee), cursor.pointee != ascii("e"), cursor.pointee != ascii("E") {
                    command = cursor.pointee
                    cursor += 1
                }
                let relative = command >= 97
                let kind = relative ? command - 32 : command

                switch UInt8(bitPattern: kind) {
                case UInt8(ascii: "Z"):
                    path.closeSubpath()
                    current = subpath
                    lastKind = kind
                    continue loop
                case UInt8(ascii: "M"):
                    guard let p = point(relative: relative) else { break loop }
                    path.move(to: p, transform: t)
                    current = p
                    subpath = p
                    command = relative ? ascii("l") : ascii("L")
                case UInt8(ascii: "L"):
                    guard let p = point(relative: relative) else { break loop }
                    path.addLine(to: p, transform: t)
                    current = p
                case UInt8(ascii: "H"):
                    guard let x = number() else { break loop }
                    let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    path.addLine(to: p, transform: t)
                    current = p
                case UInt8(ascii: "V"):
                    guard let y = number() else { break loop }
                    let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    path.addLine(to: p, transform: t)
                    current = p
                case UInt8(ascii: "Q"):
                    guard let c = point(relative: relative), let p = point(relative: relative) else { break loop }
                    path.addQuadCurve(to: p, control: c, transform: t)
                    lastControl = c
                    current = p
                case UInt8(ascii: "T"):
                    guard let p = point(relative: relative) else { break loop }
                    let c = lastKind == ascii("Q") || lastKind == ascii("T")
                        ? CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
                        : current
                    path.addQuadCurve(to: p, control: c, transform: t)
                    lastControl = c
                    current = p
                case UInt8(ascii: "C"):
                    guard let c1 = point(relative: relative), let c2 = point(relative: relative), let p = point(relative: relative) else { break loop }
                    path.addCurve(to: p, control1: c1, control2: c2, transform: t)
                    lastControl = c2
                    current = p
                case UInt8(ascii: "S"):
                    guard let c2 = point(relative: relative), let p = point(relative: relative) else { break loop }
                    let c1 = lastKind == ascii("C") || lastKind == ascii("S")
                        ? CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
                        : current
                    path.addCurve(to: p, control1: c1, control2: c2, transform: t)
                    lastControl = c2
                    current = p
                default:
                    break loop
                }
                lastKind = kind
            }
        }
    }
}
