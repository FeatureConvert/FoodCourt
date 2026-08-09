import Foundation
import AVFoundation

/// Every player-facing sound in the game, synthesized at launch rather than bundled - short
/// arcade-style tones rendered from sine oscillators need no audio asset, no licensing, and
/// no App Store payload. Mirrors `Haptics` (`Theme.swift`) in spirit: a handful of reusable
/// categories rather than one sound per call site.
enum SoundKind: CaseIterable {
    case tap        // light UI tick - taps, tab switches
    case purchase   // buy/upgrade click
    case reward     // the common success chime
    case bigReward  // prestige, legacy reset, real-money IAP grant, league promotion
    case denied     // insufficient funds, locked, errors
}

/// Owns the audio engine and plays `SoundKind`s. A UI-layer concern exactly like `Haptics` -
/// never called from `GameEngine` or anywhere in `Sources/Core` other than this file; every
/// call site lives in `Sources/UI`, injected the same way `NotificationService` and
/// `CloudSaveService` are.
@MainActor
final class SoundService: ObservableObject {

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private var buffers: [SoundKind: AVAudioPCMBuffer] = [:]

    /// Read fresh on every call rather than cached, so the Settings toggle takes effect
    /// immediately without any observer plumbing between this service and `@AppStorage`.
    /// `@AppStorage` doesn't write to `UserDefaults` until the value is first set, so a
    /// missing key means the default (sound on) still applies.
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "soundEnabled")
    }

    init() {
        // .ambient respects the hardware silent switch and never interrupts whatever the
        // player is already listening to - the right behavior for incidental game SFX.
        // Both calls are non-fatal: if session setup fails, `play()` below detects the
        // engine never started and quietly no-ops rather than crashing the game over sound.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }

        // A small round-robin pool rather than one shared player node - a fast tap-combo
        // burst can fire `.tap` several times a second, and a single node would cut off its
        // own previous sound every time instead of letting short taps layer.
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        for kind in SoundKind.allCases {
            buffers[kind] = Self.buffer(for: kind, format: format)
        }

        try? engine.start()
    }

    func play(_ kind: SoundKind) {
        guard isEnabled, engine.isRunning, let buffer = buffers[kind], !players.isEmpty else { return }
        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        if !player.isPlaying { player.play() }
        // .interrupts so a node that's still finishing an older tap's tail gets superseded
        // immediately rather than queuing a backlog behind it.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    // MARK: Synthesis

    private struct Note {
        let frequency: Double
        /// Offset from the start of the buffer, in seconds.
        let start: Double
        let duration: Double
        /// Exponential decay rate - higher decays faster (snappier, no ring).
        let decay: Double
        let amplitude: Double
    }

    private static func notes(for kind: SoundKind) -> [Note] {
        switch kind {
        case .tap:
            return [
                Note(frequency: 1200, start: 0, duration: 0.06, decay: 32, amplitude: 0.30),
            ]
        case .purchase:
            return [
                Note(frequency: 700, start: 0, duration: 0.05, decay: 22, amplitude: 0.28),
                Note(frequency: 1000, start: 0.04, duration: 0.06, decay: 20, amplitude: 0.30),
            ]
        case .reward:
            return [
                Note(frequency: 1046.50, start: 0, duration: 0.09, decay: 14, amplitude: 0.26),  // C6
                Note(frequency: 1318.51, start: 0.06, duration: 0.09, decay: 14, amplitude: 0.26), // E6
                Note(frequency: 1567.98, start: 0.12, duration: 0.14, decay: 10, amplitude: 0.28), // G6
            ]
        case .bigReward:
            return [
                Note(frequency: 523.25, start: 0, duration: 0.09, decay: 14, amplitude: 0.24),   // C5
                Note(frequency: 659.25, start: 0.07, duration: 0.09, decay: 14, amplitude: 0.24), // E5
                Note(frequency: 784.00, start: 0.14, duration: 0.09, decay: 14, amplitude: 0.24), // G5
                Note(frequency: 1046.50, start: 0.21, duration: 0.12, decay: 12, amplitude: 0.26), // C6
                // Held chord tail - three notes starting together and ringing out.
                Note(frequency: 1046.50, start: 0.34, duration: 0.22, decay: 6, amplitude: 0.18),
                Note(frequency: 1318.51, start: 0.34, duration: 0.22, decay: 6, amplitude: 0.16),
                Note(frequency: 1567.98, start: 0.34, duration: 0.22, decay: 6, amplitude: 0.16),
            ]
        case .denied:
            // Two close, detuned frequencies summed for a short buzzy beat - dissonant on
            // purpose, and cut off blunt rather than left to ring, so it reads as "no."
            return [
                Note(frequency: 180, start: 0, duration: 0.14, decay: 16, amplitude: 0.26),
                Note(frequency: 190, start: 0, duration: 0.14, decay: 16, amplitude: 0.22),
            ]
        }
    }

    private static func buffer(for kind: SoundKind, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        renderBuffer(notes: notes(for: kind), format: format, sampleRate: format.sampleRate)
    }

    /// Sums each note's sine wave - a short linear attack into an exponential decay envelope
    /// - into one buffer. Overlapping notes (the `.bigReward` chord tail) add together and
    /// the mix is clamped afterward so they never clip.
    private static func renderBuffer(notes: [Note], format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer? {
        let totalDuration = notes.map { $0.start + $0.duration }.max() ?? 0
        let frameCount = AVAudioFrameCount(max(1, (totalDuration * sampleRate).rounded(.up)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) { channel[frame] = 0 }

        let attack = 0.005
        for note in notes {
            let startFrame = Int((note.start * sampleRate).rounded())
            let noteFrameCount = Int((note.duration * sampleRate).rounded())
            for i in 0..<noteFrameCount {
                let frame = startFrame + i
                guard frame >= 0, frame < Int(frameCount) else { continue }
                let t = Double(i) / sampleRate
                let attackRamp = min(1, t / attack)
                let envelope = attackRamp * exp(-note.decay * t)
                let sample = sin(2 * .pi * note.frequency * t) * envelope * note.amplitude
                channel[frame] += Float(sample)
            }
        }

        for frame in 0..<Int(frameCount) {
            channel[frame] = max(-1, min(1, channel[frame]))
        }

        return buffer
    }
}
