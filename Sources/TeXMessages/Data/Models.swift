import Foundation

struct ReplyOriginal {
    let text: String
    let isFromMe: Bool
    var handle: String? = nil
}

struct LinkCard {
    let title: String?
    let domain: String?
    let url: URL?
    let imageIndex: Int?
    let theme: (red: Double, green: Double, blue: Double)?
}

struct AttachmentInfo {
    enum Kind { case image, video, audio, file }

    let guid: String
    let path: String?
    let mimeType: String?
    let uti: String?
    let name: String?
    let bytes: Int64
    let isSticker: Bool

    var url: URL? {
        guard let path else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    var kind: Kind {
        let mime = mimeType ?? ""
        let type = uti ?? ""
        if mime.hasPrefix("image/") || type.contains("image") || type.contains("heic") { return .image }
        if mime.hasPrefix("video/") || type.contains("movie") || type.contains("video") { return .video }
        if mime.hasPrefix("audio/") || type.contains("audio") { return .audio }
        return .file
    }

    var isVoiceMessage: Bool {
        guard kind == .audio, let suffix = url?.pathExtension.lowercased() else { return false }
        return suffix == "caf" || suffix == "amr"
    }

    var isPluginPayload: Bool { (path ?? "").lowercased().hasSuffix(".pluginpayloadattachment") }

    var displayName: String {
        name ?? url?.lastPathComponent ?? "Attachment"
    }
}

struct Tapback {
    let type: Int64
    let emoji: String?
    let isFromMe: Bool
    let sender: String?
}

struct Message {
    let rowID: Int64
    let guid: String
    let text: String?
    let rawDate: Int64
    let date: Date
    let dateRead: Date?
    let dateDelivered: Date?
    let dateEdited: Date?
    let dateRetracted: Date?
    let isFromMe: Bool
    let isRead: Bool
    let isSent: Bool
    let isDelivered: Bool
    let error: Int64
    let itemType: Int64
    let groupActionType: Int64
    let groupTitle: String?
    let sender: String?
    let otherHandle: String?
    let threadOriginatorGuid: String?
    let balloonBundleID: String?
    let expressiveStyle: String?
    let service: String?
    var attachments: [AttachmentInfo]
    var linkCard: LinkCard? = nil

    var fingerprint: String {
        "\(text?.hashValue ?? 0):\(dateEdited?.timeIntervalSince1970 ?? 0):\(attachments.count)"
    }
}

struct ChatRow {
    let rowID: Int64
    let guid: String
    let identifier: String
    let displayName: String?
    let service: String?
    let isGroup: Bool
    let lastMessageID: Int64?
    let lastRawDate: Int64
    var photoPath: String? = nil
}

struct MessagePage {
    let messages: [Message]
    let tapbacks: [String: [Tapback]]
    let replyPreviews: [String: ReplyOriginal]
    let hasMore: Bool
}

struct ChatSnapshot {
    let chats: [ChatRow]
    let participants: [Int64: [String]]
    let recentSenders: [Int64: [String]]
    let previews: [Int64: String]
    let unread: [Int64: (count: Int, maxRowID: Int64)]
}

final class Conversation {
    let key: String
    let chats: [ChatRow]
    let participants: [String]
    let recentSenders: [String]
    let isGroup: Bool
    let lastDate: Date?
    let preview: String
    let unreadCount: Int
    let isMuted: Bool

    init(key: String, chats: [ChatRow], participants: [String], recentSenders: [String] = [], isGroup: Bool, lastDate: Date?, preview: String, unreadCount: Int, isMuted: Bool = false) {
        self.key = key
        self.chats = chats
        self.participants = participants
        self.recentSenders = recentSenders
        self.isGroup = isGroup
        self.lastDate = lastDate
        self.preview = preview
        self.unreadCount = unreadCount
        self.isMuted = isMuted
    }

    var chatIDs: [Int64] { chats.map(\.rowID) }

    var avatarHandles: [String] {
        guard isGroup else { return [participants.first ?? chats.first?.identifier ?? ""] }
        let recent = recentSenders.filter { participants.contains($0) }
        if participants.count > 6 {
            return Array((recent + participants.filter { !recent.contains($0) }).prefix(7))
        }
        guard let latest = recent.first else { return participants }
        return [latest] + participants.filter { $0 != latest }
    }

    var groupPhotoURL: URL? {
        guard isGroup, let path = chats.first?.photoPath else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    var sendGuid: String { chats.first?.guid ?? "" }
    var isSMS: Bool {
        let service = chats.first?.service?.lowercased() ?? ""
        return service == "sms" || service == "rcs"
    }

    var headerTitle: String {
        if isGroup, chats.first?.displayName?.isEmpty != false { return "\(participants.count) People" }
        guard !isGroup, chats.first?.displayName?.isEmpty != false, let handle = participants.first else { return title }
        return Contacts.shared.shortName(for: handle)
    }

    var title: String {
        if let name = chats.first?.displayName, !name.isEmpty { return name }
        if !isGroup { return Contacts.shared.displayName(for: participants.first ?? chats.first?.identifier ?? "") }
        let names = participants.map { Contacts.shared.shortName(for: $0) }
        switch names.count {
        case 0: return "Group"
        case 2: return "\(names[0]) & \(names[1])"
        case 1...3: return ListFormatter.localizedString(byJoining: names)
        default: return "\(names[0]), \(names[1]) & \(names.count - 2) others"
        }
    }
}

enum AppleDate {
    static func date(_ raw: Int64) -> Date? {
        guard raw != 0 else { return nil }
        let seconds = raw > 100_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
