import Foundation

// Deliberately not NSUnarchiver: it instantiates classes from message-derived bytes and raises uncatchable exceptions.
enum AttributedBody {
    private static let marker = Array("NSString".utf8)

    static func text(from data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let start = find(marker, in: bytes, from: 0) else { return nil }

        var index = start + marker.count
        let limit = min(index + 24, bytes.count)
        while index < limit, bytes[index] != 0x2B { index += 1 }
        guard index < limit else { return nil }
        index += 1
        guard index < bytes.count else { return nil }

        var length = 0
        switch bytes[index] {
        case 0x81:
            guard index + 2 < bytes.count else { return nil }
            length = Int(bytes[index + 1]) | Int(bytes[index + 2]) << 8
            index += 3
        case 0x82:
            guard index + 4 < bytes.count else { return nil }
            length = Int(bytes[index + 1]) | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3]) << 16 | Int(bytes[index + 4]) << 24
            index += 5
        default:
            length = Int(bytes[index])
            index += 1
        }

        guard length > 0, index + length <= bytes.count else { return nil }
        return String(decoding: bytes[index..<(index + length)], as: UTF8.self)
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        var index = from
        while index <= haystack.count - needle.count {
            if haystack[index] == needle[0], Array(haystack[index..<(index + needle.count)]) == needle {
                return index
            }
            index += 1
        }
        return nil
    }
}
