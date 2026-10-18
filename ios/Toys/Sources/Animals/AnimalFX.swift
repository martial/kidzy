import AVFoundation

/// The animals' little sounds around the recordings, synthesized:
/// - a whoosh when the next animal slides in (noise sweeping up, moving across
///   the stereo the way the swipe went), landing with a soft pop and thump;
/// - a springy "boing" when an animal bounces.
final class AnimalFX: RenderDSP, @unchecked Sendable {
    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case whoosh, boing }
        var kind: Kind
        /// -1: the swipe went left, 1: right.
        var direction: Float = 1
        var seed: UInt32 = 1
    }

    let queue = DSPQueue<Command>(capacity: 16, filler: Command(kind: .boing))
    private let sampleRate: Float
    private var noise = Noise(seed: 0x6C07_8965)
    // the whoosh
    private var whooshAt = -1, whooshLength = 0
    private var direction: Float = 1
    private var band = SVF()
    // the landing: a bubble pop and a thump
    private var pop = (phase: Float(0), step: Float(0), glide: Float(1), level: Float(0), decay: Float(0))
    private var thump = (phase: Float(0), level: Float(0), decay: Float(0))
    private var landAt = -1
    // the boing: a spring's wobbling pitch
    private var boingAt = -1, boingLength = 0
    private var boingPhase: Float = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        whooshLength = Int(0.22 * self.sampleRate)
        boingLength = Int(0.28 * self.sampleRate)
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = queue.drain()
        for i in 0..<n { apply(queue.taken[i]) }
        let twoPi = 2 * Float.pi
        for i in 0..<frameCount {
            var mono: Float = 0, left: Float = 0, right: Float = 0
            if whooshAt >= 0 {
                let t = Float(whooshAt) / Float(whooshLength)
                if whooshAt & 15 == 0 { band.tune(500 + 2600 * t * t, q: 1.3, sampleRate: sampleRate) }
                let envelope = t < 0.3 ? t / 0.3 : (1 - t) / 0.7
                let w = band.process(noise.bipolar()).band * envelope * envelope * 0.32
                // across the stereo, the way the finger went
                let angle = (direction * (t * 1.6 - 0.8) + 1) * 0.25 * .pi
                left += w * cosf(angle)
                right += w * sinf(angle)
                whooshAt += 1
                if whooshAt >= whooshLength { whooshAt = -1 }
            }
            if landAt >= 0 {
                landAt -= 1
                if landAt < 0 {
                    // the new animal lands
                    let f = 650 + 300 * noise.unit()
                    pop = (0, twoPi * f / sampleRate, powf(1.7, 1 / (0.03 * sampleRate)), 0.16, expf(-1 / (0.012 * sampleRate)))
                    thump = (0, 0.22, expf(-1 / (0.03 * sampleRate)))
                }
            }
            if pop.level > 0.0005 {
                mono += sinf(pop.phase) * pop.level
                pop.phase += pop.step
                if pop.phase > twoPi { pop.phase -= twoPi }
                pop.step *= pop.glide
                pop.level *= pop.decay
            }
            if thump.level > 0.0005 {
                mono += sinf(thump.phase) * thump.level
                thump.phase += twoPi * 120 / sampleRate
                if thump.phase > twoPi { thump.phase -= twoPi }
                thump.level *= thump.decay
            }
            if boingAt >= 0 {
                let t = Float(boingAt) / sampleRate
                // the spring: 330 Hz wobbling ±18 % at 14 Hz, the wobble dying away
                let f = 330 * (1 + 0.18 * expf(-t * 9) * sinf(twoPi * 14 * t))
                boingPhase += twoPi * f / sampleRate
                if boingPhase > twoPi { boingPhase -= twoPi }
                let envelope = min(1, t / 0.006) * expf(-t * 11)
                mono += (sinf(boingPhase) + 0.25 * sinf(2 * boingPhase)) * envelope * 0.13
                boingAt += 1
                if boingAt >= boingLength { boingAt = -1 }
            }
            var outL = mono + left, outR = mono + right
            if !outL.isFinite { outL = 0 }
            if !outR.isFinite { outR = 0 }
            l[i] = outL
            r?[i] = outR
        }
    }

    private func apply(_ c: Command) {
        noise = Noise(seed: c.seed | 1)
        switch c.kind {
        case .whoosh:
            direction = c.direction < 0 ? -1 : 1
            band.reset()
            whooshAt = 0
            landAt = Int(0.2 * sampleRate)
        case .boing:
            boingAt = 0
            boingPhase = 0
        }
    }
}
