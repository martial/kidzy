import AVFoundation

/// A brush on paper, synthesized sample by sample, one voice per finger.
///
/// - The stroke: noise through a soft band-pass whose centre and loudness follow
///   the brush speed (slow = a low swish, fast = a brighter hiss), its top rolled
///   off; as the brush slows and lifts, the top closes down to ~1 kHz.
/// - The bristles: the hairs catch the paper's tooth unevenly, a fibrous
///   flutter of the level (10 to 25 times a second) and a fine crackle, both
///   stronger as the brush dries.
/// - The paper: the sheet's own body, a low-mid resonance the stroke excites.
/// - The paint: a wet squish with a wobbling level and tiny viscous bubbles
///   (damped blips: what makes a sound read as liquid); a fresh brush is wet and
///   it dries along the stroke. A stroke starts by breaking the paint's surface:
///   a quick falling blip.
/// - A dab: the bristles splay (low-mids, 5 ms in, ~25 ms out), and lifting is a
///   short suction hiss; every dab a little different.
/// - The room: a few dark early reflections, so it sounds close-miked, not sterile.
/// A finger that stops moving goes quiet within a tenth of a second, as a still brush does.
final class BrushDSP: RenderDSP, @unchecked Sendable {
    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case down, move, up, silence }
        var kind: Kind
        var voice: Int32 = 0
        var speed: Float = 0   // 0...1
        var pan: Float = 0     // -1...1
    }

    /// A blip of liquid: a damped sine gliding in pitch.
    private struct Bubble {
        var phase: Float = 0
        var step: Float = 0      // phase per sample
        var glide: Float = 1     // step multiplier per sample
        var level: Float = 0
        var decay: Float = 0

        @inline(__always) mutating func next() -> Float {
            guard level > 0.0005 else { return 0 }
            let out = sinf(phase) * level
            phase += step
            if phase > 2 * .pi { phase -= 2 * .pi }
            step *= glide
            level *= decay
            return out
        }
    }

    private struct Voice {
        var active = false
        var touching = false
        var broke = false           // the stroke has broken the paint's surface
        var target: Float = 0       // speed asked
        var speed: Float = 0        // speed heard (smoothed)
        var stale = 0               // samples since the last move
        var pan: Float = 0, panTarget: Float = 0
        var wetness: Float = 1
        var stroke = SVF(), top = SVF(), grain = SVF(), body = SVF(), wet = SVF(), splay = SVF(), suction = SVF()
        var grainEnvelope: Float = 0
        var catchLevel: Float = 1, catchTarget: Float = 1, catchTicks = 0
        var slipLevel: Float = 1, slipTarget: Float = 1, slipCount = 0
        var crackleLevel: Float = 0
        var wobble: Float = 1, wobbleTarget: Float = 1, wobbleTicks = 0
        var bubbles = (Bubble(), Bubble(), Bubble())
        var nextBubble = 0
        var splayEnvelope: Float = 0, splayAttack: Float = 0, splaySize: Float = 1
        var suctionEnvelope: Float = 0
        var fade: Float = 1         // 1, or falling to 0 on `silence`
        var noise = Noise(seed: 1)
        var tick = 0                // samples to the next filter retune
    }

    /// The brush's character (tuned by blind listening tests: wet, high and light reads as
    /// a paintbrush; low, dry and full reads as a broom).
    struct Tuning: Sendable {
        /// Friction source: white noise mixed with a crackle of random impulses (stick-slip).
        var white: Float = 0.2
        var crackle: Float = 1
        var crackleDensity: ClosedRange<Float> = 400...2000   // impulses per second, slow...fast
        /// Stick-slip flutter: level jumps 70 to 200 times a second.
        var slip: Float = 0.4
        /// Fibrous catch: 10 to 25 times a second.
        var catchDepth: Float = 0.2
        var wet: Float = 2.4
        var bubbles: Float = 2.4
        var room: Float = 1
        /// The stroke's band centre, slow...fast (Hz), and the paper's body level.
        var center: ClosedRange<Float> = 1500...5500
        var body: Float = 0.2
    }

    static let voiceCount = 10
    private static let roomLength = 2048
    let tuning: Tuning

    let sampleRate: Float
    let queue = DSPQueue<Command>(capacity: 512, filler: Command(kind: .silence))
    private let voices: UnsafeMutablePointer<Voice>
    private let room: UnsafeMutablePointer<Float>   // two delay lines, left then right
    private var roomIndex = 0
    private var roomLowL: Float = 0, roomLowR: Float = 0
    private let taps: [(left: Int, right: Int, gain: Float)]
    // per-sample constants
    private let rise: Float, fall: Float, grainDecay: Float, splayAttack: Float, splayDecay: Float, suctionDecay: Float, roomDamp: Float
    private let staleAfter: Int

    init(sampleRate: Float, tuning: Tuning = Tuning()) {
        let sr = sampleRate > 0 ? sampleRate : 44100
        self.sampleRate = sr
        self.tuning = tuning
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        for v in 0..<Self.voiceCount { voices[v].noise = Noise(seed: 0x9E37_79B9 &+ UInt32(v + 1) &* 0x85EB_CA6B) }
        room = .allocate(capacity: 2 * Self.roomLength)
        room.initialize(repeating: 0, count: 2 * Self.roomLength)
        func ms(_ t: Float) -> Int { min(Self.roomLength - 1, Int(t / 1000 * sr)) }
        taps = [(ms(6.1), ms(7.7), 0.2), (ms(11.3), ms(13.9), 0.14), (ms(19.7), ms(17.2), 0.1), (ms(29.5), ms(31.1), 0.06)]
        func perSample(_ seconds: Float) -> Float { exp(-1 / (seconds * sr)) }
        rise = 1 - perSample(0.035)
        fall = 1 - perSample(0.045)
        grainDecay = perSample(0.0005)
        splayAttack = 1 / (0.005 * sr)
        splayDecay = perSample(0.022)
        suctionDecay = perSample(0.006)
        roomDamp = 1 - perSample(1 / (2 * .pi * 3500))
        staleAfter = Int(0.035 * sr)
    }

    deinit {
        voices.deallocate()
        room.deallocate()
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = queue.drain()
        for i in 0..<n { apply(queue.taken[i]) }
        for i in 0..<frameCount {
            l[i] = 0
            r?[i] = 0
        }
        let invSR = 1 / sampleRate
        for v in 0..<Self.voiceCount where voices[v].active {
            var s = voices[v]
            for i in 0..<frameCount {
                if s.touching {
                    s.stale += 1
                    if s.stale > staleAfter { s.target = 0 }
                }
                s.speed += (s.target - s.speed) * (s.target > s.speed ? rise : fall)
                s.pan += (s.panTarget - s.pan) * 0.0005
                let speed = s.speed
                if s.tick <= 0 {
                    s.tick = 32
                    retune(&s)
                }
                s.tick -= 1
                if !s.broke, s.touching, speed > 0.08 {
                    // the stroke breaks the paint's surface: 800 → 200 Hz in 15 ms
                    s.broke = true
                    if s.wetness > 0.3 { blip(&s, from: 800, to: 200, seconds: 0.015, level: 0.14 * s.wetness) }
                }

                let a = s.noise.bipolar(), b = s.noise.bipolar()
                let dryness = 1 - s.wetness
                // friction: impulses at random times, heavy-tailed sizes, held for a sample or two
                let density = tuning.crackleDensity.lowerBound + (tuning.crackleDensity.upperBound - tuning.crackleDensity.lowerBound) * speed
                var impulse: Float = 0
                if s.noise.unit() < density * invSR {
                    let u = s.noise.unit()
                    impulse = (a < 0 ? -1 : 1) * u * u * u * 3
                }
                s.crackleLevel = impulse + s.crackleLevel * 0.35
                s.slipCount -= 1
                if s.slipCount <= 0 {
                    s.slipCount = Int(sampleRate / (70 + 130 * s.noise.unit()))
                    s.slipTarget = 1 - tuning.slip + 2 * tuning.slip * s.noise.unit()
                }
                s.slipLevel += (s.slipTarget - s.slipLevel) * 0.02
                let friction = (tuning.white * a + tuning.crackle * s.crackleLevel) * s.slipLevel
                // the bristles: a fibrous flutter and a fine crackle
                s.catchLevel += (s.catchTarget - s.catchLevel) * 0.004
                let grainRate = (200 + 1600 * speed) * (0.4 + dryness)
                if s.noise.unit() < grainRate * invSR { s.grainEnvelope = 0.3 + 0.7 * s.noise.unit() }
                s.grainEnvelope *= grainDecay
                // the stroke
                let loud = powf(speed, 1.05)
                let band = s.stroke.process(friction).band
                let swish = s.top.process(band).low * s.catchLevel * (0.85 + (0.2 + 0.6 * dryness) * s.grainEnvelope)
                let crackle = s.grain.process(b * s.grainEnvelope).band * (0.08 + 0.25 * dryness)
                let paper = s.body.process(a).band * 0.5 * tuning.body
                // the paint
                s.wobble += (s.wobbleTarget - s.wobble) * 0.0012
                let wet = s.wetness * s.wetness
                let squish = s.wet.process(b).band * s.wobble * wet * powf(speed, 0.9) * tuning.wet
                if s.noise.unit() < 50 * speed * wet * invSR { pop(&s, size: 1) }
                let liquid = (s.bubbles.0.next() + s.bubbles.1.next() + s.bubbles.2.next()) * tuning.bubbles
                s.wetness = max(0.15, s.wetness - speed * invSR / 2.4)
                // dab and lift
                var touch: Float = 0
                if s.splayAttack > 0 {
                    s.splayEnvelope = min(1, s.splayEnvelope + s.splayAttack)
                    if s.splayEnvelope >= 1 { s.splayAttack = 0 }
                } else {
                    s.splayEnvelope *= splayDecay
                }
                if s.splayEnvelope > 0.0004 { touch += s.splay.process(a).band * s.splayEnvelope * 0.42 * s.splaySize }
                if s.suctionEnvelope > 0.0004 {
                    s.suctionEnvelope *= suctionDecay
                    touch += s.suction.process(b).high * s.suctionEnvelope * 0.16
                }
                var out = (loud * (0.6 * swish + crackle + paper) + 0.5 * squish + 0.5 * liquid + touch) * s.fade
                if s.fade < 1 { s.fade = max(0, s.fade - 1 / (0.04 * sampleRate)) }
                if !out.isFinite { out = 0 }
                let angle = (s.pan + 1) * 0.25 * .pi
                l[i] += out * cosf(angle)
                r?[i] += out * sinf(angle)
            }
            let ringing = s.bubbles.0.level + s.bubbles.1.level + s.bubbles.2.level > 0.0015
            if s.fade <= 0 || (!s.touching && s.speed < 0.0005 && s.splayEnvelope < 0.0004 && s.suctionEnvelope < 0.0004 && !ringing) {
                s.active = false
            }
            voices[v] = s
        }
        // a small dark room: a few early reflections, low-passed
        let size = Self.roomLength
        let left = room, right = room + size
        for i in 0..<frameCount {
            let dryL = l[i], dryR = r?[i] ?? dryL
            var wetL: Float = 0, wetR: Float = 0
            for t in taps {
                wetL += t.gain * right[(roomIndex - t.left + size) % size]
                wetR += t.gain * left[(roomIndex - t.right + size) % size]
            }
            roomLowL += (wetL - roomLowL) * roomDamp
            roomLowR += (wetR - roomLowR) * roomDamp
            left[roomIndex] = dryL
            right[roomIndex] = dryR
            roomIndex = (roomIndex + 1) % size
            l[i] = dryL + roomLowL * tuning.room
            r?[i] = dryR + roomLowR * tuning.room
        }
    }

    /// The filters follow the speed; retuned every 32 samples.
    private func retune(_ s: inout Voice) {
        let speed = s.speed
        s.stroke.tune(tuning.center.lowerBound + (tuning.center.upperBound - tuning.center.lowerBound) * powf(speed, 0.9), q: 0.6, sampleRate: sampleRate)
        // the top closes as the brush slows: the lift sounds darker
        s.top.tune(950 + 5200 * powf(speed, 0.7), q: 0.55, sampleRate: sampleRate)
        s.grain.tune(1700 + 2000 * speed, q: 1.0, sampleRate: sampleRate)
        s.body.tune(310 + 60 * speed, q: 1.3, sampleRate: sampleRate)
        s.wet.tune(300 + 420 * speed, q: 1.6, sampleRate: sampleRate)
        s.catchTicks -= 1
        if s.catchTicks <= 0 {
            // the hairs catch and release some 10 to 25 times a second
            s.catchTicks = Int(sampleRate / 32 / (10 + 15 * s.noise.unit()))
            let depth = tuning.catchDepth * (1 + 1.4 * (1 - s.wetness))
            s.catchTarget = 1 - depth * 0.5 + depth * s.noise.unit()
        }
        s.wobbleTicks -= 1
        if s.wobbleTicks <= 0 {
            s.wobbleTicks = Int(sampleRate * 0.06 / 32 * (0.6 + 0.8 * s.noise.unit()))
            s.wobbleTarget = 0.25 + 1.4 * s.noise.unit()
        }
    }

    /// A bubble on the voice's next slot: 450-1700 Hz (lower when `size` is bigger), 3-9 ms, rising.
    private func pop(_ s: inout Voice, size: Float) {
        let f = (450 + 1250 * s.noise.unit()) / size
        let life = (0.003 + 0.006 * s.noise.unit()) * size
        blip(&s, from: f, to: f * (1.15 + 0.6 * s.noise.unit()), seconds: life, level: (0.05 + 0.14 * s.noise.unit()) * min(1.5, size))
    }

    /// A damped sine gliding from `from` to `to` Hz over `seconds` (its decay time).
    private func blip(_ s: inout Voice, from: Float, to: Float, seconds: Float, level: Float) {
        var b = Bubble()
        b.step = 2 * .pi * from / sampleRate
        b.glide = powf(to / from, 1 / (seconds * sampleRate))
        b.level = level
        b.decay = expf(-1 / (seconds * sampleRate))
        switch s.nextBubble {
        case 0: s.bubbles.0 = b
        case 1: s.bubbles.1 = b
        default: s.bubbles.2 = b
        }
        s.nextBubble = (s.nextBubble + 1) % 3
    }

    private func apply(_ c: Command) {
        switch c.kind {
        case .silence:
            for v in 0..<Self.voiceCount where voices[v].active {
                voices[v].fade = min(voices[v].fade, 0.999)
                voices[v].touching = false
                voices[v].target = 0
            }
        case .down:
            let v = Int(c.voice)
            guard (0..<Self.voiceCount).contains(v) else { return }
            var s = voices[v]
            if !s.active {
                let noise = s.noise
                s = Voice()
                s.noise = noise
                s.pan = c.pan
                s.suction.tune(2400, q: 0.7, sampleRate: sampleRate)
            }
            s.active = true
            s.touching = true
            s.broke = false
            s.fade = 1
            s.panTarget = c.pan
            s.target = 0
            s.stale = 0
            s.wetness = 1
            // the bristles splay: bigger dabs are lower and fuller
            s.splaySize = 0.75 + 0.5 * s.noise.unit()
            s.splay.tune((260 + 260 * s.noise.unit()) / s.splaySize, q: 0.8, sampleRate: sampleRate)
            s.splayAttack = splayAttack
            if s.noise.unit() < 0.7 { pop(&s, size: 1.3) }
            voices[v] = s
        case .move:
            let v = Int(c.voice)
            guard (0..<Self.voiceCount).contains(v), voices[v].active else { return }
            voices[v].target = c.speed
            voices[v].panTarget = c.pan
            voices[v].stale = 0
        case .up:
            let v = Int(c.voice)
            guard (0..<Self.voiceCount).contains(v), voices[v].active else { return }
            voices[v].touching = false
            voices[v].target = 0
            // the suction of wet bristles leaving the paper
            voices[v].suctionEnvelope = 0.4 + 0.6 * voices[v].wetness
        }
    }
}
