@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Foundation

/// The toys' recorded sounds, played through `ToyAudio`.
///
/// Each sound has three players used in turn, so playing it again never cuts
/// the one still ringing (that cut was a click). Each player runs through a
/// varispeed for the small random pitch, and the bank has one output fader.
@MainActor
final class SoundBank {
    static let names = ["splash", "plop", "bump", "giggle", "chime"]

    private final class Slot {
        let player: AudioPlayer
        let speed: VariSpeed

        init?(url: URL, buffered: Bool) {
            guard let player = AudioPlayer(url: url, buffered: buffered) else { return nil }
            self.player = player
            speed = VariSpeed(player)
        }
    }

    private let audio: ToyAudio
    private let names: [String]
    private let copies: Int
    private let buffered: Bool
    private var slots: [String: [Slot]] = [:]
    private var turn: [String: Int] = [:]
    private var out: Fader?
    private var loaded = false

    /// `buffered: false` streams long clips from disk instead of holding them in memory.
    init(audio: ToyAudio = .shared, names: [String] = SoundBank.names, copies: Int = 3, buffered: Bool = true) {
        self.audio = audio
        self.names = names
        self.copies = copies
        self.buffered = buffered
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        if out == nil { build() }
        if let out {
            out.gain = 1
            audio.attach(out)
        }
        audio.acquire()
    }

    func play(_ name: String, volume: Float = 1, rate: Double = 1) {
        guard loaded, let pool = slots[name], !pool.isEmpty else { return }
        let i = turn[name, default: 0]
        turn[name] = (i + 1) % pool.count
        let slot = pool[i]
        if slot.player.isPlaying { slot.player.stop() }
        slot.speed.rate = AUValue(min(2, max(0.5, rate)))
        slot.player.volume = AUValue(min(1, max(0, volume)))
        slot.player.play()
    }

    /// The length of a sound, in seconds at normal speed.
    func duration(_ name: String) -> TimeInterval {
        slots[name]?.first?.player.duration ?? 0
    }

    func has(_ name: String) -> Bool { slots[name]?.isEmpty == false }

    /// Stops what is playing (the bank stays loaded).
    func stopAll() {
        for pool in slots.values {
            for slot in pool where slot.player.isPlaying { slot.player.stop() }
        }
    }

    func unload() {
        guard loaded else { return }
        loaded = false
        if let out { audio.detach(out) }
        audio.release()
    }

    private func build() {
        var nodes: [Node] = []
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { continue }
            let pool = (0..<copies).compactMap { _ in Slot(url: url, buffered: buffered) }
            slots[name] = pool
            nodes += pool.map(\.speed)
        }
        let mix = Mixer(nodes, name: "samples")
        out = Fader(mix, gain: 1)
    }
}
