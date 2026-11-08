import AppKit
import QuartzCore

enum MessageEffect: String {
    case slam = "impact", loud, gentle, invisibleInk = "invisibleink"
    case balloons = "CKHappyBirthdayEffect", confetti = "CKConfettiEffect", love = "CKHeartEffect"
    case lasers = "CKLasersEffect", fireworks = "CKFireworksEffect", celebration = "CKSparklesEffect"
    case echo = "CKEchoEffect", spotlight = "CKSpotlightEffect"

    init?(style: String?) {
        guard let style, let last = style.split(separator: ".").last else { return nil }
        self.init(rawValue: String(last))
    }

    var title: String {
        switch self {
        case .slam: return "Slam"
        case .loud: return "Loud"
        case .gentle: return "Gentle"
        case .invisibleInk: return "Invisible Ink"
        case .balloons: return "Balloons"
        case .confetti: return "Confetti"
        case .love: return "Love"
        case .lasers: return "Lasers"
        case .fireworks: return "Fireworks"
        case .celebration: return "Celebration"
        case .echo: return "Echo"
        case .spotlight: return "Spotlight"
        }
    }

    var replacesBubble: Bool {
        self == .slam || self == .loud || self == .gentle
    }
}

final class EffectOverlayView: FlippedView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum MessageEffectPlayer {
    typealias Snapshot = (image: NSImage, frame: NSRect)

    static func play(_ effect: MessageEffect, in host: NSView, bubble: NSRect, snapshot: Snapshot?, shake: NSView?, completion: @escaping () -> Void) {
        let overlay = EffectOverlayView(frame: host.bounds)
        overlay.wantsLayer = true
        overlay.autoresizingMask = [.width, .height]
        host.addSubview(overlay)
        guard let root = overlay.layer else {
            overlay.removeFromSuperview()
            completion()
            return
        }

        let duration: TimeInterval
        switch effect {
        case .slam: duration = slam(root, snapshot: snapshot, shake: shake)
        case .loud: duration = loud(root, snapshot: snapshot)
        case .gentle: duration = gentle(root, snapshot: snapshot)
        case .balloons: duration = balloons(root)
        case .confetti: duration = confetti(root)
        case .love: duration = love(root, bubble: bubble)
        case .lasers: duration = lasers(root, bubble: bubble)
        case .fireworks: duration = fireworks(root)
        case .celebration: duration = celebration(root)
        case .echo: duration = echo(root, snapshot: snapshot)
        case .spotlight: duration = spotlight(root, bubble: bubble)
        case .invisibleInk: duration = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            overlay.removeFromSuperview()
            completion()
        }
    }

