import AVFoundation
import Foundation

/// The toy's little sounds, preloaded, played with a touch of random pitch.
/// Uses the ambient category so they respect the silent switch and mix with music.
@MainActor
final class SoundBank {
    static let names = ["splash", "plop", "bump", "giggle", "chime"]
    private var players: [String: [AVAudioPlayer]] = [:]
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        for name in Self.names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { continue }
            players[name] = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.enableRate = true
                p?.prepareToPlay()
                return p
            }
        }
    }

    func play(_ name: String, volume: Float = 1, rate: Double = 1) {
        guard let pool = players[name] else { return }
        let p = pool.first { !$0.isPlaying } ?? pool.first
        guard let p else { return }
        p.currentTime = 0
        p.volume = volume
        p.rate = Float(rate)
        p.play()
    }

    func unload() {
        players.removeAll()
        loaded = false
    }
}
