import AVFoundation

/// A nylon-string guitar from recorded notes (`GuitarSamples`), one voice per
/// ringing note: the note nearest in pitch, retuned by its playback speed (at
/// most a semitone), louder and brighter with the pluck's strength (a soft
/// pluck is a warmer, darker note), a few cents of human detune, and a damp
/// that fades it over tens of milliseconds, like a finger touching the string,
/// so a re-pluck or a muted string never clicks; a pluck on a voice still
/// ringing hands the old note to a spare voice that fades it out in 15 ms. Everything the audio thread
/// touches is allocated before it runs; commands come through a `DSPQueue`.
final class NylonDSP: RenderDSP, @unchecked Sendable {
    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case pluck, damp, silence }
        var kind: Kind
        var voice: Int32 = 0
        var frequency: Float = 0
        var velocity: Float = 0
        var pan: Float = 0
        var time: Float = 0.06
    }

    private struct Voice {
        var active = false
        var offset = 0, length = 0
        var position: Double = 0
        var rate: Double = 1
        var gainL: Float = 0, gainR: Float = 0
        var brightness: Float = 1   // one-pole coefficient: 1 = untouched
        var low: Float = 0
        var envelope: Float = 1
        var envelopeStep: Float = 0
    }

    static let voiceCount = 22   // three per string, four for the melody
    private static let spareCount = 8

    let queue = DSPQueue<Command>(capacity: 256, filler: Command(kind: .silence))
    private let samples: GuitarSamples
    private let sampleRate: Float
    private let voices: UnsafeMutablePointer<Voice>
    private var noise = Noise(seed: 0x6C07_8965)

    init(sampleRate: Float, samples: GuitarSamples = .shared) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        self.samples = samples
        voices = .allocate(capacity: Self.voiceCount + Self.spareCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount + Self.spareCount)
    }

    deinit { voices.deallocate() }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = queue.drain()
        for i in 0..<n { apply(queue.taken[i]) }
        for i in 0..<frameCount {
            l[i] = 0
            r?[i] = 0
        }
        let data = samples.data
        for v in 0..<(Self.voiceCount + Self.spareCount) where voices[v].active {
            var s = voices[v]
            let base = data + s.offset
            let last = Double(s.length - 2)
            for i in 0..<frameCount {
                if s.position >= last || s.envelope <= 0 {
                    s.active = false
                    break
                }
                let k = Int(s.position)
                let f = Float(s.position - Double(k))
                let a = Float(base[k]), b = Float(base[k + 1])
                let x = (a + (b - a) * f) * (1 / 32768)
                s.low += (x - s.low) * s.brightness
                let out = s.low * s.envelope
                l[i] += out * s.gainL
                r?[i] += out * s.gainR
                s.position += s.rate
                if s.envelopeStep > 0 { s.envelope = max(0, s.envelope - s.envelopeStep) }
            }
            voices[v] = s
        }
    }

    private func apply(_ c: Command) {
        switch c.kind {
        case .silence:
            for v in 0..<(Self.voiceCount + Self.spareCount) where voices[v].active {
                voices[v].envelopeStep = max(voices[v].envelopeStep, 1 / (0.04 * sampleRate))
            }
        case .damp:
            let v = Int(c.voice)
            guard (0..<Self.voiceCount).contains(v), voices[v].active else { return }
            voices[v].envelopeStep = max(voices[v].envelopeStep, 1 / (max(0.005, c.time) * sampleRate))
        case .pluck:
            let v = Int(c.voice)
            guard (0..<Self.voiceCount).contains(v), c.frequency > 20, !samples.isEmpty else { return }
            // a few cents either way: a hand-tuned guitar, and no two plucks alike
            let cents = Double(noise.bipolar()) * 4
            let note = samples.nearest(Double(c.frequency) * pow(2, cents / 1200), outputRate: Double(sampleRate))
            guard samples.lengths[note.index] > 4 else { return }
            if voices[v].active {
                // the note still ringing fades out on a spare voice (the quietest one if all are busy)
                let spares = Self.voiceCount..<(Self.voiceCount + Self.spareCount)
                let spare = spares.first(where: { !voices[$0].active }) ?? spares.min(by: { voices[$0].envelope < voices[$1].envelope })!
                voices[spare] = voices[v]
                voices[spare].envelopeStep = max(voices[spare].envelopeStep, 1 / (0.015 * sampleRate))
            }
            let velocity = max(0.1, min(1, c.velocity))
            let level = 0.3 + 0.7 * powf(velocity, 1.3)
            // soft = warm: a one-pole low-pass from ~1.2 kHz (soft) to wide open (hard)
            let cutoff = 1200 * powf(16, velocity)
            let angle = (min(1, max(-1, c.pan)) + 1) * 0.25 * .pi
            voices[v] = Voice(
                active: true, offset: samples.offsets[note.index], length: samples.lengths[note.index],
                position: 0, rate: note.rate,
                gainL: level * cosf(angle), gainR: level * sinf(angle),
                brightness: min(1, 1 - expf(-2 * .pi * cutoff / sampleRate)), low: 0,
                envelope: 1, envelopeStep: 0
            )
        }
    }
}