    private static func picture(_ snapshot: Snapshot, in root: CALayer) -> CALayer? {
        guard let image = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: snapshot.frame.size)
        layer.position = CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)
        layer.contents = image
        root.addSublayer(layer)
        return layer
    }

    private static func keyframes(_ path: String, _ values: [Any], _ times: [NSNumber], duration: CFTimeInterval, begin: CFTimeInterval = 0) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.calculationMode = .linear
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        if begin > 0 { animation.beginTime = CACurrentMediaTime() + begin }
        return animation
    }

    private static func slam(_ root: CALayer, snapshot: Snapshot?, shake: NSView?) -> TimeInterval {
        guard let snapshot, let layer = picture(snapshot, in: root) else { return 0 }
        layer.add(keyframes("transform.scale", [3.4, 1, 1.06, 1], [0, 0.3, 0.45, 0.6], duration: 0.7), forKey: "scale")
        layer.add(keyframes("opacity", [0, 1, 1], [0, 0.25, 1], duration: 0.7), forKey: "fade")
        shake?.layer?.add(keyframes("transform.translation.y", [0, 7, -4, 2, 0], [0, 0.3, 0.55, 0.8, 1], duration: 0.3, begin: 0.2), forKey: "shake")
        return 0.72
    }

    private static func loud(_ root: CALayer, snapshot: Snapshot?) -> TimeInterval {
        guard let snapshot, let layer = picture(snapshot, in: root) else { return 0 }
        layer.add(keyframes("transform.scale", [1, 2.4, 2.4, 1], [0, 0.22, 0.7, 1], duration: 1.15), forKey: "scale")
        layer.add(keyframes("transform.rotation.z", [0, 0.03, -0.03, 0.03, -0.03, 0.02, 0], [0, 0.22, 0.34, 0.46, 0.58, 0.7, 1], duration: 1.15), forKey: "shake")
        return 1.17
    }

    private static func gentle(_ root: CALayer, snapshot: Snapshot?) -> TimeInterval {
        guard let snapshot, let layer = picture(snapshot, in: root) else { return 0 }
        layer.add(keyframes("transform.scale", [0.35, 0.35, 1], [0, 0.15, 1], duration: 2.2), forKey: "scale")
        layer.add(keyframes("opacity", [0.4, 1], [0, 1], duration: 2.2), forKey: "fade")
        return 2.22
    }

    private static func particle(_ draw: (CGContext, CGRect) -> Void, side: Int = 20) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        draw(context, CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static let circle = particle { context, rect in context.fillEllipse(in: rect) }
    private static let square = particle { context, rect in context.fill(rect.insetBy(dx: 2, dy: 6)) }
    private static let spark = particle({ context, rect in
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        for index in 0..<8 {
            let radius: CGFloat = index % 2 == 0 ? rect.width / 2 : rect.width / 9
            let angle = CGFloat(index) * .pi / 4
            let point = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }, side: 32)

    private static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink]

    private static func emitter(_ root: CALayer, position: CGPoint, size: CGSize, shape: CAEmitterLayerEmitterShape, cells: [CAEmitterCell]) -> CAEmitterLayer {
        let layer = CAEmitterLayer()
        layer.frame = root.bounds
        layer.emitterPosition = position
        layer.emitterSize = size
        layer.emitterShape = shape
        layer.emitterCells = cells
        root.addSublayer(layer)
        return layer
    }

    private static func dim(_ root: CALayer, opacity: Float, duration: CFTimeInterval) {
        let layer = CALayer()
        layer.frame = root.bounds
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        root.addSublayer(layer)
        layer.add(keyframes("opacity", [0, opacity, opacity, 0], [0, 0.12, 0.85, 1], duration: duration), forKey: "dim")
    }

    private static func confetti(_ root: CALayer) -> TimeInterval {
        let cells = palette.map { color -> CAEmitterCell in
            let cell = CAEmitterCell()
            cell.contents = square
            cell.color = color.cgColor
            cell.birthRate = 9
            cell.lifetime = 5
            cell.velocity = 150
            cell.velocityRange = 70
            cell.yAcceleration = 150
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 5
            cell.spin = 3
            cell.spinRange = 5
            cell.scale = 0.75
            cell.scaleRange = 0.3
            return cell
        }
        let layer = emitter(root, position: CGPoint(x: root.bounds.midX, y: -24), size: CGSize(width: root.bounds.width, height: 1), shape: .line, cells: cells)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { layer.birthRate = 0 }
        return 6
    }

    private static func celebration(_ root: CALayer) -> TimeInterval {
        let colors: [NSColor] = [.systemYellow, .systemOrange, NSColor(srgbRed: 1, green: 0.92, blue: 0.6, alpha: 1)]
        let cells = colors.map { color -> CAEmitterCell in
            let cell = CAEmitterCell()
            cell.contents = spark
            cell.color = color.cgColor
            cell.birthRate = 40
            cell.lifetime = 2.6
            cell.lifetimeRange = 0.8
            cell.velocity = 340
            cell.velocityRange = 200
            cell.emissionLongitude = .pi * 0.75
            cell.emissionRange = .pi / 4
            cell.alphaSpeed = -0.35
            cell.scale = 0.55
            cell.scaleRange = 0.4
            cell.spin = 2
            cell.spinRange = 4
            return cell
        }
        let layer = emitter(root, position: CGPoint(x: root.bounds.maxX - 8, y: 8), size: CGSize(width: 10, height: 10), shape: .point, cells: cells)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { layer.birthRate = 0 }
        return 5
    }

    private static func fireworks(_ root: CALayer) -> TimeInterval {
        dim(root, opacity: 0.6, duration: 4.6)
        let bounds = root.bounds
        for index in 0..<9 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(index) * 0.42) {
                guard root.superlayer != nil else { return }
                let color = palette.randomElement() ?? .systemYellow
                let cell = CAEmitterCell()
                cell.contents = circle
                cell.color = color.cgColor
                cell.birthRate = 1500
                cell.lifetime = 1.5
                cell.lifetimeRange = 0.4
                cell.velocity = 175
                cell.velocityRange = 14
                cell.emissionRange = .pi * 2
                cell.yAcceleration = 70
                cell.alphaSpeed = -0.6
                cell.scale = 0.13
                cell.scaleRange = 0.04
                let center = CGPoint(x: CGFloat.random(in: bounds.width * 0.15...bounds.width * 0.85), y: CGFloat.random(in: bounds.height * 0.12...bounds.height * 0.62))
                let layer = emitter(root, position: center, size: CGSize(width: 2, height: 2), shape: .point, cells: [cell])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { layer.birthRate = 0 }
            }
        }
        return 5.4
    }

    private static func balloons(_ root: CALayer) -> TimeInterval {
        let bounds = root.bounds
        for index in 0..<16 {
            let size = CGFloat.random(in: 58...104)
            let balloon = CALayer()
            balloon.bounds = CGRect(x: 0, y: 0, width: size, height: size * 1.9)
            let color = (palette.randomElement() ?? .systemRed).cgColor

            let body = CAShapeLayer()
            body.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size * 1.18), transform: nil)
            body.fillColor = color
            balloon.addSublayer(body)

            let shine = CAShapeLayer()
            shine.path = CGPath(ellipseIn: CGRect(x: size * 0.2, y: size * 0.14, width: size * 0.22, height: size * 0.3), transform: nil)
            shine.fillColor = CGColor(gray: 1, alpha: 0.4)
            balloon.addSublayer(shine)

            let string = CAShapeLayer()
            let line = CGMutablePath()
            line.move(to: CGPoint(x: size / 2, y: size * 1.18))
            line.addCurve(to: CGPoint(x: size / 2, y: size * 1.9), control1: CGPoint(x: size * 0.3, y: size * 1.4), control2: CGPoint(x: size * 0.7, y: size * 1.65))
            string.path = line
            string.strokeColor = CGColor(gray: 0.75, alpha: 0.8)
            string.fillColor = nil
            string.lineWidth = 1
            balloon.addSublayer(string)

            root.addSublayer(balloon)
            let x = CGFloat.random(in: 0...bounds.width)
            let sway = CGFloat.random(in: 18...46)
            let start = CGPoint(x: x, y: bounds.maxY + size * 1.2)
            balloon.position = start
            let values = [start, CGPoint(x: x + sway, y: bounds.height * 0.65), CGPoint(x: x - sway, y: bounds.height * 0.3), CGPoint(x: x, y: -size * 1.2)].map { NSValue(point: $0) }
            balloon.add(keyframes("position", values, [0, 0.35, 0.7, 1], duration: Double.random(in: 3.4...4.6), begin: Double(index) * 0.11), forKey: "rise")
        }
        return 6.6
    }

    private static func love(_ root: CALayer, bubble: NSRect) -> TimeInterval {
        guard let symbol = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 220, weight: .regular).applying(.init(paletteColors: [NSColor(srgbRed: 1, green: 0.26, blue: 0.47, alpha: 1)]))),
            let image = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let layer = CALayer()
        layer.contents = image
        layer.bounds = CGRect(x: 0, y: 0, width: symbol.size.width, height: symbol.size.height)
        layer.position = CGPoint(x: bubble.midX, y: max(bubble.midY - 90, symbol.size.height / 2))
        root.addSublayer(layer)
        layer.add(keyframes("transform.scale", [0.12, 1.1, 0.95, 1.1, 0.95, 1.25], [0, 0.22, 0.38, 0.54, 0.7, 1], duration: 2.5), forKey: "beat")
        layer.add(keyframes("opacity", [0, 0.95, 0.95, 0], [0, 0.1, 0.72, 1], duration: 2.5), forKey: "fade")
        return 2.55
    }

    private static func lasers(_ root: CALayer, bubble: NSRect) -> TimeInterval {
        dim(root, opacity: 0.72, duration: 3.6)
        let origin = CGPoint(x: root.bounds.midX, y: -10)
        let length = hypot(root.bounds.width, root.bounds.height) * 1.3
        let colors: [NSColor] = [.systemPink, .systemTeal, .systemPurple, .systemGreen, .systemBlue, .systemYellow]
        for index in 0..<12 {
            let beam = CAGradientLayer()
            let color = colors[index % colors.count]
            beam.colors = [color.cgColor, color.withAlphaComponent(0.15).cgColor]
            beam.bounds = CGRect(x: 0, y: 0, width: 5, height: length)
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.position = origin
            beam.shadowColor = color.cgColor
            beam.shadowRadius = 8
            beam.shadowOpacity = 1
            beam.shadowOffset = .zero
            root.addSublayer(beam)
            let phase = Double(index) / 12 * 2 * .pi
            let spread = 1.05
            let swings = (0...6).map { step -> NSNumber in
                NSNumber(value: sin(phase + Double(step) * 1.1) * spread)
            }
            beam.add(keyframes("transform.rotation.z", swings, (0...6).map { NSNumber(value: Double($0) / 6) }, duration: 3.6), forKey: "sweep")
            beam.add(keyframes("opacity", [0, 1, 1, 0], [0, 0.12, 0.85, 1], duration: 3.6), forKey: "fade")
        }
        return 3.7
    }

    private static func echo(_ root: CALayer, snapshot: Snapshot?) -> TimeInterval {
        guard let snapshot else { return 0 }
        let bounds = root.bounds
        let start = CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)
        for index in 0..<34 {
            guard let layer = picture(snapshot, in: root) else { continue }
            let target = CGPoint(x: CGFloat.random(in: 0...bounds.width), y: CGFloat.random(in: -40...bounds.height * 0.8))
            let begin = Double(index) * 0.045
            let move = [start, target].map { NSValue(point: $0) }
            let time: [NSNumber] = [0, 1]
            layer.opacity = 0
            layer.add(keyframes("position", move, time, duration: 1.5, begin: begin), forKey: "fly")
            layer.add(keyframes("opacity", [0.95, 0.95, 0], [0, 0.65, 1], duration: 1.5, begin: begin), forKey: "fade")
            layer.add(keyframes("transform.scale", [1, 0.75], time, duration: 1.5, begin: begin), forKey: "scale")
        }
        return 3.2
    }

    private static func spotlight(_ root: CALayer, bubble: NSRect) -> TimeInterval {
        let bounds = root.bounds
        let shade = CAShapeLayer()
        shade.frame = bounds
        shade.fillRule = .evenOdd
        shade.fillColor = CGColor(gray: 0, alpha: 0.86)

        let radius = max(bubble.width, bubble.height) / 2 + 26
        func path(_ center: CGPoint, _ r: CGFloat) -> CGPath {
            let result = CGMutablePath()
            result.addRect(bounds)
            result.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            return result
        }
        let target = CGPoint(x: bubble.midX, y: bubble.midY)
        let first = CGPoint(x: bounds.width * 0.15, y: bounds.height * 0.2)
        let second = CGPoint(x: bounds.width * 0.85, y: bounds.height * 0.45)
        shade.path = path(target, radius)
        root.addSublayer(shade)
        shade.add(keyframes("path", [path(first, radius * 1.3), path(second, radius * 1.3), path(target, radius), path(target, radius)], [0, 0.3, 0.55, 1], duration: 3), forKey: "sweep")
        shade.add(keyframes("opacity", [0, 1, 1, 0], [0, 0.1, 0.86, 1], duration: 3), forKey: "fade")
        return 3.05
    }
}

final class InkHostView: NSView {
    private let emitter = CAEmitterLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .surface
        layer?.addSublayer(emitter)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    private static let dot: CGImage? = {
        guard let context = CGContext(data: nil, width: 6, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: 6, height: 6))
        return context.makeImage()
    }()

    func configure(size: CGSize, color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.frame = CGRect(origin: .zero, size: size)
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
        emitter.emitterSize = size
        let cell = CAEmitterCell()
        cell.contents = Self.dot
        cell.color = color.cgColor
        cell.birthRate = Float(min(size.width * size.height * 0.5, 1400))
        cell.lifetime = 1.1
        cell.lifetimeRange = 0.5
        cell.velocity = 4
        cell.velocityRange = 6
        cell.emissionRange = .pi * 2
        cell.alphaSpeed = -0.5
        cell.scale = 0.2
        cell.scaleRange = 0.1
        emitter.emitterCells = [cell]
        CATransaction.commit()
    }
}
