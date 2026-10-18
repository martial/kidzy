import AVFoundation

/// The strings (`StringsDSP`) and the guitar around them, sample by sample.
///
/// - The body: eight resonant modes of a small acoustic guitar (the air in the
///   box near 100 Hz, the top plate near 200 Hz, then higher plate modes), each
///   ringing for a few tens of milliseconds: the wooden "knock" and warmth.
/// - Sympathetic strings: the six open strings, tuned E A D G B E, hum quietly
///   along when the body excites them, a halo after every strum.
/// - The pick: a short bright tick of noise and a softer thud on each pluck.
/// - Width: a slow chorus between the two sides, then a few early reflections,
///   so the guitar sits in a small room in front of you.
final class GuitarDSP: RenderDSP, @unchecked Sendable {
    struct Pick: Sendable {
        var velocity: Float
        var pan: Float
    }

    /// The body's character: the modes lift the air resonance by about 8 dB over
    /// the bare strings (a real body lifts its resonances by 10 dB and more).
    struct Tuning: Sendable {
        var dry: Float = 0.6
        var body: Float = 2.6
        /// Off: six fixed open strings rang on for seconds under any chord, a "diiing" drone.
        var sympathetic: Float = 0
        var pick: Float = 0.35
        var chorus: Float = 0.2
        var room: Float = 1
        /// Where the top starts to roll off (Hz).
        var top: Float = 7000
    }

    let strings: StringsDSP
    let picks = DSPQueue<Pick>(capacity: 64, filler: Pick(velocity: 0, pan: 0))
    let tuning: Tuning
    private let sampleRate: Float
    /// (Hz, Q, gain): a small steel-string body.
    private static let bodyModes: [(Float, Float, Float)] = [
        (98, 9, 0.6), (196, 13, 0.5), (232, 15, 0.32), (395, 17, 0.26),
        (548, 19, 0.2), (820, 22, 0.13), (1180, 22, 0.1), (2350, 16, 0.07),
    ]
    private static let openStrings: [Float] = [82.41, 110, 146.83, 196, 246.94, 329.63]
    private let modes: UnsafeMutablePointer<SVF>
    private let modeGain: UnsafeMutablePointer<Float>
    private let sympathetic: UnsafeMutablePointer<SVF>
    private var noise = Noise(seed: 0x2545_F491)
    private var pickEnvelope: Float = 0, pickLevel: Float = 0, pickPan: Float = 0
    private var pickTick = SVF(), pickThud = SVF()
    private let pickDecay: Float, thudDecay: Float
    private var thudEnvelope: Float = 0
    // chorus: each side hears a slowly moving copy of the other
    private static let lineLength = 4096
    private let lineL: UnsafeMutablePointer<Float>, lineR: UnsafeMutablePointer<Float>
    private var lineIndex = 0
    private var chorusPhase: Float = 0
    private var roomLowL: Float = 0, roomLowR: Float = 0
    private let roomDamp: Float
    private var topL: Float = 0, topR: Float = 0
    private let topCoefficient: Float
    private let taps: [(left: Int, right: Int, gain: Float)]

    init(sampleRate: Float, tuning: Tuning = Tuning()) {
        let sr = sampleRate > 0 ? sampleRate : 44100
        self.sampleRate = sr
        self.tuning = tuning
        strings = StringsDSP(sampleRate: sr)
        modes = .allocate(capacity: Self.bodyModes.count)
        modes.initialize(repeating: SVF(), count: Self.bodyModes.count)
        modeGain = .allocate(capacity: Self.bodyModes.count)
        for (k, m) in Self.bodyModes.enumerated() {
            modes[k].tune(m.0, q: m.1, sampleRate: sr)
            modeGain[k] = m.2
        }
        sympathetic = .allocate(capacity: Self.openStrings.count)
        sympathetic.initialize(repeating: SVF(), count: Self.openStrings.count)
        for (k, f) in Self.openStrings.enumerated() { sympathetic[k].tune(f, q: 240, sampleRate: sr) }
        pickTick.tune(3200, q: 1.2, sampleRate: sr)
        pickThud.tune(160, q: 0.8, sampleRate: sr)
        pickDecay = expf(-1 / (0.004 * sr))
        thudDecay = expf(-1 / (0.012 * sr))
        lineL = .allocate(capacity: Self.lineLength)
        lineL.initialize(repeating: 0, count: Self.lineLength)
        lineR = .allocate(capacity: Self.lineLength)
        lineR.initialize(repeating: 0, count: Self.lineLength)
        roomDamp = 1 - expf(-2 * .pi * 4000 / sr)
        topCoefficient = 1 - expf(-2 * .pi * tuning.top / sr)
        func ms(_ t: Float) -> Int { min(Self.lineLength - 1, Int(t / 1000 * sr)) }
        taps = [(ms(7.3), ms(9.1), 0.16), (ms(13.7), ms(16.9), 0.11), (ms(23.3), ms(21.1), 0.08), (ms(34.1), ms(37.7), 0.05)]
    }

