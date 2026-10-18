import AVFoundation

/// The parrot's voice: plays a phrase back as one of several characters,
/// sample by sample, so every character lives in one node and nothing in the
/// audio graph changes while it runs.
///
/// The phrase is read at a speed (pitch and tempo together, like a tape: no
/// time-stretching artefacts), with an optional wobble of that speed, then
/// goes through the character's chain: filters, a 22-band vocoder on a
/// steady buzz (the robot), ring modulation, a metallic comb, a nasal band and
/// a soft drive, a beak flutter, pitch-shifted harmonies (a delay-line shifter,
/// two crossfaded taps, each singer wobbling on its own), bubbles, and a
/// ping-pong echo. A short sound can come first: a curious "hmm?", a chirp,
/// a robot's bleep-bloop.
///
/// The phrase lives in one of two slots: the main thread writes the slot the
/// audio thread is not reading (phrases alternate, and a phrase is only
/// loaded once the previous one has played), then sends `play`.
final class VoiceDSP: RenderDSP, @unchecked Sendable {
    /// No slowed-down voice: blind listeners heard a low, slow one as a monster.
    enum Character: Int, CaseIterable, Sendable {
        case chipmunk, squawk, robot, canyon, choir, underwater
    }

    enum Prefix: UInt8, Sendable { case none, hmm, chirp, bleep }

    /// A character's chain. Zero switches a stage off.
    struct Settings: Sendable {
        var rate: Double = 1
        var vibratoRate: Float = 0, vibratoDepth: Float = 0
        var highpass: Float = 90
        var lowpass: Float = 0, lowpassWobbleRate: Float = 0, lowpassWobble: Float = 0
        /// The robot: the voice's spectrum played on a buzz that sings this little tune (Hz),
        /// a note every `vocoderStep` seconds.
        var vocoderTune: [Float] = []
        var vocoderStep: Float = 0.2
        /// How much robot, how much of the voice itself, how much of its "s" and "t".
        var vocoderWet: Float = 2.4, vocoderDry: Float = 0.35, vocoderSibilance: Float = 0.9
        var ringFrequency: Float = 0, ringMix: Float = 0
        var combMilliseconds: Float = 0, combFeedback: Float = 0, combMix: Float = 0
        var crushHold = 0
        var nasalCenter: Float = 0, nasalGain: Float = 0
        var drive: Float = 0
        var flutterRate: Float = 0, flutterDepth: Float = 0
        var dry: Float = 1
        /// (pitch ratio, level, delay in ms, pan)
        var harmonies: [(ratio: Float, level: Float, delay: Float, pan: Float)] = []
        var bubbles: Float = 0          // per second
        var echoSeconds: Float = 0, echoFeedback: Float = 0, echoMix: Float = 0
        var level: Float = 1
        /// Seconds of sound after the phrase ends (echoes, harmonies' delay).
        var tail: Double = 0.05

        static func of(_ c: Character) -> Settings {
            var s = Settings()
            switch c {
            case .chipmunk:
                s.rate = 1.72
                s.highpass = 140
                s.level = 0.8
            case .squawk:
                // a real parrot: high, nasal, a rough edge, the beak fluttering
                s.rate = 1.5
                s.highpass = 320
                s.nasalCenter = 2400; s.nasalGain = 1.5
                s.drive = 2.2
                s.flutterRate = 40; s.flutterDepth = 0.3
                s.level = 0.72
            case .robot:
                // a friendly robot singing its words on a little tune, a metallic ring, still clear
                s.rate = 1.15
                s.highpass = 120
                s.vocoderTune = [262, 330, 392, 330]
                s.vocoderStep = 0.22
                s.vocoderWet = 1.2; s.vocoderDry = 0.8; s.vocoderSibilance = 0.7
                s.ringFrequency = 392; s.ringMix = 0.35
                s.combMilliseconds = 5.1; s.combFeedback = 0.45; s.combMix = 0.35
                s.level = 0.85
            case .canyon:
                // a bouncy echo, two or three quick answers (long dark echoes in a big
                // hall read as a ghost to blind listeners)
                s.rate = 1.3
                s.echoSeconds = 0.3; s.echoFeedback = 0.3; s.echoMix = 0.5
                s.lowpass = 6500
                s.level = 0.78
                s.tail = 1.2
            case .choir:
                // a tiny choir: the voice and its major third, fifth and octave
                s.rate = 1.15
                s.vibratoRate = 5.2; s.vibratoDepth = 0.008
                s.dry = 0.7
                s.harmonies = [(1.2599, 0.55, 9, -0.65), (1.4983, 0.5, 15, 0.65), (2.0, 0.3, 21, 0)]
                s.level = 0.62
                s.tail = 0.3
            case .underwater:
                // under the sea: wobbling pitch, muffled, bubbles
                s.rate = 1.32
                s.vibratoRate = 6.5; s.vibratoDepth = 0.045
                s.lowpass = 1150; s.lowpassWobbleRate = 2.7; s.lowpassWobble = 380
                s.bubbles = 22
                s.level = 0.85
                s.tail = 0.25
            }
            return s
        }

