import AppKit

final class AppModel {
    static let shared = AppModel()

    private(set) var database: ChatDatabase?
    private(set) var conversations: [Conversation] = []
    private(set) var pinned: [Conversation] = []
    private var snapshot: ChatSnapshot?
    private var watcher: DatabaseWatcher?
    private var reloading = false
    private var reloadQueued = false
    private var seen: [String: Int64]
    private var forcedUnread: Set<String>
    private var muted: Set<String>
    private var localPins: [String]
    private var localUnpins: Set<String>
    private var backgrounds: [String: String]

    var onConversations: (() -> Void)?
    var onDatabaseChange: (() -> Void)?
    var onContactsLoaded: (() -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        seen = defaults.dictionary(forKey: "seenRowIDs") as? [String: Int64] ?? [:]
        forcedUnread = Set(defaults.stringArray(forKey: "forcedUnread") ?? [])
        muted = Set(defaults.stringArray(forKey: "mutedConversations") ?? [])
        localPins = defaults.stringArray(forKey: "localPins") ?? []
        localUnpins = Set(defaults.stringArray(forKey: "localUnpins") ?? [])
        backgrounds = defaults.dictionary(forKey: "conversationBackgrounds") as? [String: String] ?? [:]
    }

    func connect() throws {
        let path = ChatDatabase.defaultPath
        database = try ChatDatabase(path: path)
        watcher = DatabaseWatcher(databasePath: path) { [weak self] in self?.databaseTouched() }
        watcher?.start()
        reload()
        if !ChatDatabase.isFixture { Contacts.shared.load { [weak self] in
            self?.reload()
            self?.onContactsLoaded?()
        } }
    }

    private static func pinnedIdentifiers() -> [String] {
        if ChatDatabase.isFixture {
            return (ProcessInfo.processInfo.environment["LM_PINS"] ?? "").split(separator: ",").map(String.init)
        }
        let domain = "com.apple.messages.pinning" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("pD" as CFString, domain) as? [String: Any]
        return value?["pP"] as? [String] ?? []
    }

    private func databaseTouched() {
        guard let database else { return }
        Task {
            guard await database.hasChanged() else { return }
            await MainActor.run {
                self.reload()
                self.onDatabaseChange?()
            }
        }
    }

    func reload() {
        guard let database else { return }
        if reloading {
            reloadQueued = true
            return
        }
        reloading = true
        Task {
            let result = try? await database.snapshot()
            await MainActor.run {
                self.reloading = false
                if let result {
                    self.snapshot = result
                    self.publish()
                }
                if self.reloadQueued {
                    self.reloadQueued = false
                    self.reload()
                }
            }
        }
    }

    func markOpen(_ conversation: Conversation, userOpened: Bool = false) {
        guard let snapshot else { return }
        var changed = false
        if userOpened, forcedUnread.remove(conversation.key) != nil {
            UserDefaults.standard.set(Array(forcedUnread), forKey: "forcedUnread")
            changed = true
        }
        for id in conversation.chatIDs {
            if let unread = snapshot.unread[id], (seen[String(id)] ?? 0) < unread.maxRowID {
                seen[String(id)] = unread.maxRowID
                changed = true
            }
        }
        if changed {
            UserDefaults.standard.set(seen, forKey: "seenRowIDs")
            publish()
        }
    }

    func markRead(_ conversation: Conversation) {
        forcedUnread.remove(conversation.key)
        UserDefaults.standard.set(Array(forcedUnread), forKey: "forcedUnread")
        markOpen(conversation)
        publish()
    }

    func markUnread(_ conversation: Conversation) {
        forcedUnread.insert(conversation.key)
        UserDefaults.standard.set(Array(forcedUnread), forKey: "forcedUnread")
        publish()
    }

    func toggleMuted(_ conversation: Conversation) {
        if muted.remove(conversation.key) == nil { muted.insert(conversation.key) }
        UserDefaults.standard.set(Array(muted), forKey: "mutedConversations")
        publish()
    }

