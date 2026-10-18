@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Foundation
import os
@preconcurrency import SoundpipeAudioKit

/// Six strings and four melody voices, through `ToyAudio`.
///
/// AudioKit's own `PluckedString` cannot go below 110 Hz (the low E is 82 Hz)
/// and restarts from raw noise on every trigger, so the strings are an
/// extended Karplus-Strong model (`StringsDSP`): exact tuning (allpass in the
/// loop), a pick-position comb and a velocity low-pass on the excitation
/// (soft = warm, hard = bright), a decay per string, and two voices per string:
/// a new pluck takes the free voice while the ringing one is damped over 60 ms,
/// like a pick touching the string, so nothing clicks. Around them `GuitarDSP`
/// builds the guitar: a wooden body of eight modes, the open strings humming
/// along, the pick's tick, a chorus and a small room; the shared reverb adds
/// the rest. No two plucks are quite the same loudness.
@MainActor
final class GuitarSynth {
    private let audio: ToyAudio
    private var graph: (guitar: RenderNode<GuitarDSP>, out: Fader)?
    private var running = false
    private var turn = [Int](repeating: 0, count: 6)
    private var melodyVoice = 0

    init(audio: ToyAudio = .shared) {
        self.audio = audio
    }

    func start() {
        guard !running else { return }
        running = true
        let g = graph ?? build()
        graph = g
        g.out.gain = 0.9
        audio.attach(g.out)
        audio.setRoom(.small)
        audio.acquire()
    }

    func stop() {
        guard running, let g = graph else { return }
        running = false
        g.guitar.dsp.strings.send(.init(kind: .silence))
        audio.detach(g.out)
        audio.release()
    }

    /// Plucks string `index` (0 = low E) at `frequency`; `velocity` 0...1 sets loudness and brightness.
    func pluck(string index: Int, frequency: Double, velocity: Double) {
        guard running, let g = graph, (0..<6).contains(index), frequency > 20 else { return }
        let fresh = index * 2 + turn[index], old = index * 2 + (1 - turn[index])
        turn[index] ^= 1
        let lane = Float(index) / 5
        let pan = (lane - 0.5) * 0.7
        // a hand never plucks twice the same
        let v = Float(min(1, max(0.1, velocity * Double.random(in: 0.88...1.08))))
        g.guitar.dsp.strings.send(.init(kind: .damp, voice: Int32(old), time: 0.06))
        g.guitar.dsp.strings.send(.init(kind: .pluck, voice: Int32(fresh), frequency: Float(frequency), velocity: v, pan: pan, t60: 4.6 - 2.2 * lane))
        g.guitar.dsp.picks.send(.init(velocity: v, pan: pan))
    }

    /// A melody note on one of four extra voices, round robin so notes overlap.
    func melody(midi: Int, velocity: Double) {
        guard running, let g = graph else { return }
        melodyVoice = (melodyVoice + 1) % 4
        let v = Float(min(1, max(0.1, velocity * Double.random(in: 0.9...1.06))))
        g.guitar.dsp.strings.send(.init(kind: .pluck, voice: Int32(12 + melodyVoice), frequency: Float(Chord.frequency(midi: midi)), velocity: v, pan: 0.12, t60: 2.6))
        g.guitar.dsp.picks.send(.init(velocity: v * 0.7, pan: 0.12))
    }

    /// A string not in the chord: damped quickly.
    func mute(string index: Int) {
        guard running, let g = graph, (0..<6).contains(index) else { return }
        g.guitar.dsp.strings.send(.init(kind: .damp, voice: Int32(index * 2), time: 0.08))
        g.guitar.dsp.strings.send(.init(kind: .damp, voice: Int32(index * 2 + 1), time: 0.08))
    }

    private func build() -> (guitar: RenderNode<GuitarDSP>, out: Fader) {
        let format = AudioKit.Settings.audioFormat
        let guitar = RenderNode(GuitarDSP(sampleRate: Float(format.sampleRate)), format: format)
        // the body spreads the strings' energy: as loud as the bare strings were
        return (guitar, Fader(guitar, gain: 1.5))
    }
}

