@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
@preconcurrency import DunneAudioKit
import Foundation
@preconcurrency import SoundpipeAudioKit

/// One voice per finger (and one for the boat), on AudioKit oscillators.
///
/// Each voice is a morphing wavetable oscillator (round → bright → bell, by the
/// finger's direction) through a panner. Every change is a sample-accurate ramp:
/// pitch glides, loudness has an attack and a release, and a stolen voice fades
/// for 12 ms before it takes its new note, so nothing clicks. The dreamy style
/// adds a chorus (the detuned twin) and a ping-pong echo; the shared reverb and
/// the master limiter come from `ToyAudio`.
@MainActor
final class FingerSynth {
    enum Style {
        case playful   // quick notes, a boing on touch
        case dreamy    // slow attack and release, chorus, octave shimmer, stereo echo
    }

    static let voiceCount = 12

    var style: Style = .playful {
        didSet { applyStyle() }
    }

    private let audio: ToyAudio
    private var graph: Graph?
    private var running = false

    private final class Voice {
        let osc: MorphingOscillator
        let panner: Panner
        var id = -1
        var active = false
        var since = Date.distantPast
        var silentAt = Date.distantPast

        init(tables: [Table]) {
            osc = MorphingOscillator(waveformArray: tables, frequency: 220, amplitude: 0, index: 1)
            panner = Panner(osc, pan: 0)
        }
    }

    private struct Graph {
        let voices: [Voice]
        let mix: Mixer
        let chorus: Chorus
        let echo: StereoDelay
        let out: Fader
    }

    init(audio: ToyAudio = .shared) {
        self.audio = audio
    }

    func start() {
        guard !running else { return }
        running = true
        let g = graph ?? build()
        graph = g
        for v in g.voices {
            v.osc.amplitude = 0
            v.id = -1
            v.active = false
            v.osc.start()
        }
        g.out.gain = level
        applyStyle()
        audio.attach(g.out)
        audio.acquire()
    }

    func stop() {
        guard running, let g = graph else { return }
        running = false
        for v in g.voices {
            v.osc.$amplitude.ramp(to: 0, duration: 0.04)
            v.active = false
            v.id = -1
        }
        audio.detach(g.out)
        audio.release()
    }

    /// A finger (or the boat) starts: in the playful style a short "boing" slides down to the pitch.
    func began(id: Int, voice: FingerVoice) {
        guard running else { return }
        play(id: id, voice: voice, boing: style == .playful)
    }

    func update(id: Int, voice: FingerVoice) {
        guard running, let g = graph else { return }
        guard let v = g.voices.first(where: { $0.id == id && $0.active }) else {
            play(id: id, voice: voice, boing: false)
            return
        }
        let glide: Float = style == .dreamy ? 0.12 : 0.05
        v.osc.$frequency.ramp(to: AUValue(voice.frequency), duration: glide)
        v.osc.$amplitude.ramp(to: amplitude(voice), duration: style == .dreamy ? 0.18 : 0.06)
        v.osc.$index.ramp(to: index(voice), duration: 0.15)
        v.panner.$pan.ramp(to: AUValue(voice.pan), duration: 0.12)
    }

    func ended(id: Int) {
        guard let g = graph, let v = g.voices.first(where: { $0.id == id && $0.active }) else { return }
        v.osc.$amplitude.ramp(to: 0, duration: release)
        v.active = false
        v.silentAt = Date().addingTimeInterval(Double(release) + 0.03)
    }

    // MARK: - internals

    private var attack: Float { style == .dreamy ? 0.22 : 0.012 }
    private var release: Float { style == .dreamy ? 1.1 : 0.22 }
    private var level: AUValue { style == .dreamy ? 1.25 : 0.8 }

    private func amplitude(_ voice: FingerVoice) -> AUValue {
        // several fingers sum: keep each voice modest, the limiter does the rest
        AUValue(min(1, max(0, voice.amplitude))) * (style == .dreamy ? 0.2 : 0.24)
    }

    private func index(_ voice: FingerVoice) -> AUValue {
        let b = AUValue(min(1, max(0, voice.brightness)))
        return style == .dreamy ? 1 + b * 2 : b * 2
    }

    private func play(id: Int, voice: FingerVoice, boing: Bool) {
        guard let g = graph else { return }
        let now = Date()
        let v = g.voices.first(where: { $0.id == id && $0.active })
            ?? g.voices.first(where: { !$0.active && $0.silentAt <= now })
            ?? g.voices.min(by: { ($0.active ? $0.since : $0.silentAt) < ($1.active ? $1.since : $1.silentAt) })!
        let sounding = v.active || v.silentAt > now
        // a voice still sounding fades for 12 ms before its new note: no click
        let delay: Float = sounding ? 0.013 : 0
        if sounding { v.osc.$amplitude.ramp(to: 0, duration: 0.012) }
        let f = AUValue(voice.frequency)
        if boing {
            v.osc.$frequency.ramp(to: f * 2.2, duration: 0, delay: delay)
            v.osc.$frequency.ramp(to: f, duration: 0.14, delay: delay + 0.001)
        } else {
            v.osc.$frequency.ramp(to: f, duration: 0, delay: delay)
        }
        v.osc.$index.ramp(to: index(voice), duration: 0, delay: delay)
        v.panner.$pan.ramp(to: AUValue(voice.pan), duration: 0, delay: delay)
        v.osc.$amplitude.ramp(to: amplitude(voice), duration: attack, delay: delay + 0.001)
        v.id = id
        v.active = true
        v.since = now
    }

    private func applyStyle() {
        guard let g = graph else { return }
        let dreamy = style == .dreamy
        g.chorus.dryWetMix = dreamy ? 0.45 : 0
        g.echo.dryWetMix = dreamy ? 0.32 : 0.08
        g.echo.feedback = dreamy ? 0.42 : 0.15
        g.echo.time = dreamy ? 0.34 : 0.18
        g.out.gain = level
        audio.setRoom(dreamy ? .hall : .small)
    }

    private func build() -> Graph {
        let tables = Self.tables
        let voices = (0..<Self.voiceCount).map { _ in Voice(tables: tables) }
        let mix = Mixer(voices.map(\.panner), name: "fingers")
        let chorus = Chorus(mix, frequency: 0.6, depth: 0.35, feedback: 0, dryWetMix: 0)
        let echo = StereoDelay(chorus, time: 0.34, feedback: 0.4, dryWetMix: 0, pingPong: true)
        let out = Fader(echo, gain: level)
        return Graph(voices: voices, mix: mix, chorus: chorus, echo: echo, out: out)
    }

    /// Four timbres the voices morph between: round, warm, bright, bell (octave shimmer).
    static let tables: [Table] = [
        harmonics([1, 0.08]),
        harmonics([1, 0.3, 0.1]),
        harmonics([1, 0.45, 0.22, 0.08]),
        harmonics([1, 0.25, 0, 0.18, 0, 0, 0, 0.08]),
    ]

    static func harmonics(_ amps: [Float], size: Int = 4096) -> Table {
        var samples = [Float](repeating: 0, count: size)
        for i in 0..<size {
            let x = Float(i) / Float(size) * 2 * .pi
            var s: Float = 0
            for (k, a) in amps.enumerated() where a != 0 { s += a * sin(Float(k + 1) * x) }
            samples[i] = s
        }
        let peak = samples.map(abs).max() ?? 1
        return Table(samples.map { $0 / max(peak, 0.0001) })
    }
}
