@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Foundation

/// The sea's sound, through `ToyAudio`: the water follows the simulation every
/// frame (see `SeaAcoustics`), and the toy's events (a poke, a droplet falling
/// back, the boat's motor and knocks) are sent as they happen. Synthesis: `SeaDSP`.
@MainActor
final class SeaSound {
    private let audio: ToyAudio
    private var graph: (sea: RenderNode<SeaDSP>, out: Fader)?
    private var running = false

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
        send(.water, 0)
    }

    func stop() {
        guard running, let g = graph else { return }
        running = false
        g.sea.dsp.queue.send(.init(kind: .silence))
        audio.detach(g.out)
        audio.release()
    }

    /// Every frame: how much the water moves, 0...1.
    func water(_ wash: Double) { send(.water, Float(wash)) }

    /// A wave against a wall, or the water lapping on the hull.
    func hit(_ h: SeaAcoustics.Hit) {
        switch h.place {
        case .leftWall: send(.slap, Float(h.strength), pan: -0.75)
        case .rightWall: send(.slap, Float(h.strength), pan: 0.75)
        case .hull(let x): send(.lap, Float(h.strength), pan: pan(x))
        }
    }

    /// A finger pokes the water at `x` (0...1 across the screen).
    func poke(x: Double, strength: Double = 0.8) { send(.poke, Float(strength), pan: pan(x)) }

    /// A droplet falls back into the sea.
    func droplet(x: Double) { send(.plip, Float.random(in: 0.3...1), pan: pan(x)) }

    /// The boat hits the side.
    func knock(x: Double, strength: Double) { send(.knock, Float(strength), pan: pan(x)) }

    /// The boat's motor while it is held: `speed` 0...1.
    func motor(x: Double, speed: Double) { send(.motor, Float(min(1, max(0, speed))), pan: pan(x)) }

    func motorOff() { send(.motorOff, 0) }

    private func pan(_ x: Double) -> Float { Float(min(1, max(-1, (x - 0.5) * 1.4))) }

    private func send(_ kind: SeaDSP.Command.Kind, _ a: Float, pan: Float = 0) {
        guard running, let g = graph else { return }
        g.sea.dsp.queue.send(.init(kind: kind, a: a, pan: pan))
    }

    private func build() -> (sea: RenderNode<SeaDSP>, out: Fader) {
        let format = AudioKit.Settings.audioFormat
        let sea = RenderNode(SeaDSP(sampleRate: Float(format.sampleRate)), format: format)
        return (sea, Fader(sea, gain: 1))
    }
}
