import Foundation

enum SendError: Error, LocalizedError {
    case script(String)

    var errorDescription: String? {
        if case .script(let message) = self { return message }
        return nil
    }
}

enum MessageSender {
    private static let isFixture = ChatDatabase.isFixture

    private static let textToChat = """
        on run argv
            tell application "Messages" to send (item 2 of argv) to chat id (item 1 of argv)
        end run
        """

    private static let textToHandle = """
        on run argv
            tell application "Messages"
                set svc to 1st account whose service type = iMessage
                send (item 2 of argv) to participant (item 1 of argv) of svc
            end tell
        end run
        """

    private static let fileToChat = """
        on run argv
            tell application "Messages" to send (POSIX file (item 2 of argv)) to chat id (item 1 of argv)
        end run
        """

    private static let fileToHandle = """
        on run argv
            tell application "Messages"
                set svc to 1st account whose service type = iMessage
                send (POSIX file (item 2 of argv)) to participant (item 1 of argv) of svc
            end tell
        end run
        """

    static func send(text: String, chatGuid: String, handle: String?, completion: @escaping (Error?) -> Void) {
        deliver(payload: text, primary: (textToChat, chatGuid), fallback: handle.map { (textToHandle, $0) }, completion: completion)
    }

    static func send(file: URL, chatGuid: String, handle: String?, completion: @escaping (Error?) -> Void) {
        background(completion) {
            let staged = try stage(file)
            try attempt(payload: staged.path, primary: (fileToChat, chatGuid), fallback: handle.map { (fileToHandle, $0) })
        }
    }

    static func sendNew(text: String, to handle: String, completion: @escaping (Error?) -> Void) {
        deliver(payload: text, primary: (textToHandle, handle), fallback: nil, completion: completion)
    }

    static func sendNew(file: URL, to handle: String, completion: @escaping (Error?) -> Void) {
        background(completion) {
            let staged = try stage(file)
            try attempt(payload: staged.path, primary: (fileToHandle, handle), fallback: nil)
        }
    }

    private static func deliver(payload: String, primary: (String, String), fallback: (String, String)?, completion: @escaping (Error?) -> Void) {
        background(completion) { try attempt(payload: payload, primary: primary, fallback: fallback) }
    }

    private static func background(_ completion: @escaping (Error?) -> Void, work: @escaping () throws -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try work()
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    private static func attempt(payload: String, primary: (String, String), fallback: (String, String)?) throws {
        guard !isFixture else { return }
        do {
            try run(script: primary.0, target: primary.1, payload: payload)
        } catch {
            guard let fallback else { throw error }
            try run(script: fallback.0, target: fallback.1, payload: payload)
        }
    }

    private static func stage(_ file: URL) throws -> URL {
        guard !isFixture else { return file }
        let directory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Messages/Attachments/TeXMessages/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    private static func run(script: String, target: String, payload: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, target, payload]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SendError.script(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
