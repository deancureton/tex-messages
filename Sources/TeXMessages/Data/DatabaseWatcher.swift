import CoreServices
import Foundation

final class DatabaseWatcher {
    private let directory: String
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var timer: Timer?

    init(databasePath: String, onChange: @escaping () -> Void) {
        directory = (databasePath as NSString).deletingLastPathComponent
        self.onChange = onChange
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DatabaseWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
        }
        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [directory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.03,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.onChange() }
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }
}
