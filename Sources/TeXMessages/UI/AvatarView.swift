import AppKit

final class AvatarView: NSView {
    private var handles: [String] = []
    private var photo: NSImage?
    private var photoURL: URL?

    override var isFlipped: Bool { true }

    func configure(handles: [String], photo url: URL? = nil) {
        self.handles = handles
        if url != photoURL {
            photoURL = url
            photo = nil
            if let url {
                ImageLoader.shared.image(url: url, size: CGSize(width: 160, height: 160)) { [weak self] image in
                    guard self?.photoURL == url else { return }
                    self?.photo = image
                    self?.needsDisplay = true
                }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let photo {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: bounds).addClip()
            let source = photo.size
            let inset = abs(source.width - source.height) / 2
            let crop = source.width > source.height
                ? NSRect(x: inset, y: 0, width: source.height, height: source.height)
                : NSRect(x: 0, y: inset, width: source.width, height: source.width)
            photo.draw(in: bounds, from: crop, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        guard !handles.isEmpty else { return }
        guard handles.count > 1 else {
            drawCircle(handle: handles[0], rect: bounds)
            return
        }
        Self.groupFill.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let radius = bounds.width / 2
        let slots = handles.count == 2 ? Self.twoSlots : handles.count <= 6 ? Self.growingSlots : Self.manySlots
        for (handle, slot) in zip(handles, slots) {
            let size = slot.radius * radius
            drawCircle(handle: handle, rect: NSRect(x: bounds.midX + slot.x * radius - size, y: bounds.midY + slot.y * radius - size, width: size * 2, height: size * 2))
        }
    }

    private static let groupFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.48, green: 0.48, blue: 0.48, alpha: 0.45)
            : NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1)
    }
    private static let twoSlots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(-0.2375, -0.2375, 0.5375), (0.4, 0.394, 0.325)]
    private static let growingSlots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(-0.275, -0.275, 0.475), (0.488, 0.162, 0.362), (-0.138, 0.538, 0.288), (0.45, -0.475, 0.225), (-0.625, 0.312, 0.155), (0.162, -0.738, 0.112)]
    private static let manySlots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(-0.275, -0.275, 0.475), (0.438, 0.262, 0.338), (0.5, -0.375, 0.25), (-0.475, 0.45, 0.225), (0.05, 0.675, 0.175), (-0.075, 0.35, 0.125), (0.212, -0.712, 0.112)]

    private func drawCircle(handle: String, rect: NSRect) {
        let path = NSBezierPath(ovalIn: rect)
        let person = Contacts.shared.person(for: handle)
        if let person, let image = Contacts.shared.image(for: person) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        NSGradient(starting: NSColor(srgbRed: 0.424, green: 0.4, blue: 0.494, alpha: 1), ending: NSColor(srgbRed: 0.249, green: 0.208, blue: 0.361, alpha: 1))?.draw(in: path, angle: 90)
        if let initials = person?.initials {
            let font = NSFont.systemFont(ofSize: rect.height * 0.45, weight: .bold)
            let string = NSAttributedString(string: initials, attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = string.size()
            string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        } else {
            NSColor.white.setFill()
            silhouette(in: rect).fill()
        }
    }

    private func silhouette(in rect: NSRect) -> NSBezierPath {
        let radius = rect.width / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.midX + x * radius, y: rect.midY + y * radius)
        }
        let path = NSBezierPath(ovalIn: NSRect(x: rect.midX - 0.364 * radius, y: rect.midY - 0.614 * radius, width: 0.728 * radius, height: 0.756 * radius))
        path.move(to: point(0, 0.31))
        path.curve(to: point(0.634, 0.566), controlPoint1: point(0.363, 0.31), controlPoint2: point(0.634, 0.5115))
        path.curve(to: point(0, 0.864), controlPoint1: point(0.634, 0.622), controlPoint2: point(0.378, 0.864))
        path.curve(to: point(-0.634, 0.566), controlPoint1: point(-0.378, 0.864), controlPoint2: point(-0.634, 0.622))
        path.curve(to: point(0, 0.31), controlPoint1: point(-0.634, 0.5115), controlPoint2: point(-0.363, 0.31))
        path.close()
        return path
    }
}
