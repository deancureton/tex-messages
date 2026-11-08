import AppKit
import AVFoundation

final class VoicePlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayback()
    static let changed = Notification.Name("VoicePlaybackChanged")

    private var player: AVAudioPlayer?
    private var url: URL?
    private var timer: Timer?

    func isPlaying(_ candidate: URL) -> Bool {
        url == candidate && player?.isPlaying == true
    }

    func elapsed(_ candidate: URL) -> TimeInterval? {
        url == candidate ? player?.currentTime : nil
    }

    func progress(_ candidate: URL) -> Double {
        guard url == candidate, let player, player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }

    @discardableResult
    private func load(_ candidate: URL) -> Bool {
        if url == candidate, player != nil { return true }
        guard let next = try? AVAudioPlayer(contentsOf: candidate) else { return false }
        stop()
        next.delegate = self
        next.prepareToPlay()
        player = next
        url = candidate
        return true
    }

    func toggle(_ candidate: URL) -> Bool {
        guard load(candidate), let player else { return false }
        if player.isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        post()
        return true
    }

    func seek(_ candidate: URL, to fraction: Double) {
        guard load(candidate), let player else { return }
        player.currentTime = max(0, min(1, fraction)) * player.duration
        post()
    }

    func stop() {
        player?.stop()
        player = nil
        url = nil
        stopTimer()
        post()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }

    private func startTimer() {
        stopTimer()
        let next = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.post() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func post() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

enum VoiceWaveform {
    struct Info {
        let levels: [CGFloat]
        let duration: TimeInterval
    }

    private static let barCount = 36
    private static var cache: [URL: Info] = [:]
    private static let queue = DispatchQueue(label: "voice.waveform", qos: .userInitiated)

    static func load(_ url: URL, completion: @escaping (Info?) -> Void) {
        if let cached = cache[url] {
            completion(cached)
            return
        }
        queue.async {
            let info = read(url)
            DispatchQueue.main.async {
                if let info { cache[url] = info }
                completion(info)
            }
        }
    }

    private static func read(_ url: URL) -> Info? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        let step = max(1, frames / barCount)
        var levels = stride(from: 0, to: step * barCount, by: step).map { start -> CGFloat in
            let end = min(frames, start + step)
            guard start < end else { return 0 }
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            return CGFloat(sqrt(sum / Float(end - start)))
        }
        let peak = max(levels.max() ?? 0, 0.0001)
        levels = levels.map { max(0.14, min(1, $0 / peak)) }
        return Info(levels: levels, duration: Double(file.length) / file.processingFormat.sampleRate)
    }
}

final class VoiceWaveformView: NSView {
    var levels: [CGFloat] = [] { didSet { needsDisplay = true } }
    var progress: CGFloat = 0 {
        didSet {
            if progress != oldValue { needsDisplay = true }
        }
    }
    var color = NSColor.labelColor { didSet { needsDisplay = true } }
    var onSeek: ((Double) -> Void)?

    override var isFlipped: Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Playback position" }
    override func accessibilityValue() -> Any? { "\(Int(progress * 100))%" }

    override func accessibilityPerformIncrement() -> Bool {
        onSeek?(Double(progress) + 0.1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        onSeek?(Double(progress) - 0.1)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let count = levels.isEmpty ? 36 : levels.count
        let pitch = bounds.width / CGFloat(count)
        let barWidth = min(2, pitch * 0.6)
        for index in 0..<count {
            let level = levels.isEmpty ? 0.14 : levels[index]
            let height = max(2, level * bounds.height)
            let x = CGFloat(index) * pitch
            let rect = NSRect(x: x, y: (bounds.height - height) / 2, width: barWidth, height: height)
            let played = progress > 0 && x / bounds.width <= progress
            color.withAlphaComponent(played ? 1 : 0.45).setFill()
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    private func seek(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onSeek?(Double(point.x / max(bounds.width, 1)))
    }

    override func mouseDown(with event: NSEvent) { seek(event) }
    override func mouseDragged(with event: NSEvent) { seek(event) }
}

final class VoiceMessageView: NSView {
    private let button = NSButton()
    private let waveform = VoiceWaveformView()
    private let timeLabel = NSTextField(labelWithString: "")
    private var url: URL?
    private var duration: TimeInterval?
    var leadingInset: CGFloat = 0 { didSet { needsLayout = true } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePlayback)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.alignment = .right
        waveform.onSeek = { [weak self] fraction in
            guard let self, let url = self.url else { return }
            VoicePlayback.shared.seek(url, to: fraction)
        }
        for view in [button, waveform, timeLabel] as [NSView] { addSubview(view) }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: VoicePlayback.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    func configure(url next: URL, color: NSColor) {
        url = next
        duration = nil
        waveform.levels = []
        waveform.color = color
        button.contentTintColor = color
        timeLabel.textColor = color.withAlphaComponent(0.8)
        refresh()
        VoiceWaveform.load(next) { [weak self] info in
            guard let self, self.url == next else { return }
            self.waveform.levels = info?.levels ?? []
            self.duration = info?.duration
            self.refresh()
        }
    }

    @objc private func togglePlayback() {
        guard let url else { return }
        if !VoicePlayback.shared.toggle(url) { NSWorkspace.shared.open(url) }
    }

    @objc private func refresh() {
        guard let url else { return }
        let playing = VoicePlayback.shared.isPlaying(url)
        let name = playing ? "pause.fill" : "play.fill"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        button.setAccessibilityLabel(playing ? "Pause voice message" : "Play voice message")
        waveform.progress = CGFloat(VoicePlayback.shared.progress(url))
        let elapsed = VoicePlayback.shared.elapsed(url) ?? 0
        timeLabel.stringValue = (elapsed > 0 || playing) ? Self.format(elapsed) : duration.map(Self.format) ?? ""
    }

    private static func format(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        button.frame = NSRect(x: leadingInset + 8, y: (height - 26) / 2, width: 26, height: 26)
        let timeWidth: CGFloat = 38
        timeLabel.frame = NSRect(x: bounds.width - timeWidth - 12, y: (height - 16) / 2, width: timeWidth, height: 16)
        let waveX = leadingInset + 40
        waveform.frame = NSRect(x: waveX, y: (height - 22) / 2, width: max(0, timeLabel.frame.minX - 6 - waveX), height: 22)
    }
}
