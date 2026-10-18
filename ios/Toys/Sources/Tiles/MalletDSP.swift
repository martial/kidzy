import AVFoundation

/// Mallet percussion by modal synthesis: every note is a few tuned resonators
/// (the bar's or the tine's modes) struck by a mallet pulse.
///
/// - The pulse is a short half sine whose area is the loudness; a harder hit
///   also brings the high modes up. Each mode is a two-pole resonator with its
///   own ratio, level and decay. Striking a bar that still rings adds energy to
///   the same resonators, as a real bar does: no click.
/// - A short noise burst is the mallet's contact (the wooden knock, the metal
///   ping, the thumb on the tine).
/// - The levels and decays were measured, partial by partial, on the sampled
///   instruments of the General MIDI bank, and matched within ~2 dB:
///   - Marimba: the bar (1), its two-octave mode (4, −25 dB) and the bright tick
///     of the hit (10.2, as loud as the note for 50 ms); a resonator tube driven by
///     the bar swells the fundamental by ~7 dB over 60 ms and carries the note.
///   - Glockenspiel: a free steel bar struck at its centre, so the 2.76 mode
///     (a node there) is faint and the 5.40 one sings above the fundamental;
///     13.3 glints. Long ring, high modes included.
///   - Kalimba: a clamped tine, 1 : 5.87 : 11.9 with a weak octave, the hollow
///     box (0.59 and 1.44), and a faint buzz when the tine swings wide.
/// - Strikes can be scheduled to the sample (the shuffle's glissando).
final class MalletDSP: RenderDSP, @unchecked Sendable {
    enum Instrument: UInt8, Sendable { case marimba, glockenspiel, kalimba }

    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case strike, silence }
        var kind: Kind
        /// Same key = same bar: a re-strike adds to it while it rings.
        var key: Int32 = 0
        var instrument: Instrument = .marimba
        var frequency: Float = 440
        var velocity: Float = 0.8   // 0...1
        var pan: Float = 0          // -1...1
        /// Samples from now (0 = at the start of the next render).
        var delay: Int32 = 0
    }

    private struct Mode {
        var b1: Float = 0, b2: Float = 0   // y = b1 y1 + b2 y2 + g x
        var g: Float = 0
        var y1: Float = 0, y2: Float = 0
    }

    private struct Voice {
        var key: Int32 = -1
        var instrument: Instrument = .marimba
        var modes = 0
        var level: Float = 0          // a running peak, to know when it is silent
        var gainL: Float = 0, gainR: Float = 0
        // the mallet pulse
        var pulseLeft = 0, pulseLength = 1
        var pulseArea: Float = 0
        // contact noise
        var contact: Float = 0, contactDecay: Float = 0
        var contactFilter = SVF()
        // marimba tube / kalimba buzz
        var tubeCoupling: Float = 0
        var buzz: Float = 0
        var buzzFilter = SVF()
        var fade: Float = 1, fading = false
        /// Each note's own noise (contact, buzz), so notes never depend on one another.
        var noise = Noise(seed: 1)
    }

    /// One mode: frequency ratio to the fundamental, level, T60 in seconds.
    private struct Partial {
        var ratio: Float, level: Float, t60: Float
    }

    static let maxModes = 6
    /// Notes taken over by a new one fade out here for 12 ms instead of being cut.
    private static let ghostCount = 4
    private static let scheduleCapacity = 128

    let sampleRate: Float
    /// Notes that can ring at once.
    let voiceCount: Int
    let queue = DSPQueue<Command>(capacity: 256, filler: Command(kind: .silence))
    private let voices: UnsafeMutablePointer<Voice>
    private let modes: UnsafeMutablePointer<Mode>
    private let scheduled: UnsafeMutablePointer<Command>
    private let partials: UnsafeMutablePointer<Partial>
    private var scheduledCount = 0
    private var nextGhost = 0
    private var noise = Noise(seed: 0x2545_F491)
    private var slots: Int { voiceCount + Self.ghostCount }

    init(sampleRate: Float, voices voiceCount: Int = 40) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        self.voiceCount = max(1, voiceCount)
        let slots = self.voiceCount + Self.ghostCount
        voices = .allocate(capacity: slots)
        voices.initialize(repeating: Voice(), count: slots)
        modes = .allocate(capacity: slots * Self.maxModes)
        modes.initialize(repeating: Mode(), count: slots * Self.maxModes)
        scheduled = .allocate(capacity: Self.scheduleCapacity)
        scheduled.initialize(repeating: Command(kind: .silence), count: Self.scheduleCapacity)
        partials = .allocate(capacity: Self.maxModes)
        partials.initialize(repeating: Partial(ratio: 1, level: 0, t60: 1), count: Self.maxModes)
    }

    deinit {
        voices.deallocate()
        modes.deallocate()
        scheduled.deallocate()
        partials.deallocate()
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = queue.drain()
        for i in 0..<n {
            let c = queue.taken[i]
            if c.kind == .silence {
                silence()
            } else if scheduledCount < Self.scheduleCapacity {
                scheduled[scheduledCount] = c
                scheduledCount += 1
            }
        }
        for i in 0..<frameCount {
            l[i] = 0
            r?[i] = 0
        }
        // render in segments, firing each strike on its sample
        var at = 0
        while at < frameCount {
            var next = frameCount
            var k = 0
            while k < scheduledCount {
                let due = Int(scheduled[k].delay)
                if due <= at {
                    strike(scheduled[k])
                    scheduledCount -= 1
                    scheduled[k] = scheduled[scheduledCount]
                } else {
                    next = min(next, due)
                    k += 1
                }
            }
            renderVoices(l + at, r.map { $0 + at }, count: next - at)
            at = next
        }
        for k in 0..<scheduledCount { scheduled[k].delay -= Int32(frameCount) }
    }

    private func renderVoices(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>?, count: Int) {
        guard count > 0 else { return }
        let fadeStep = 1 / (0.012 * sampleRate)
        for v in 0..<slots where voices[v].level > 0 || voices[v].pulseLeft > 0 {
            var s = voices[v]
            let m = modes + v * Self.maxModes
            var peak: Float = 0
            for i in 0..<count {
                // the mallet: a half-sine pulse
                var x: Float = 0
                if s.pulseLeft > 0 {
                    let phase = Float(s.pulseLength - s.pulseLeft) + 0.5
                    x = sinf(.pi * phase / Float(s.pulseLength)) * s.pulseArea
                    s.pulseLeft -= 1
                }
                var y: Float = 0
                var fundamental: Float = 0
                let tube = s.tubeCoupling > 0 ? s.modes - 1 : -1
                for k in 0..<s.modes {
                    // the marimba's tube (its last mode) is driven by the bar's fundamental
                    let input = k == tube ? fundamental * s.tubeCoupling : x
                    let out = m[k].b1 * m[k].y1 + m[k].b2 * m[k].y2 + m[k].g * input
                    m[k].y2 = m[k].y1
                    m[k].y1 = out
                    if k == 0 { fundamental = out }
                    y += out
                }
                // contact: the knock, the ping, the thumb
                if s.contact > 0.0002 {
                    y += s.contactFilter.process(s.noise.bipolar()).band * s.contact
                    s.contact *= s.contactDecay
                }
                // the kalimba's buzzer: noise gated by a wide swing of the tine
                if s.buzz > 0 {
                    let swing = max(0, abs(fundamental) - 0.08)
                    y += s.buzzFilter.process(s.noise.bipolar() * swing).band * s.buzz
                }
                if s.fading {
                    s.fade = max(0, s.fade - fadeStep)
                }
                var out = y * s.fade
                if !out.isFinite { out = 0 }
                peak = max(peak, abs(out))
                l[i] += out * s.gainL
                r?[i] += out * s.gainR
            }
            s.level = max(peak, s.level * 0.5)
            if (s.level < 0.00003 && s.pulseLeft == 0) || (s.fading && s.fade <= 0) {
                s.level = 0
                s.key = -1
                s.fade = 1
                s.fading = false
                s.contact = 0
                for k in 0..<Self.maxModes {
                    m[k].y1 = 0
                    m[k].y2 = 0
                }
            }
            voices[v] = s
        }
    }

    private func silence() {
        scheduledCount = 0
        for v in 0..<slots where voices[v].level > 0 {
            voices[v].fading = true
        }
    }

    /// The voice for a strike: the same bar if it still rings, else a silent one, else the quietest.
    private func voice(for key: Int32) -> Int {
        var quietest = 0
        var quietestLevel = Float.greatestFiniteMagnitude
        var free = -1
        for v in 0..<voiceCount {
            let s = voices[v]
            if s.key == key, s.level > 0, !s.fading { return v }
            if s.level == 0, s.pulseLeft == 0 {
                if free < 0 { free = v }
            } else if s.level < quietestLevel {
                quietestLevel = s.level
                quietest = v
            }
        }
        return free >= 0 ? free : quietest
    }

    private func jitter(_ amount: Float) -> Float { 1 + (noise.unit() - 0.5) * 2 * amount }

    private func strike(_ c: Command) {
        let v = voice(for: c.key)
        let m = modes + v * Self.maxModes
        let rebar = voices[v].key == c.key && voices[v].level > 0
        if !rebar, voices[v].level > 0 {
            // taking over a note that still sounds: it fades out on a ghost slot
            let g = voiceCount + nextGhost
            nextGhost = (nextGhost + 1) % Self.ghostCount
            voices[g] = voices[v]
            voices[g].fading = true
            voices[g].key = -1
            (modes + g * Self.maxModes).update(from: m, count: Self.maxModes)
        }
        // every strike draws the same random numbers, fresh bar or not: the sound of
        // one note never depends on what else is ringing
        let seed = noise.next() | 1
        let detune = noise.unit()
        var s = rebar ? voices[v] : Voice()
        if !rebar { s.noise = Noise(seed: seed) }
        let velocity = max(0.05, min(1, c.velocity))
        // ±2 cents on a fresh bar: no two hits alike
        let f0 = c.frequency * (rebar ? 1 : powf(2, (detune - 0.5) * 4 / 1200))
        let sr = sampleRate

        var count = 0
        func add(_ ratio: Float, _ level: Float, _ t60: Float) {
            guard count < Self.maxModes else { return }
            partials[count] = Partial(ratio: ratio, level: level, t60: t60)
            count += 1
        }
        var pulseSeconds: Float
        var contactLevel: Float, contactSeconds: Float, contactHz: Float
        s.tubeCoupling = 0
        s.buzz = 0
        // levels and decays measured on sampled instruments (General MIDI bank) and matched;
        // a harder hit brings the high modes up (`bright`)
        let bright = 0.35 + 0.65 * velocity
        var gain: Float = 1
        switch c.instrument {
        case .marimba:
            // rosewood: the decay shortens fast up the keyboard
            let t = powf(262 / f0, 0.75)
            add(1, 0.12, 0.3 * t)                                         // the bar alone
            add(4 * jitter(0.002), 0.025 * jitter(0.15), 1.5 * t)         // tuned two octaves up
            add(10.2 * jitter(0.004), 0.32 * bright * jitter(0.2), 0.22 * t)  // the bright tick of the hit
            add(10.55 * jitter(0.004), 0.15 * bright * jitter(0.3), 0.15 * t)
            gain = 2
            pulseSeconds = (0.0004 - 0.00015 * velocity) * jitter(0.12)
            // the mallet on wood: a broad burst
            contactLevel = 0.12; contactSeconds = 0.012; contactHz = 2800
        case .glockenspiel:
            // a free steel bar struck at its centre: the 2.76 mode has a node there, so
            // the fundamental and the 5.40 mode carry it, the 13.3 one glints
            let t = powf(1000 / f0, 0.35)
            add(1, 1, 2.2 * t)
            add(2.756, 0.18 * jitter(0.3), 1.2 * t)
            // softer than the sampled bar (+5 dB, not +12): small ears
            add(5.404 * jitter(0.002), 2.2 * bright * jitter(0.15), 1.7 * t)
            add(8.933, 0.12 * bright, 0.8 * t)
            add(13.34 * jitter(0.004), 0.3 * bright * jitter(0.25), 1.4 * t)
            gain = 0.16
            pulseSeconds = (0.00016 - 0.00006 * velocity) * jitter(0.12)
            contactLevel = 0.035; contactSeconds = 0.0006; contactHz = 9000
        case .kalimba:
            let t = powf(262 / f0, 0.4)
            add(1, 1, 1.6 * t)
            add(2, 0.04, 0.5 * t)                                        // the box's nonlinearity
            add(5.87 * jitter(0.01), 0.1 * bright * jitter(0.2), 0.3 * t)
            add(11.9 * jitter(0.01), 0.05 * bright * jitter(0.3), 0.08)
            add(0.59, 0.35, 0.3)                                         // the hollow box
            add(1.44, 0.045, 0.3)                                        // and its second mode
            // the thumb pushes the tine and lets go
            pulseSeconds = (0.0005 - 0.0002 * velocity) * jitter(0.12)
            contactLevel = 0.03; contactSeconds = 0.004; contactHz = 900
            s.buzz = 0.8
            s.buzzFilter.tune(3500, q: 1.1, sampleRate: sr)
        }
        for k in 0..<count {
            let p = partials[k]
            let f = f0 * p.ratio
            if f < min(sr * 0.45, 18000), f > 20 {
                set(&m[k], frequency: f, t60: p.t60, level: p.level, keepState: rebar)
            } else {
                m[k] = Mode()
            }
        }
        if c.instrument == .marimba {
            // the resonator tube: driven by the bar's fundamental, it swells over the first
            // 60 ms (+6 to 8 dB) and carries the note after the bar alone has faded
            set(&m[count], frequency: f0 * 1.0015, t60: 2.0 * powf(262 / f0, 0.75), level: 1, keepState: rebar)
            // per sample, so scaled to the rate it was tuned at (48 kHz)
            s.tubeCoupling = 0.0045 * 48000 / sr
            count += 1
        }
        if !rebar {
            for k in count..<Self.maxModes { m[k] = Mode() }
        }
        s.modes = count
        s.key = c.key
        s.instrument = c.instrument
        s.fade = 1
        s.fading = false
        let length = max(2, Int(pulseSeconds * sr))
        s.pulseLength = length
        s.pulseLeft = length
        // a finger racing over many tiles lands each one lighter: the sum stays sane
        var ringing = 0
        for k in 0..<voiceCount where voices[k].level > 0.01 { ringing += 1 }
        let crowd = 1 / (1 + Float(min(ringing, 24)) / 6).squareRoot()
        // unit area, then loudness
        s.pulseArea = (.pi / 2) / Float(length) * 0.34 * gain * crowd * powf(velocity, 1.3) * jitter(0.08)
        s.contact = contactLevel * powf(velocity, 1.5) * jitter(0.2)
        s.contactDecay = expf(-1 / (contactSeconds * sr))
        s.contactFilter.tune(contactHz * jitter(0.1), q: 0.9, sampleRate: sr)
        let angle = (max(-1, min(1, c.pan)) + 1) * 0.25 * .pi
        s.gainL = cosf(angle)
        s.gainR = sinf(angle)
        s.level = max(s.level, 0.0001)
        voices[v] = s
    }

    /// A resonator at `frequency` with a T60 decay; `level` is its amplitude for a unit impulse.
    private func set(_ mode: inout Mode, frequency: Float, t60: Float, level: Float, keepState: Bool) {
        let w = 2 * .pi * frequency / sampleRate
        let radius = powf(10, -3 / (max(0.01, t60) * sampleRate))
        mode.b1 = 2 * radius * cosf(w)
        mode.b2 = -radius * radius
        mode.g = level * sinf(w)
        if !keepState {
            mode.y1 = 0
            mode.y2 = 0
        }
    }
}
