import AVFoundation
import AVKit
import SwiftUI

/// The sounds the scoreboard plays, made in code (no sound files to ship).
enum GameSound: String {
    case whistle, doubleWhistle, horn, longHorn
}

/// Speaks announcements and plays whistles and horns, one after another, through whatever the phone is connected to
/// (the speaker, or a Bluetooth speaker the user picked). Music playing in another app is lowered while it speaks and comes back after.
final class AudioAnnouncer: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = AudioAnnouncer()

    private enum Item { case sound(GameSound), speech(String) }

    private var queue: [Item] = []
    private var busy = false
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var soundCache: [GameSound: Data] = [:]
    private var watchdog: DispatchWorkItem?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ sound: GameSound) { enqueue(.sound(sound)) }
    func speak(_ text: String) { enqueue(.speech(text)) }

    private func enqueue(_ item: Item) {
        DispatchQueue.main.async {
            self.queue.append(item)
            if !self.busy { self.next() }
        }
    }

    private func next() {
        guard !queue.isEmpty else {
            busy = false
            watchdog?.cancel()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)   // music in other apps comes back
            return
        }
        busy = true
        let item = queue.removeFirst()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        var expected: TimeInterval = 8
        switch item {
        case .sound(let sound):
            let data = soundCache[sound] ?? Self.wav(for: sound)
            soundCache[sound] = data
            if let player = try? AVAudioPlayer(data: data) {
                player.delegate = self
                self.player = player
                expected = player.duration + 2
                player.play()
            } else { finished(); return }
        case .speech(let text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96      // a little slower than the default sounds less hurried
            utterance.pitchMultiplier = 1.0
            utterance.preUtteranceDelay = 0.1
            utterance.volume = 1
            expected = max(6, Double(text.count) * 0.12)
            synthesizer.speak(utterance)
        }
        // if a callback never comes, do not block the queue
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finished() }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + expected, execute: work)
    }

    private func finished() {
        DispatchQueue.main.async { self.next() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finished() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finished() }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished() }

    // MARK: - Voices
    static let voiceKey = "speechVoiceID"
    
    /// The voices installed for the app's language, best first: premium, then enhanced, then standard.
    static func voices(for language: AppLanguage = .current) -> [AVSpeechSynthesisVoice] {
        let prefix = language.code
        let regions = prefix == "es" ? ["es-MX", "es-US", "es-ES"] : ["en-US", "en-GB", "en-AU", "en-CA"]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && $0.identifier.hasPrefix("com.apple.") && !$0.identifier.contains("eloquence") }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue { return lhs.quality.rawValue > rhs.quality.rawValue }
                let l = regions.firstIndex(of: lhs.language) ?? 99, r = regions.firstIndex(of: rhs.language) ?? 99
                return l != r ? l < r : lhs.name < rhs.name
            }
    }
    
    /// The voice chosen on the Alerts and Sound page, or the best one installed.
    static func voice(for language: AppLanguage = .current) -> AVSpeechSynthesisVoice? {
        let available = voices(for: language)
        if let id = UserDefaults.standard.string(forKey: voiceKey), !id.isEmpty, let chosen = available.first(where: { $0.identifier == id }) { return chosen }
        return available.first ?? AVSpeechSynthesisVoice(language: language.code == "es" ? "es-MX" : "en-US")
    }
    
    // MARK: - Sounds made in code
    private static func wav(for sound: GameSound) -> Data {
        let rate = 44_100.0
        var samples: [Int16] = []

        /// A note of `seconds` with a short fade in and out.
        func note(_ seconds: Double, _ wave: (Double) -> Double) {
            let count = Int(seconds * rate)
            for i in 0..<count {
                let t = Double(i) / rate
                let envelope = max(0, min(1, t / 0.02, (seconds - t) / 0.08))
                samples.append(Int16(max(-1, min(1, wave(t) * envelope)) * 0.8 * 32_767))
            }
        }
        func silence(_ seconds: Double) { samples += [Int16](repeating: 0, count: Int(seconds * rate)) }

        // a referee's pea whistle: a high tone wobbling about 28 times a second
        func whistle(_ seconds: Double) {
            note(seconds) { t in 0.8 * sin(2 * .pi * 3_000 * t + 4 * sin(2 * .pi * 28 * t)) + 0.15 * sin(2 * .pi * 6_000 * t) }
        }
        // an air horn: two slightly different low tones with their harmonics, so they beat
        func horn(_ seconds: Double) {
            note(seconds) { t in
                var sum = 0.0
                for k in 1...6 { sum += (sin(2 * .pi * 392 * Double(k) * t) + sin(2 * .pi * 397 * Double(k) * t)) / Double(k) }
                return sum / 3.2
            }
        }

        switch sound {
        case .whistle: whistle(0.7)
        case .doubleWhistle: whistle(0.35); silence(0.15); whistle(0.35)
        case .horn: horn(1.2)
        case .longHorn: horn(2.4)
        }

        var data = Data()
        func append32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func append16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let byteCount = UInt32(samples.count * 2)
        data.append("RIFF".data(using: .ascii)!); append32(36 + byteCount); data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!); append32(16); append16(1); append16(1); append32(UInt32(rate)); append32(UInt32(rate) * 2); append16(2); append16(16)
        data.append("data".data(using: .ascii)!); append32(byteCount)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}

/// The system's output picker (AirPlay and Bluetooth speakers). A Bluetooth speaker is paired once in iOS Settings, then chosen here.
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.activeTintColor = .systemBlue
        picker.tintColor = .label
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
