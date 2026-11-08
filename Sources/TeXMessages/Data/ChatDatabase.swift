import Foundation

actor ChatDatabase {
    static var defaultPath: String {
        ProcessInfo.processInfo.environment["LM_CHAT_DB"] ?? NSHomeDirectory() + "/Library/Messages/chat.db"
    }

    static let isFixture = ProcessInfo.processInfo.environment["LM_CHAT_DB"] != nil

    private let sql: SQLite
    private let messageSelect: String
    private let attachmentSelect: String
    private let chatFilter: String
    private let chatProperties: String
    private var lastDataVersion: Int64 = -1
    private var senderDates: [Int64: [String: Int64]] = [:]
    private var lastSenderRowID: Int64 = 0

    init(path: String = ChatDatabase.defaultPath) throws {
        let sql = try SQLite(path: path)
        try sql.query("SELECT 1 FROM chat LIMIT 1") { _ in }
        self.sql = sql

        let message = try sql.columns(of: "message")
        func m(_ name: String) -> String { message.contains(name) ? "m.\(name)" : "NULL" }
        messageSelect = [
            "m.ROWID", "m.guid", m("text"), m("attributedBody"), m("date"), m("date_read"),
            m("date_delivered"), m("date_edited"), m("date_retracted"), m("is_from_me"), m("is_read"),
            m("is_sent"), m("is_delivered"), m("error"), m("item_type"), m("group_action_type"),
            m("group_title"), "h.id", "oh.id", m("thread_originator_guid"), m("balloon_bundle_id"),
            m("expressive_send_style_id"), m("service"), m("cache_has_attachments"), m("payload_data"),
        ].joined(separator: ", ")

        let attachment = try sql.columns(of: "attachment")
        func a(_ name: String) -> String { attachment.contains(name) ? "a.\(name)" : "NULL" }
        attachmentSelect = [
            "j.message_id", "a.guid", a("filename"), a("mime_type"), a("uti"), a("transfer_name"),
            a("total_bytes"), a("is_sticker"),
        ].joined(separator: ", ")

        let chat = try sql.columns(of: "chat")
        chatFilter = chat.contains("is_archived") ? "WHERE c.is_archived = 0" : ""
        chatProperties = chat.contains("properties") ? "c.properties" : "NULL"
    }

    func hasChanged() -> Bool {
        var version: Int64 = 0
        try? sql.query("PRAGMA data_version") { version = $0.int(0) }
        defer { lastDataVersion = version }
        return version != lastDataVersion
    }

    func snapshot() throws -> ChatSnapshot {
        var chats: [ChatRow] = []
        var photoGuids: [Int64: String] = [:]
        try sql.query("""
            SELECT c.ROWID, c.guid, c.chat_identifier, c.display_name, c.service_name, c.style, l.message_id, l.date, \(chatProperties)
            FROM chat c
            LEFT JOIN (
                SELECT chat_id, message_id, MAX(message_date) AS date FROM chat_message_join GROUP BY chat_id
            ) l ON l.chat_id = c.ROWID
            \(chatFilter)
            ORDER BY l.date DESC
            """) { row in
            if let data = row.blob(8),
               let properties = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let guid = properties["groupPhotoGuid"] as? String {
                photoGuids[row.int(0)] = guid
            }
            chats.append(ChatRow(
                rowID: row.int(0),
                guid: row.text(1) ?? "",
                identifier: row.text(2) ?? "",
                displayName: row.text(3),
                service: row.text(4),
                isGroup: row.int(5) == 43,
                lastMessageID: row.text(6) == nil ? nil : row.int(6),
                lastRawDate: row.int(7)
            ))
        }

        let photoPaths = try attachmentPaths(guids: Array(Set(photoGuids.values)))
        for index in chats.indices {
            if let guid = photoGuids[chats[index].rowID] { chats[index].photoPath = photoPaths[guid] }
        }

        var participants: [Int64: [String]] = [:]
        try sql.query("""
            SELECT j.chat_id, h.id FROM chat_handle_join j JOIN handle h ON h.ROWID = j.handle_id ORDER BY j.rowid
            """) { row in
            if let id = row.text(1) { participants[row.int(0), default: []].append(id) }
        }

        var unread: [Int64: (count: Int, maxRowID: Int64)] = [:]
        try sql.query("""
            SELECT j.chat_id, COUNT(*), MAX(m.ROWID)
            FROM message m JOIN chat_message_join j ON j.message_id = m.ROWID
            WHERE m.is_read = 0 AND m.is_from_me = 0 AND m.item_type = 0
              AND (m.associated_message_type IS NULL OR m.associated_message_type NOT BETWEEN 2000 AND 3999)
            GROUP BY j.chat_id
            """) { row in
            unread[row.int(0)] = (Int(row.int(1)), row.int(2))
        }

        return ChatSnapshot(chats: chats, participants: participants, recentSenders: try recentSenders(), previews: try previews(for: chats), unread: unread)
    }

    private func recentSenders() throws -> [Int64: [String]] {
        var newest = lastSenderRowID
        try sql.query("""
            SELECT j.chat_id, h.id, MAX(m.date), MAX(m.ROWID)
            FROM message m
            CROSS JOIN chat_message_join j ON j.message_id = m.ROWID
            CROSS JOIN chat c ON c.ROWID = j.chat_id
            CROSS JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.ROWID > ? AND c.style = 43 AND m.is_from_me = 0 AND m.item_type = 0
              AND (m.associated_message_type IS NULL OR m.associated_message_type NOT BETWEEN 2000 AND 3999)
            GROUP BY j.chat_id, h.id
            """, [.int(lastSenderRowID)]) { row in
            guard let id = row.text(1) else { return }
            senderDates[row.int(0), default: [:]][id] = row.int(2)
            newest = max(newest, row.int(3))
        }
        lastSenderRowID = newest
        return senderDates.mapValues { dates in dates.sorted { $0.value > $1.value }.map(\.key) }
    }

    private func attachmentPaths(guids: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for start in stride(from: 0, to: guids.count, by: 500) {
            let batch = Array(guids[start..<min(start + 500, guids.count)])
            let marks = Array(repeating: "?", count: batch.count).joined(separator: ",")
            try sql.query("SELECT guid, filename FROM attachment WHERE guid IN (\(marks))", batch.map { .text($0) }) { row in
                if let guid = row.text(0), let path = row.text(1) { result[guid] = path }
            }
        }
        return result
    }

    private static func ownTapback(_ text: String, sender: String?) -> String {
        let verbs = [("Loved", "loved"), ("Liked", "liked"), ("Disliked", "disliked"), ("Laughed at", "laughed at"), ("Emphasized", "emphasized"), ("Questioned", "questioned")]
        for (prefix, verb) in verbs where text.hasPrefix(prefix + " ") {
            let rest = String(text.dropFirst(prefix.count + 1))
            if rest == "an image", let sender { return "You \(verb) \(Contacts.shared.shortName(for: sender))'s photo" }
            return "You \(verb) \(rest)"
        }
        return text
    }

    private func previews(for chats: [ChatRow]) throws -> [Int64: String] {
        let ids = chats.compactMap(\.lastMessageID)
        guard !ids.isEmpty else { return [:] }
        var byMessage: [Int64: String] = [:]
        var ownTapbacks: [Int64: String] = [:]
        for batch in stride(from: 0, to: ids.count, by: 500) {
            let slice = ids[batch..<min(batch + 500, ids.count)]
            try sql.query("""
                SELECT m.ROWID, m.text, m.attributedBody, m.cache_has_attachments, m.is_from_me, m.associated_message_type, m.associated_message_guid
                FROM message m WHERE m.ROWID IN (\(slice.map(String.init).joined(separator: ",")))
                """) { row in
                let text = Self.body(text: row.text(1), blob: row.blob(2))
                byMessage[row.int(0)] = text ?? (row.int(3) != 0 ? "Attachment" : "")
                if row.int(4) != 0, (2000...2005).contains(row.int(5)), let raw = row.text(6) {
                    ownTapbacks[row.int(0)] = Self.targetGuid(raw)
                }
            }
        }

        var senders: [String: String] = [:]
        let targets = Array(Set(ownTapbacks.values))
        for start in stride(from: 0, to: targets.count, by: 500) {
            let batch = Array(targets[start..<min(start + 500, targets.count)])
            let marks = Array(repeating: "?", count: batch.count).joined(separator: ",")
            try sql.query("SELECT m.guid, h.id FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id WHERE m.guid IN (\(marks))", batch.map { .text($0) }) { row in
                if let guid = row.text(0), let handle = row.text(1) { senders[guid] = handle }
            }
        }
        for (id, target) in ownTapbacks {
            if let text = byMessage[id] { byMessage[id] = Self.ownTapback(text, sender: senders[target]) }
        }
        var result: [Int64: String] = [:]
        for chat in chats {
            if let id = chat.lastMessageID, let preview = byMessage[id] { result[chat.rowID] = preview }
        }
        return result
    }

    func page(chatIDs: [Int64], before: (date: Int64, rowID: Int64)? = nil, since: Int64? = nil, oldestLoaded: Int64? = nil, limit: Int = 200) throws -> MessagePage {
        let ids = chatIDs.map(String.init).joined(separator: ",")
        var clauses = [
            "j.chat_id IN (\(ids))",
            "(m.associated_message_type IS NULL OR m.associated_message_type NOT BETWEEN 2000 AND 3999)",
        ]
        var params: [SQLValue] = []
        if let before {
            clauses.append("(j.message_date < ? OR (j.message_date = ? AND m.ROWID < ?))")
            params += [.int(before.date), .int(before.date), .int(before.rowID)]
        }
        if let since {
            clauses.append("j.message_date >= ?")
            params.append(.int(since))
        }

        var messages: [Message] = []
        try sql.query("""
            SELECT \(messageSelect)
            FROM message m
            JOIN chat_message_join j ON j.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            LEFT JOIN handle oh ON oh.ROWID = m.other_handle
            WHERE \(clauses.joined(separator: " AND "))
            ORDER BY j.message_date DESC, m.ROWID DESC
            LIMIT \(limit + 1)
            """, params) { row in
            messages.append(Self.message(from: row))
        }

        let hasMore = messages.count > limit
        if hasMore { messages.removeLast() }
        messages.reverse()

        try attachAttachments(to: &messages)

        let from = min(oldestLoaded ?? Int64.max, messages.first?.rawDate ?? Int64.max)
        let tapbacks = from == Int64.max ? [:] : try loadTapbacks(ids: ids, from: from)
        return MessagePage(messages: messages, tapbacks: tapbacks, replyPreviews: try replyPreviews(for: messages), hasMore: hasMore)
    }

    func search(_ term: String) throws -> Set<Int64> {
        var result = Set<Int64>()
        try sql.query("""
            SELECT DISTINCT j.chat_id
            FROM message m JOIN chat_message_join j ON j.message_id = m.ROWID
            WHERE m.text LIKE ? OR instr(m.attributedBody, ?) > 0
            """, [.text("%\(term)%"), .blob(Data(term.utf8))]) { row in
            result.insert(row.int(0))
        }
        return result
    }

    private func attachAttachments(to messages: inout [Message]) throws {
        let ids = messages.map(\.rowID).map(String.init).joined(separator: ",")
        guard !ids.isEmpty else { return }
        var byMessage: [Int64: [AttachmentInfo]] = [:]
        try sql.query("""
            SELECT \(attachmentSelect)
            FROM attachment a JOIN message_attachment_join j ON j.attachment_id = a.ROWID
            WHERE j.message_id IN (\(ids))
            ORDER BY j.message_id, a.ROWID
            """) { row in
            byMessage[row.int(0), default: []].append(AttachmentInfo(
                guid: row.text(1) ?? "",
                path: row.text(2),
                mimeType: row.text(3),
                uti: row.text(4),
                name: row.text(5),
                bytes: row.int(6),
                isSticker: row.int(7) != 0
            ))
        }
        for index in messages.indices {
            messages[index].attachments = byMessage[messages[index].rowID] ?? []
        }
    }

    private func loadTapbacks(ids: String, from: Int64) throws -> [String: [Tapback]] {
        var result: [String: [Tapback]] = [:]
        try sql.query("""
            SELECT m.associated_message_guid, m.associated_message_type, m.is_from_me, h.id, \(emojiColumn)
            FROM message m
            JOIN chat_message_join j ON j.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE j.chat_id IN (\(ids)) AND j.message_date >= ?
              AND m.associated_message_type BETWEEN 2000 AND 3999
            ORDER BY j.message_date, m.ROWID
            """, [.int(from)]) { row in
            guard let raw = row.text(0) else { return }
            let target = Self.targetGuid(raw)
            let type = row.int(1)
            let isFromMe = row.int(2) != 0
            let sender = row.text(3)
            var list = result[target] ?? []
            list.removeAll { $0.isFromMe == isFromMe && $0.sender == sender }
            if type < 3000 {
                list.append(Tapback(type: type, emoji: row.text(4), isFromMe: isFromMe, sender: sender))
            }
            result[target] = list
        }
        return result.filter { !$0.value.isEmpty }
    }

    private var emojiColumn: String {
        ((try? sql.columns(of: "message")) ?? []).contains("associated_message_emoji") ? "m.associated_message_emoji" : "NULL"
    }

    private func replyPreviews(for messages: [Message]) throws -> [String: ReplyOriginal] {
        let guids = Array(Set(messages.compactMap(\.threadOriginatorGuid)))
        guard !guids.isEmpty else { return [:] }
        var result: [String: ReplyOriginal] = [:]
        let marks = Array(repeating: "?", count: guids.count).joined(separator: ",")
        try sql.query("SELECT m.guid, m.text, m.attributedBody, m.is_from_me, h.id FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id WHERE m.guid IN (\(marks))", guids.map { .text($0) }) { row in
            if let guid = row.text(0) {
                result[guid] = ReplyOriginal(text: Self.body(text: row.text(1), blob: row.blob(2)) ?? "Attachment", isFromMe: row.int(3) != 0, handle: row.text(4))
            }
        }
        return result
    }

    private static func targetGuid(_ raw: String) -> String {
        if let slash = raw.firstIndex(of: "/") { return String(raw[raw.index(after: slash)...]) }
        if raw.hasPrefix("bp:") { return String(raw.dropFirst(3)) }
        return raw
    }

    private static func body(text: String?, blob: Data?) -> String? {
        let raw = (text?.isEmpty == false ? text : nil) ?? blob.flatMap(AttributedBody.text(from:))
        guard let cleaned = raw?
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func message(from row: SQLRow) -> Message {
        let rawDate = row.int(4)
        var message = Message(
            rowID: row.int(0),
            guid: row.text(1) ?? "",
            text: body(text: row.text(2), blob: row.blob(3)),
            rawDate: rawDate,
            date: AppleDate.date(rawDate) ?? .distantPast,
            dateRead: AppleDate.date(row.int(5)),
            dateDelivered: AppleDate.date(row.int(6)),
            dateEdited: AppleDate.date(row.int(7)),
            dateRetracted: AppleDate.date(row.int(8)),
            isFromMe: row.int(9) != 0,
            isRead: row.int(10) != 0,
            isSent: row.int(11) != 0,
            isDelivered: row.int(12) != 0,
            error: row.int(13),
            itemType: row.int(14),
            groupActionType: row.int(15),
            groupTitle: row.text(16),
            sender: row.text(17),
            otherHandle: row.text(18),
            threadOriginatorGuid: row.text(19),
            balloonBundleID: row.text(20),
            expressiveStyle: row.text(21),
            service: row.text(22),
            attachments: []
        )
        if message.balloonBundleID?.contains("URLBalloonProvider") == true, let payload = row.blob(24) {
            message.linkCard = LinkPayload.parse(payload)
        }
        return message
    }
}