        /// How often each character comes: the chipmunk most.
        static func weight(_ c: Character) -> Double {
            c == .chipmunk ? 3 : 2
        }

        static func prefix(_ c: Character, roll: Double) -> Prefix {
            switch c {
            case .robot: roll < 0.75 ? .bleep : .none
            case .squawk: roll < 0.6 ? .chirp : .none
            case .canyon, .choir: .none
            default: roll < 0.25 ? .hmm : .none
            }
        }
    }

    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case play, stop }
        var kind: Kind
        var slot: Int32 = 0
        var length: Int32 = 0
        var phraseRate: Float = 48000
        var character: Int32 = 0
        var prefix: Prefix = .none
        var seed: UInt32 = 1
    }

    static let maxSeconds = 12.0
    static let shifterLength = 4096
    static let echoLength = 32768
    static let combLength = 1024

    let sampleRate: Float
    let queue = DSPQueue<Command>(capacity: 16, filler: Command(kind: .stop))
    /// Samples per slot.
    let capacity: Int
    private let slots: UnsafeMutablePointer<Float>
    private let shifter: UnsafeMutablePointer<Float>
    private let echoL: UnsafeMutablePointer<Float>, echoR: UnsafeMutablePointer<Float>
    private let comb: UnsafeMutablePointer<Float>
    /// The settings of every character, built once (no allocation on the audio thread).
    private let table: [Settings]

    // playback state (audio thread only)
    private var settings = Settings()
    private var slot = 0, length = 0
    private var position = 0.0, step = 1.0
    private var reading = false
    private var silentFor = 0
    private var prefix: Prefix = .none, prefixAt = 0, prefixLength = 0
    private var noise = Noise(seed: 1)
    private var phase = (vibrato: Float(0), ring: Float(0), flutter: Float(0), wobble: Float(0), prefix: Float(0))
    private var high = SVF(), low = SVF(), nasal = SVF(), echoDampL = SVF(), echoDampR = SVF(), prefixFilter = SVF()
    private var held: Float = 0, holdCount = 0
    private var shifterIndex = 0, combIndex = 0, echoIndex = 0
    private var harmonyDelay: (Float, Float, Float) = (0, 0, 0)
    private var bubble = (phase: Float(0), step: Float(0), glide: Float(1), level: Float(0), decay: Float(0))
    private var singers: (Float, Float, Float) = (0, 0, 0)
    private var active = false
    // the vocoder: a band-pass per band on the voice and on the buzz, and the voice's level in each
    static let bands = 22
    private let analysis: UnsafeMutablePointer<SVF>
    private let synthesis: UnsafeMutablePointer<SVF>
    private let envelopes: UnsafeMutablePointer<Float>
    private var buzz: Float = 0, tuneAt: Float = 0, note = 0
    private var sibilance = SVF()
    private let envelopeRise: Float, envelopeFall: Float

    /// `custom` replaces some characters' settings (for tuning by ear).
    init(sampleRate: Float, custom: [Character: Settings] = [:]) {
        let sr = sampleRate > 0 ? sampleRate : 44100
        self.sampleRate = sr
        capacity = Int(Self.maxSeconds * 48000)
        slots = .allocate(capacity: 2 * capacity)
        slots.initialize(repeating: 0, count: 2 * capacity)
        shifter = .allocate(capacity: Self.shifterLength)
        shifter.initialize(repeating: 0, count: Self.shifterLength)
        echoL = .allocate(capacity: Self.echoLength)
        echoL.initialize(repeating: 0, count: Self.echoLength)
        echoR = .allocate(capacity: Self.echoLength)
        echoR.initialize(repeating: 0, count: Self.echoLength)
        comb = .allocate(capacity: Self.combLength)
        comb.initialize(repeating: 0, count: Self.combLength)
        table = Character.allCases.map { custom[$0] ?? Settings.of($0) }
        analysis = .allocate(capacity: Self.bands)
        analysis.initialize(repeating: SVF(), count: Self.bands)
        synthesis = .allocate(capacity: Self.bands)
        synthesis.initialize(repeating: SVF(), count: Self.bands)
        envelopes = .allocate(capacity: Self.bands)
        envelopes.initialize(repeating: 0, count: Self.bands)
        for b in 0..<Self.bands {
            // 180 Hz to 5.5 kHz, about a quarter of an octave apart: the formants come through
            let f = 180 * powf(5500 / 180, Float(b) / Float(Self.bands - 1))
            analysis[b].tune(f, q: 3.5, sampleRate: sr)
            synthesis[b].tune(f, q: 3.5, sampleRate: sr)
        }
        sibilance.tune(4500, q: 0.7, sampleRate: sr)
        envelopeRise = 1 - expf(-1 / (0.002 * sr))
        envelopeFall = 1 - expf(-1 / (0.025 * sr))
    }

    deinit {
        slots.deallocate()
        shifter.deallocate()
        echoL.deallocate()
        echoR.deallocate()
        comb.deallocate()
        analysis.deallocate()
        synthesis.deallocate()
        envelopes.deallocate()
    }

    /// From the main thread: copies a phrase into `slot` (0 or 1), at most `capacity` samples.
    func load(_ samples: UnsafeBufferPointer<Float>, into slot: Int) -> Int {
        let n = min(samples.count, capacity)
        guard let base = samples.baseAddress, (0...1).contains(slot) else { return 0 }
        (slots + slot * capacity).update(from: base, count: n)
        return n
    }

    /// The prefix's length, in seconds (it plays before the phrase).
    static func duration(of prefix: Prefix) -> Double {
        switch prefix {
        case .none: 0
        case .hmm: 0.42
        case .chirp: 0.3
        case .bleep: 0.36
        }
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = queue.drain()
        for i in 0..<n { apply(queue.taken[i]) }
        guard active else {
            for i in 0..<frameCount {
                l[i] = 0
                r?[i] = 0
            }
            return
        }
        let s = settings
        let twoPi = 2 * Float.pi
        let invSR = 1 / sampleRate
        let phrase = slots + slot * capacity
        let combDelay = s.combMilliseconds > 0 ? min(Self.combLength - 1, Int(s.combMilliseconds / 1000 * sampleRate)) : 0
        let echoDelay = s.echoSeconds > 0 ? min(Self.echoLength - 1, Int(s.echoSeconds * sampleRate)) : 0
        let window: Float = 2048
        var energy: Float = 0
        for i in 0..<frameCount {
            var x: Float = 0
            if prefix != .none {
                x = prefixSample()
            } else if reading {
                var speed = step
                if s.vibratoDepth > 0 {
                    phase.vibrato += twoPi * s.vibratoRate * invSR
                    if phase.vibrato > twoPi { phase.vibrato -= twoPi }
                    speed *= Double(1 + s.vibratoDepth * sinf(phase.vibrato))
                }
                x = Self.hermite(phrase, length, position)
                position += speed
                if position >= Double(length + 2) { reading = false }
            }
            // the character's chain
            if s.highpass > 0 { x = high.process(x).high }
            if s.lowpass > 0 {
                if s.lowpassWobble > 0, i & 31 == 0 {
                    phase.wobble += twoPi * s.lowpassWobbleRate * invSR * 32
                    if phase.wobble > twoPi { phase.wobble -= twoPi }
                    low.tune(s.lowpass + s.lowpassWobble * sinf(phase.wobble), q: 0.9, sampleRate: sampleRate)
                }
                x = low.process(x).low
            }
            if !s.vocoderTune.isEmpty {
                // the buzz: a sawtooth on the tune's note, a breath of noise for the consonants
                tuneAt += invSR
                if tuneAt >= s.vocoderStep {
                    tuneAt -= s.vocoderStep
                    note = (note + 1) % s.vocoderTune.count
                }
                buzz += s.vocoderTune[note] * invSR
                if buzz >= 1 { buzz -= 1 }
                let carrier = (2 * buzz - 1) * 0.8 + 0.12 * noise.bipolar()
                var robot: Float = 0
                for b in 0..<Self.bands {
                    let m = abs(analysis[b].process(x).band)
                    let e = envelopes[b]
                    envelopes[b] = e + (m - e) * (m > e ? envelopeRise : envelopeFall)
                    robot += synthesis[b].process(carrier).band * envelopes[b]
                }
                // some of the voice itself and its own "s" and "t" keep the words clear
                x = robot * s.vocoderWet + s.vocoderDry * x + s.vocoderSibilance * sibilance.process(x).high
            }
            if s.ringMix > 0 {
                phase.ring += twoPi * s.ringFrequency * invSR
                if phase.ring > twoPi { phase.ring -= twoPi }
                x *= 1 - s.ringMix + s.ringMix * sinf(phase.ring)
            }
            if s.crushHold > 1 {
                holdCount -= 1
                if holdCount <= 0 {
                    holdCount = s.crushHold
                    held = x
                }
                x = held
            }
            if combDelay > 0 {
                let back = comb[(combIndex - combDelay + Self.combLength) % Self.combLength]
                let c = x + s.combFeedback * back
                comb[combIndex] = c
                combIndex = (combIndex + 1) % Self.combLength
                x = (1 - s.combMix) * x + s.combMix * c * (1 - s.combFeedback)
            }
            if s.nasalGain > 0 { x += s.nasalGain * nasal.process(x).band }
            if s.drive > 0 { x = tanhf(s.drive * x) / tanhf(s.drive) }
            if s.flutterDepth > 0 {
                phase.flutter += twoPi * s.flutterRate * invSR
                if phase.flutter > twoPi { phase.flutter -= twoPi }
                x *= 1 - s.flutterDepth * (0.5 + 0.5 * sinf(phase.flutter))
            }
            var outL = x * s.dry, outR = x * s.dry
            // harmonies: a delay-line pitch shifter per voice, two taps crossfaded
            if !s.harmonies.isEmpty {
                shifter[shifterIndex] = x
                for h in 0..<min(3, s.harmonies.count) {
                    let v = s.harmonies[h]
                    var d = h == 0 ? harmonyDelay.0 : (h == 1 ? harmonyDelay.1 : harmonyDelay.2)
                    // each singer wobbles on its own (4.1, 5.3, 6.2 Hz): a choir, not a chord machine
                    var sp = h == 0 ? singers.0 : (h == 1 ? singers.1 : singers.2)
                    let before = sinf(sp)
                    sp += twoPi * (h == 0 ? 4.1 : (h == 1 ? 5.3 : 6.2)) * invSR
                    if sp > twoPi { sp -= twoPi }
                    switch h {
                    case 0: singers.0 = sp
                    case 1: singers.1 = sp
                    default: singers.2 = sp
                    }
                    d += 1 - v.ratio + 14 * (sinf(sp) - before)
                    let base = v.delay / 1000 * sampleRate + 8
                    if d < base { d += window }
                    if d >= base + window { d -= window }
                    let p1 = (d - base) / window
                    var d2 = d + window / 2
                    if d2 >= base + window { d2 -= window }
                    let g1 = 0.5 - 0.5 * cosf(twoPi * p1)
                    let y = g1 * tap(d) + (1 - g1) * tap(d2)
                    switch h {
                    case 0: harmonyDelay.0 = d
                    case 1: harmonyDelay.1 = d
                    default: harmonyDelay.2 = d
                    }
                    let angle = (v.pan + 1) * 0.25 * .pi
                    outL += y * v.level * cosf(angle) * 1.41
                    outR += y * v.level * sinf(angle) * 1.41
                }
                shifterIndex = (shifterIndex + 1) % Self.shifterLength
            }
            if s.bubbles > 0 {
                if reading, noise.unit() < s.bubbles * invSR { startBubble() }
                if bubble.level > 0.0005 {
                    let b = sinf(bubble.phase) * bubble.level
                    bubble.phase += bubble.step
                    if bubble.phase > twoPi { bubble.phase -= twoPi }
                    bubble.step *= bubble.glide
                    bubble.level *= bubble.decay
                    outL += b * 0.8
                    outR += b * 0.5
                }
            }
            if echoDelay > 0 {
                // ping-pong: the left echo feeds the right, damped a little each time
                let backL = echoL[(echoIndex - echoDelay + Self.echoLength) % Self.echoLength]
                let backR = echoR[(echoIndex - echoDelay + Self.echoLength) % Self.echoLength]
                echoL[echoIndex] = x + s.echoFeedback * echoDampR.process(backR).low
                echoR[echoIndex] = s.echoFeedback * echoDampL.process(backL).low
                echoIndex = (echoIndex + 1) % Self.echoLength
                outL += s.echoMix * backL
                outR += s.echoMix * backR
            }
            outL *= s.level
            outR *= s.level
            if !outL.isFinite || !outR.isFinite {
                outL = 0
                outR = 0
            }
            l[i] = outL
            if let r { r[i] = outR } else { l[i] = 0.5 * (outL + outR) }
            energy = max(energy, abs(outL) + abs(outR))
        }
        // once the phrase and its tail are over, go idle (and clear the lines for the next one)
        if !reading, prefix == .none {
            silentFor = energy < 0.0004 ? silentFor + frameCount : 0
            if silentFor > Int(sampleRate * 0.1) { idle() }
        }
    }

    // MARK: - internals

    private func apply(_ c: Command) {
        switch c.kind {
        case .stop:
            idle()
        case .play:
            let index = Int(c.character)
            guard (0..<table.count).contains(index), (0...1).contains(Int(c.slot)) else { return }
            idle()
            settings = table[index]
            slot = Int(c.slot)
            length = max(0, min(capacity, Int(c.length)))
            position = 0
            step = settings.rate * Double(c.phraseRate / sampleRate)
            reading = length > 0
            noise = Noise(seed: c.seed | 1)
            prefix = c.prefix
            prefixAt = 0
            prefixLength = Int(Self.duration(of: c.prefix) * Double(sampleRate))
            let s = settings
            high.tune(max(20, s.highpass), q: 0.7, sampleRate: sampleRate)
            low.tune(max(200, s.lowpass), q: 0.9, sampleRate: sampleRate)
            nasal.tune(max(200, s.nasalCenter), q: 2, sampleRate: sampleRate)
            echoDampL.tune(2600, q: 0.6, sampleRate: sampleRate)
            echoDampR.tune(2600, q: 0.6, sampleRate: sampleRate)
            holdCount = 0
            note = 0
            tuneAt = 0
            for h in 0..<3 {
                let base = (h < s.harmonies.count ? s.harmonies[h].delay : 0) / 1000 * sampleRate + 8
                switch h {
                case 0: harmonyDelay.0 = base + 1
                case 1: harmonyDelay.1 = base + 1
                default: harmonyDelay.2 = base + 1
                }
            }
            active = reading || prefix != .none
        }
    }

    private func idle() {
        active = false
        reading = false
        prefix = .none
        silentFor = 0
        bubble.level = 0
        high.reset(); low.reset(); nasal.reset(); echoDampL.reset(); echoDampR.reset(); prefixFilter.reset()
        shifter.update(repeating: 0, count: Self.shifterLength)
        echoL.update(repeating: 0, count: Self.echoLength)
        echoR.update(repeating: 0, count: Self.echoLength)
        comb.update(repeating: 0, count: Self.combLength)
        envelopes.update(repeating: 0, count: Self.bands)
        for b in 0..<Self.bands {
            analysis[b].reset()
            synthesis[b].reset()
        }
        sibilance.reset()
    }

    /// The short sound before the phrase. Ends with a little gap.
    private func prefixSample() -> Float {
        let t = Float(prefixAt) / sampleRate
        let total = Float(prefixLength) / sampleRate
        prefixAt += 1
        if prefixAt >= prefixLength { prefix = .none }
        let twoPi = 2 * Float.pi
        switch prefix {
        case .none:
            return 0
        case .hmm:
            // "hmm?": a closed-mouth hum rising like a question, 0.32 s, then a breath
            let d: Float = 0.32
            guard t < d else { return 0 }
            let f = 250 + 150 * (t / d) * (t / d)
            phase.prefix += twoPi * f / sampleRate
            if phase.prefix > twoPi { phase.prefix -= twoPi }
            // a soft buzz: a few harmonics, closed by a low-pass, like a hum
            let buzz = sinf(phase.prefix) + 0.5 * sinf(2 * phase.prefix) + 0.25 * sinf(3 * phase.prefix)
            if prefixAt == 1 { prefixFilter.tune(900, q: 0.7, sampleRate: sampleRate) }
            let envelope = min(1, t / 0.03) * min(1, (d - t) / 0.06)
            return prefixFilter.process(buzz).low * envelope * 0.32
        case .chirp:
            // two quick bird chirps sliding up
            let one: Float = 0.085
            let k = t < one ? t : t - 0.12
            guard k >= 0, k < one, t < 0.21 else { return 0 }
            let f = 1900 + 2100 * (k / one)
            phase.prefix += twoPi * f / sampleRate
            if phase.prefix > twoPi { phase.prefix -= twoPi }
            let envelope = sinf(.pi * k / one)
            return sinf(phase.prefix) * envelope * envelope * 0.22
        case .bleep:
            // a robot's "bee-boop": two soft square-ish tones
            let first = t < 0.11
            let k = first ? t : t - 0.14
            let len: Float = first ? 0.11 : 0.14
            guard k >= 0, k < len, t < total - 0.06 else { return 0 }
            let f: Float = first ? 880 : 660
            phase.prefix += twoPi * f / sampleRate
            if phase.prefix > twoPi { phase.prefix -= twoPi }
            let tone = tanhf(3 * sinf(phase.prefix)) / tanhf(3)
            let envelope = min(1, k / 0.008) * min(1, (len - k) / 0.02)
            return tone * envelope * 0.16
        }
    }

    private func startBubble() {
        let f = 500 + 1300 * noise.unit()
        let life = 0.004 + 0.008 * noise.unit()
        bubble.phase = 0
        bubble.step = 2 * .pi * f / sampleRate
        bubble.glide = powf(1.6 + 0.6 * noise.unit(), 1 / (life * sampleRate))
        bubble.level = 0.06 + 0.1 * noise.unit()
        bubble.decay = expf(-1 / (life * sampleRate))
    }

    @inline(__always) private func tap(_ delay: Float) -> Float {
        let size = Self.shifterLength
        let p = Float(shifterIndex) - delay
        let wrapped = p < 0 ? p + Float(size) : p
        let i = Int(wrapped)
        let f = wrapped - Float(i)
        let a = shifter[i % size], b = shifter[(i + 1) % size]
        return a + (b - a) * f
    }

    /// Four-point Hermite interpolation of the phrase at a fractional position.
    @inline(__always) static func hermite(_ p: UnsafeMutablePointer<Float>, _ n: Int, _ pos: Double) -> Float {
        let i = Int(pos)
        let f = Float(pos - Double(i))
        @inline(__always) func at(_ k: Int) -> Float { k >= 0 && k < n ? p[k] : 0 }
        let xm1 = at(i - 1), x0 = at(i), x1 = at(i + 1), x2 = at(i + 2)
        let c = (x1 - xm1) * 0.5
        let v = x0 - x1
        let w = c + v
        let a = w + v + (x2 - x0) * 0.5
        let b = w + a
        return ((a * f - b) * f + c) * f + x0
    }
}