    func setPinned(_ conversation: Conversation, _ pinned: Bool) {
        if pinned {
            localUnpins.remove(conversation.key)
            if !self.pinned.contains(where: { $0.key == conversation.key }), !localPins.contains(conversation.key) {
                localPins.append(conversation.key)
            }
        } else {
            localPins.removeAll { $0 == conversation.key }
            localUnpins.insert(conversation.key)
        }
        UserDefaults.standard.set(localPins, forKey: "localPins")
        UserDefaults.standard.set(Array(localUnpins), forKey: "localUnpins")
        publish()
    }

    func background(for key: String) -> URL? {
        backgrounds[key].map { URL(fileURLWithPath: $0) }
    }

    func setBackground(_ source: URL?, for key: String) {
        if let old = backgrounds[key] { try? FileManager.default.removeItem(atPath: old) }
        backgrounds[key] = nil
        if let source, let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let folder = support.appendingPathComponent("TeX Messages/Backgrounds", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            if (try? FileManager.default.copyItem(at: source, to: destination)) != nil {
                backgrounds[key] = destination.path
            }
        }
        UserDefaults.standard.set(backgrounds, forKey: "conversationBackgrounds")
    }

    private func publish() {
        guard let snapshot else { return }
        var groups: [String: [ChatRow]] = [:]
        var order: [String] = []
        for chat in snapshot.chats {
            let key: String
            if chat.isGroup {
                key = "group:\(chat.rowID)"
            } else {
                let handle = snapshot.participants[chat.rowID]?.first ?? chat.identifier
                key = Contacts.shared.person(for: handle).map { "person:\($0.id)" } ?? "handle:\(Contacts.key(handle))"
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(chat)
        }

        var total = 0
        conversations = order.compactMap { key in
            guard let chats = groups[key]?.sorted(by: { $0.lastRawDate > $1.lastRawDate }), let latest = chats.first else { return nil }
            guard latest.lastMessageID != nil else { return nil }
            var participants: [String] = []
            for chat in chats {
                for handle in snapshot.participants[chat.rowID] ?? [] where !participants.contains(handle) {
                    participants.append(handle)
                }
            }
            if latest.isGroup == false, participants.isEmpty { participants = [latest.identifier] }
            let unread = chats.reduce(0) { sum, chat in
                guard let info = snapshot.unread[chat.rowID], info.maxRowID > (seen[String(chat.rowID)] ?? 0) else { return sum }
                return sum + info.count
            }
            let forced = forcedUnread.contains(key)
            let isMuted = muted.contains(key)
            if !isMuted { total += max(unread, forced ? 1 : 0) }
            return Conversation(
                key: key,
                chats: chats,
                participants: participants,
                recentSenders: snapshot.recentSenders[latest.rowID] ?? [],
                isGroup: latest.isGroup,
                lastDate: AppleDate.date(latest.lastRawDate),
                preview: snapshot.previews[latest.rowID] ?? "",
                unreadCount: max(unread, forcedUnread.contains(key) ? 1 : 0),
                isMuted: muted.contains(key)
            )
        }
        .sorted { ($0.lastDate ?? .distantPast) > ($1.lastDate ?? .distantPast) }

        var pins: [Conversation] = Self.pinnedIdentifiers().compactMap { identifier in
            let key = Contacts.key(identifier)
            return conversations.first { conversation in
                conversation.chats.contains { $0.identifier == identifier || $0.guid.hasSuffix(identifier) }
                    || (!conversation.isGroup && conversation.participants.contains { Contacts.key($0) == key })
            }
        }
        pins.removeAll { localUnpins.contains($0.key) }
        for key in localPins where !pins.contains(where: { $0.key == key }) {
            if let conversation = conversations.first(where: { $0.key == key }) { pins.append(conversation) }
        }
        pinned = pins

        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
        onConversations?()
    }
}
