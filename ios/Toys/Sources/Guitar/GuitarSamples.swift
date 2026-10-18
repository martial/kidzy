import AVFoundation
import os

/// The nylon guitar's recorded notes (FluidR3 GM, MIT licence: see `Licenses.txt`):
/// one note every two semitones from the low E (MIDI 40) to 92, 3.2 s each, as
/// AAC in the bundle (`guitar-nylon-<midi>.m4a`, ~700 KB). Decoded once into one
/// block of 16-bit samples that the audio thread only reads.
final class GuitarSamples: @unchecked Sendable {
    static let notes = Array(stride(from: 40, through: 92, by: 2))
    /// Decoded once (a few tenths of a second of AAC) and kept.
    static let shared = GuitarSamples()

    /// Called as the app starts, so opening the guitar never waits for the decoding.
    static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = shared }
    }

    let sampleRate: Double
    let data: UnsafeMutablePointer<Int16>
    let offsets: [Int]
    let lengths: [Int]
    var isEmpty: Bool { lengths.allSatisfy { $0 == 0 } }

    private init() {
        var buffers: [[Int16]] = []
        var rate = 44100.0
        for note in Self.notes {
            guard let url = Bundle.main.url(forResource: "guitar-nylon-\(note)", withExtension: "m4a"),
                  let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                  let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: pcm)) != nil, let ch = pcm.floatChannelData else {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.screenclub", category: "audio").error("guitar note \(note) missing")
                buffers.append([])
                continue
            }
            rate = file.processingFormat.sampleRate
            let n = Int(pcm.frameLength)
            buffers.append((0..<n).map { Int16(max(-1, min(1, ch[0][$0])) * 32767) })
        }
        sampleRate = rate
        let total = buffers.reduce(0) { $0 + $1.count } + 4
        let block = UnsafeMutablePointer<Int16>.allocate(capacity: total)
        block.initialize(repeating: 0, count: total)
        var at = 0
        var offsets: [Int] = [], lengths: [Int] = []
        for b in buffers {
            offsets.append(at)
            lengths.append(b.count)
            b.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { (block + at).update(from: base, count: b.count) }
            }
            at += b.count
        }
        data = block
        self.offsets = offsets
        self.lengths = lengths
    }

    /// The recorded note nearest to `frequency`, and the playback rate that tunes it exactly.
    func nearest(_ frequency: Double, outputRate: Double) -> (index: Int, rate: Double) {
        let midi = 69 + 12 * log2(max(20, frequency) / 440)
        let index = min(Self.notes.count - 1, max(0, Int(((midi - 40) / 2).rounded())))
        let shift = midi - Double(Self.notes[index])
        return (index, pow(2, shift / 12) * sampleRate / outputRate)
    }
}
