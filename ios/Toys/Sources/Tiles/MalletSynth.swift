@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Foundation
@preconcurrency import SoundpipeAudioKit

/// The shapes' little orchestra, through `ToyAudio` (sound: `MalletDSP`).
///
/// The shape picks the instrument: the arcs (most tiles) are a wooden marimba,
/// the triangles a glockenspiel, the quarter discs a kalimba. The row picks the
/// note on the pentatonic scale (top = high, so any tapping is in tune), the
/// column the place left to right. The glockenspiel plays an octave up.
@MainActor
final class MalletSynth {
    private let audio: ToyAudio
    private var graph: (mallets: RenderNode<MalletDSP>, out: Fader)?
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
    }

    func stop() {
        guard running, let g = graph else { return }
        running = false
        g.mallets.dsp.queue.send(.init(kind: .silence))
        audio.detach(g.out)
        audio.release()
    }

    static func instrument(for kind: TileKind) -> MalletDSP.Instrument {
        switch kind {
        case .arcs: .marimba
        case .triangle: .glockenspiel
        case .quarter: .kalimba
        }
    }

    /// A tile struck: `velocity` 0...1 (a tap is firmer than a swipe brushing past).
    func strike(column: Int, row: Int, kind: TileKind, columns: Int, rows: Int, velocity: Double) {
        guard running, let g = graph else { return }
        let instrument = Self.instrument(for: kind)
        let voice = FingerMusic.tileVoice(column: column, row: row, columns: columns, rows: rows)
        let octave: Double = instrument == .glockenspiel ? 2 : 1
        let key = Int32((row * columns + column) * 4 + Int(instrument.rawValue))
        g.mallets.dsp.queue.send(.init(kind: .strike, key: key, instrument: instrument, frequency: Float(voice.frequency * octave), velocity: Float(min(1, max(0, velocity))), pan: Float(voice.pan)))
    }

    /// The shuffle: a glockenspiel run down the scale and back up, each note on its sample.
    func shuffle() {
        guard running, let g = graph else { return }
        let degrees = [9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 2, 4, 6, 9]
        let rate = Double(AudioKit.Settings.audioFormat.sampleRate)
        for (k, degree) in degrees.enumerated() {
            let midi = Double(FingerMusic.notes[degree] + 12)
            g.mallets.dsp.queue.send(.init(
                kind: .strike, key: Int32(100_000 + k), instrument: .glockenspiel,
                frequency: Float(FingerMusic.frequency(midi: midi)),
                velocity: Float(0.4 + 0.04 * Double(k % 3)),
                pan: Float(Double(k) / Double(degrees.count - 1) * 1.4 - 0.7),
                delay: Int32(Double(k) * 0.045 * rate)
            ))
        }
    }

    private func build() -> (mallets: RenderNode<MalletDSP>, out: Fader) {
        let format = AudioKit.Settings.audioFormat
        let mallets = RenderNode(MalletDSP(sampleRate: Float(format.sampleRate)), format: format)
        return (mallets, Fader(mallets, gain: 1))
    }
}
