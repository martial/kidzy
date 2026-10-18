@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Foundation
@preconcurrency import SoundpipeAudioKit

/// What painting sounds like: a brush per finger, on paper, through `ToyAudio`.
/// Nothing musical: the sound is the stroke itself (see `BrushDSP`).
@MainActor
final class BrushSynth {
    private let audio: ToyAudio
    private var graph: (brush: RenderNode<BrushDSP>, out: Fader)?
    private var running = false
    /// finger id → voice
    private var fingers: [Int: Int32] = [:]
    private var lastUsed = [Int](repeating: 0, count: BrushDSP.voiceCount)
    private var clock = 0

    init(audio: ToyAudio = .shared) {
        self.audio = audio
    }

    func start() {
        guard !running else { return }
        running = true
        let g = graph ?? build()
        graph = g
        audio.attach(g.out)
        audio.setRoom(.dry)
        audio.acquire()
    }

    func stop() {
        guard running, let g = graph else { return }
        running = false
        fingers.removeAll()
        g.brush.dsp.queue.send(.init(kind: .silence))
        audio.detach(g.out)
        audio.release()
    }

    /// The brush lands at `x` (0...1, left to right).
    func began(id: Int, x: Double) {
        guard running, let g = graph else { return }
        let voice = fingers[id] ?? freeVoice()
        fingers[id] = voice
        clock += 1
        lastUsed[Int(voice)] = clock
        g.brush.dsp.queue.send(.init(kind: .down, voice: voice, pan: pan(x)))
    }

    /// The brush moves: `speed` in points per second.
    func moved(id: Int, x: Double, speed: Double) {
        guard running, let g = graph else { return }
        guard let voice = fingers[id] else {
            began(id: id, x: x)
            return
        }
        clock += 1
        lastUsed[Int(voice)] = clock
        let s = Float(min(1, max(0, speed / 1600)))
        g.brush.dsp.queue.send(.init(kind: .move, voice: voice, speed: s, pan: pan(x)))
    }

    func ended(id: Int) {
        guard let g = graph, let voice = fingers.removeValue(forKey: id) else { return }
        g.brush.dsp.queue.send(.init(kind: .up, voice: voice))
    }

    private func pan(_ x: Double) -> Float { Float(min(1, max(-1, (x - 0.5) * 1.4))) }

    private func freeVoice() -> Int32 {
        let busy = Set(fingers.values)
        let candidates = (0..<BrushDSP.voiceCount).filter { !busy.contains(Int32($0)) }
        let pool = candidates.isEmpty ? Array(0..<BrushDSP.voiceCount) : candidates
        return Int32(pool.min(by: { lastUsed[$0] < lastUsed[$1] })!)
    }

    private func build() -> (brush: RenderNode<BrushDSP>, out: Fader) {
        let format = AudioKit.Settings.audioFormat
        let brush = RenderNode(BrushDSP(sampleRate: Float(format.sampleRate)), format: format)
        // phone speakers: nothing below the wet squish, a little air on top
        let low = HighPassButterworthFilter(brush, cutoffFrequency: 140)
        let air = HighShelfParametricEqualizerFilter(low, centerFrequency: 6000, gain: 1.15, q: 0.7)
        return (brush, Fader(air, gain: 1))
    }
}
