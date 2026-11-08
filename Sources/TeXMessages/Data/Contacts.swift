import AppKit
import Contacts

struct Person {
    let id: String
    let name: String
    let firstName: String
    let initials: String
    let imageData: Data?
    let handles: [String]
}

final class Contacts {
    static let shared = Contacts()

    private let lock = NSLock()
    private var people: [String: Person] = [:]
    private var everyone: [Person] = []
    private var images: [String: NSImage] = [:]

    func load(completion: @escaping () -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.fetch()
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    private func fetch() {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]
        var map: [String: Person] = [:]
        var list: [Person] = []
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            let full = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            guard !full.isEmpty else { return }
            let phones = contact.phoneNumbers.map(\.value.stringValue)
            let emails = contact.emailAddresses.map { $0.value as String }
            let given = contact.nickname.isEmpty ? contact.givenName : contact.nickname
            let initials = [contact.givenName.first, contact.familyName.first].compactMap { $0 }.map(String.init).joined()
            let person = Person(
                id: contact.identifier,
                name: contact.nickname.isEmpty ? full : contact.nickname,
                firstName: given.isEmpty ? full : given,
                initials: initials.isEmpty ? String(full.prefix(1)) : initials.uppercased(),
                imageData: contact.thumbnailImageData,
                handles: phones + emails
            )
            list.append(person)
            for handle in phones + emails { map[Self.key(handle)] = person }
        }
        lock.withLock {
            people = map
            everyone = list
        }
    }

    static func key(_ handle: String) -> String {
        if handle.contains("@") { return handle.lowercased() }
        let digits = handle.filter(\.isNumber)
        return digits.count >= 10 ? String(digits.suffix(10)) : (digits.isEmpty ? handle.lowercased() : digits)
    }

    func person(for handle: String) -> Person? {
        lock.withLock { people[Self.key(handle)] }
    }

    func displayName(for handle: String) -> String {
        person(for: handle)?.name ?? Self.formatted(handle)
    }

    func shortName(for handle: String) -> String {
        person(for: handle)?.firstName ?? Self.formatted(handle)
    }

    func image(for person: Person) -> NSImage? {
        guard let data = person.imageData else { return nil }
        return lock.withLock {
            if let image = images[person.id] { return image }
            let image = NSImage(data: data)
            images[person.id] = image
            return image
        }
    }

    func matches(prefix: String) -> [(name: String, handle: String)] {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return [] }
        let list = lock.withLock { everyone }
        return list
            .filter { $0.name.lowercased().contains(needle) || $0.handles.contains { $0.lowercased().contains(needle) } }
            .prefix(12)
            .compactMap { person in person.handles.first.map { (person.name, $0) } }
    }

    func resolve(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@") || trimmed.contains(where: \.isNumber) { return trimmed }
        return matches(prefix: trimmed).first?.handle ?? trimmed
    }

    static func formatted(_ handle: String) -> String {
        let digits = handle.filter(\.isNumber)
        guard !handle.contains("@"), handle.hasPrefix("+1"), digits.count == 11 else { return handle }
        let d = Array(digits.dropFirst())
        return "+1 (\(String(d[0..<3]))) \(String(d[3..<6]))-\(String(d[6..<10]))"
    }
}
