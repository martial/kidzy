@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Foundation
import os
@preconcurrency import SoundpipeAudioKit

/// Six strings and four melody voices, through `ToyAudio`: a real nylon-string
/// guitar, from recorded notes (`NylonDSP`). Each string has three voices: a
/// new pluck takes the oldest while the ringing ones are damped over 60 ms,
/// like a finger touching the string, so nothing clicks. No two plucks are
/// quite the same loudness. The shared reverb gives the room.
@MainActor
final class GuitarSynth {
    private let audio: ToyAudio
    private var graph: (guitar: RenderNode<NylonDSP>, out: Fader)?
    private var running = false
    private var turn = [Int](repeating: 0, count: 6)
    private var melodyVoice = 0
    static let voicesPerString = 3

    init(audio: ToyAudio = .shared) {
        self.audio = audio
    }

    func start() {
        guard !running else { return }
        running = true
        let g = graph ?? build()
        graph = g
        audio.attach(g.out)
        audio.setRoom(.small)
        audio.acquire()
    }

    func stop() {
        guard running, let g = graph else { return }
        running = false
        g.guitar.dsp.queue.send(.init(kind: .silence))
        audio.detach(g.out)
        audio.release()
    }

    /// Plucks string `index` (0 = low E) at `frequency`; `velocity` 0...1 sets loudness and brightness.
    func pluck(string index: Int, frequency: Double, velocity: Double) {
        guard running, let g = graph, (0..<6).contains(index), frequency > 20 else { return }
        let n = Self.voicesPerString
        turn[index] = (turn[index] + 1) % n
        let fresh = index * n + turn[index]
        for k in 0..<n where index * n + k != fresh {
            g.guitar.dsp.queue.send(.init(kind: .damp, voice: Int32(index * n + k), time: 0.06))
        }
        let pan = (Float(index) / 5 - 0.5) * 0.7
        // a hand never plucks twice the same
        let v = Float(min(1, max(0.1, velocity * Double.random(in: 0.88...1.08))))
        g.guitar.dsp.queue.send(.init(kind: .pluck, voice: Int32(fresh), frequency: Float(frequency), velocity: v, pan: pan))
    }

    /// A melody note on one of four extra voices, round robin so notes overlap.
    func melody(midi: Int, velocity: Double) {
        guard running, let g = graph else { return }
        melodyVoice = (melodyVoice + 1) % 4
        let voice = Int32(6 * Self.voicesPerString + melodyVoice)
        let v = Float(min(1, max(0.1, velocity * Double.random(in: 0.9...1.06))))
        g.guitar.dsp.queue.send(.init(kind: .pluck, voice: voice, frequency: Float(Chord.frequency(midi: midi)), velocity: v, pan: 0.12))
    }

    /// A string not in the chord: damped quickly.
    func mute(string index: Int) {
        guard running, let g = graph, (0..<6).contains(index) else { return }
        for k in 0..<Self.voicesPerString {
            g.guitar.dsp.queue.send(.init(kind: .damp, voice: Int32(index * Self.voicesPerString + k), time: 0.08))
        }
    }

    private func build() -> (guitar: RenderNode<NylonDSP>, out: Fader) {
        let format = AudioKit.Settings.audioFormat
        let guitar = RenderNode(NylonDSP(sampleRate: Float(format.sampleRate)), format: format)
        return (guitar, Fader(guitar, gain: 1.4))
    }
}
