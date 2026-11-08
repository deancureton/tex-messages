import Foundation

// Walks the keyed archive by hand so message payloads never instantiate classes.
enum LinkPayload {
    static func parse(_ data: Data) -> LinkCard? {
        guard let archive = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any],
              let top = archive["$top"] as? [String: Any] else { return nil }

        func deref(_ value: Any?) -> Any? {
            guard let value else { return nil }
            guard let index = uid(value) else { return value }
            guard index > 0, index < objects.count else { return nil }
            return objects[index]
        }

        guard let root = deref(top["root"]) as? [String: Any],
              let metadata = deref(root["richLinkMetadata"]) as? [String: Any] else { return nil }

        func url(_ key: String) -> URL? {
            guard let dict = deref(metadata[key]) as? [String: Any],
                  let relative = deref(dict["NS.relative"]) as? String else { return nil }
            return URL(string: relative)
        }

        let link = url("originalURL") ?? url("URL")
        let host = link?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let image = deref(metadata["image"]) as? [String: Any]
        let imageIndex = (deref(image?["richLinkImageAttachmentSubstituteIndex"]) as? NSNumber)?.intValue

        var theme: (red: Double, green: Double, blue: Double)?
        if let red = metadata["themeColor.red"] as? NSNumber,
           let green = metadata["themeColor.green"] as? NSNumber,
           let blue = metadata["themeColor.blue"] as? NSNumber {
            theme = (red.doubleValue, green.doubleValue, blue.doubleValue)
        }

        return LinkCard(
            title: deref(metadata["title"]) as? String,
            domain: host ?? deref(metadata["siteName"]) as? String,
            url: link,
            imageIndex: imageIndex,
            theme: theme
        )
    }

    private static func uid(_ value: Any) -> Int? {
        let description = String(describing: value)
        guard description.contains("CFKeyedArchiverUID"), let range = description.range(of: "value = ") else { return nil }
        return Int(description[range.upperBound...].prefix { $0.isNumber })
    }
}