    deinit {
        modes.deallocate()
        modeGain.deallocate()
        sympathetic.deallocate()
        lineL.deallocate()
        lineR.deallocate()
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        strings.render(frameCount: frameCount, buffers: buffers)
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = picks.drain()
        for i in 0..<n {
            let p = picks.taken[i]
            pickLevel = max(0.15, min(1, p.velocity))
            pickPan = p.pan
            pickEnvelope = 1
            thudEnvelope = 1
        }
        let t = tuning
        let size = Self.lineLength
        let twoPi = 2 * Float.pi
        let modeCount = Self.bodyModes.count
        for i in 0..<frameCount {
            let dryL = l[i], dryR = r?[i] ?? l[i]
            let mono = 0.5 * (dryL + dryR)
            var body: Float = 0
            for k in 0..<modeCount { body += modeGain[k] * modes[k].process(mono).band }
            var halo: Float = 0
            for k in 0..<Self.openStrings.count { halo += sympathetic[k].process(body).band }
            halo *= 0.05 * t.sympathetic
            var pick: Float = 0
            if pickEnvelope > 0.0005 || thudEnvelope > 0.0005 {
                let x = noise.bipolar()
                pick = (pickTick.process(x).band * pickEnvelope + 0.6 * pickThud.process(x).low * thudEnvelope) * pickLevel * t.pick
                pickEnvelope *= pickDecay
                thudEnvelope *= thudDecay
            }
            let pickAngle = (pickPan + 1) * 0.25 * .pi
            var outL = dryL * t.dry + body * t.body * 0.5 + halo + pick * cosf(pickAngle)
            var outR = dryR * t.dry + body * t.body * 0.5 + halo * 0.9 + pick * sinf(pickAngle)
            // the top rolls off gently, as wood and air do
            topL += (outL - topL) * topCoefficient
            topR += (outR - topR) * topCoefficient
            outL = topL
            outR = topR
            // chorus: 9 to 12 ms, 0.35 Hz, opposite sides
            chorusPhase += twoPi * 0.35 / sampleRate
            if chorusPhase > twoPi { chorusPhase -= twoPi }
            let delay = (10.5 + 1.5 * sinf(chorusPhase)) / 1000 * sampleRate
            let p = Float(lineIndex) - delay
            let w = p < 0 ? p + Float(size) : p
            let j = Int(w), f = w - Float(j)
            let fromL = lineL[j % size] + (lineL[(j + 1) % size] - lineL[j % size]) * f
            let fromR = lineR[j % size] + (lineR[(j + 1) % size] - lineR[j % size]) * f
            // early reflections, darkened
            var wetL: Float = 0, wetR: Float = 0
            for tap in taps {
                wetL += tap.gain * lineR[(lineIndex - tap.left + size) % size]
                wetR += tap.gain * lineL[(lineIndex - tap.right + size) % size]
            }
            roomLowL += (wetL - roomLowL) * roomDamp
            roomLowR += (wetR - roomLowR) * roomDamp
            lineL[lineIndex] = outL
            lineR[lineIndex] = outR
            lineIndex = (lineIndex + 1) % size
            outL += t.chorus * fromR + t.room * roomLowL
            outR += t.chorus * fromL + t.room * roomLowR
            if !outL.isFinite { outL = 0 }
            if !outR.isFinite { outR = 0 }
            l[i] = outL
            r?[i] = outR
        }
    }
}
