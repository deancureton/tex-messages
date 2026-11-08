import AppKit
import ImageIO
import QuickLookThumbnailing

final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, NSImage>()
    private let animated = NSCache<NSString, NSNumber>()
    private let queue = DispatchQueue(label: "image.loader", qos: .userInitiated, attributes: .concurrent)

    init() { cache.countLimit = 300 }

    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    func isAnimated(_ url: URL, completion: @escaping (Bool) -> Void) {
        let key = url.path as NSString
        if let hit = animated.object(forKey: key) {
            completion(hit.boolValue)
            return
        }
        queue.async {
            let result = Self.hasFrameTiming(url)
            self.animated.setObject(NSNumber(value: result), forKey: key)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func hasFrameTiming(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        if properties[kCGImagePropertyGIFDictionary] != nil { return true }
        if let heics = properties[kCGImagePropertyHEICSDictionary] as? [CFString: Any], heics[kCGImagePropertyHEICSDelayTime] != nil { return true }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any], png[kCGImagePropertyAPNGDelayTime] != nil { return true }
        return false
    }

    func image(url: URL, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let key = "\(url.path)@\(Int(size.width))" as NSString
        if let hit = cache.object(forKey: key) {
            completion(hit)
            return
        }
        queue.async {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2,
            ]
            var result: NSImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                result = NSImage(cgImage: cgImage, size: size)
                self.cache.setObject(result!, forKey: key)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func poster(url: URL, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let key = "poster:\(url.path)" as NSString
        if let hit = cache.object(forKey: key) {
            completion(hit)
            return
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            if let image { self.cache.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
