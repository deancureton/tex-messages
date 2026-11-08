import AppKit
import QuartzCore

enum SendFlight {
    private static let duration: CFTimeInterval = 0.4
    private static let keyTimes: [NSNumber] = [0, 0.42, 1]
    private static let timing = [
        CAMediaTimingFunction(name: .easeIn),
        CAMediaTimingFunction(name: .easeOut),
    ]

    static func run(in host: NSView, pill: NSRect, body: NSRect, composerTop: CGFloat, color: NSColor?, text: (image: NSImage, frame: NSRect)?, completion: @escaping () -> Void) {
        let overlay = FlippedView(frame: host.bounds)
        overlay.wantsLayer = true
        overlay.autoresizingMask = [.width, .height]
        host.addSubview(overlay)
        guard let root = overlay.layer else {
            overlay.removeFromSuperview()
            completion()
            return
        }

        let midSize = CGSize(width: max(body.width * 0.75, 40), height: body.height * 0.75)
        let mid = CGRect(x: body.maxX - midSize.width, y: composerTop - midSize.height - 2, width: midSize.width, height: midSize.height)

        let shape = CAShapeLayer()
        shape.frame = root.bounds
        shape.fillColor = color?.cgColor
        shape.path = rounded(body)
        if color != nil { root.addSublayer(shape) }

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            overlay.removeFromSuperview()
            completion()
        }
        if color != nil { shape.add(keyframes("path", [rounded(pill), rounded(mid), rounded(body)]), forKey: "morph") }

        if let text, let cgImage = text.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: text.frame.size)
            layer.position = CGPoint(x: text.frame.midX, y: text.frame.midY)
            layer.contents = cgImage
            root.addSublayer(layer)
            let startScale: CGFloat = color == nil ? 0.4 : 1
            let midScale: CGFloat = color == nil ? 0.8 : 0.75
            let start = CGPoint(x: pill.minX + 12 + text.frame.width * startScale / 2, y: pill.midY)
            let middle = color == nil
                ? CGPoint(x: text.frame.maxX - text.frame.width * midScale / 2, y: composerTop - text.frame.height * midScale / 2)
                : CGPoint(x: mid.midX, y: mid.midY)
            layer.add(keyframes("position", [start, middle, layer.position].map { NSValue(point: $0) }), forKey: "position")
            layer.add(keyframes("transform.scale", [startScale, midScale, 1].map { NSNumber(value: Double($0)) }), forKey: "scale")
        }
        CATransaction.commit()
    }

    private static func rounded(_ rect: CGRect) -> CGPath {
        let radius = max(min(17.5, rect.height / 2 - 0.01), 1)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func keyframes(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.timingFunctions = timing
        animation.duration = duration
        animation.calculationMode = .linear
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }
}
