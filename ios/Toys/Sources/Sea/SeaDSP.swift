import AVFoundation

/// The sea's water, synthesized sample by sample (stereo, every sound different).
///
/// Tuned with blind listening tests: bubbles are what makes it read as water (on
/// their own they were heard as sloshing 95 % of the time); plain noise reads as
/// wind, fast level jumps as gusts, high-passed hiss as metal, and bubbles that
/// ring on every swell as a video game. So:
/// - The bed: two decorrelated streams of pink noise, kept under the bubbles: a
///   soft swell when the sea is calm, opening into a wash as it sloshes, with a
///   crackle of foam on top, its level wavering gently.
/// - Gurgles: bubbles (damped sines whose pitch rises as they close), rare when
///   calm, a stream when the water churns, and a babble of tiny ones inside it.
/// - Splashes: a wave slapping a wall is a thud, a wet body, foam that lingers
///   and a burst of bubbles; a finger poking the sea also has the "bloop" of the
///   cavity it leaves and drops that ring; at the top of a calm swell, a wavelet
///   of foam. Every droplet falling back is a little plip.
/// - The boat: a thud and the tin hull's rattle when it hits the side, water
///   lapping on the hull, and while it is dragged a little tin putt-putt: sharp
///   clacks at a fixed pitch whose rate follows the speed, sputtering now and
///   then, the hull ringing, a hiss of steam, the exhaust bubbling and the wake
///   washing; let go, it winds down.
final class SeaDSP: RenderDSP, @unchecked Sendable {
    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case water, slap, poke, plip, knock, lap, motor, motorOff, silence }
        var kind: Kind
        var a: Float = 0     // water: wash 0...1; events: strength 0...1; motor: speed 0...1
        var pan: Float = 0   // -1...1
    }

    /// A blip of liquid (or wood): a damped sine gliding in pitch, panned.
    private struct Bubble {
        var phase: Float = 0
        var step: Float = 0
        var glide: Float = 1
        var level: Float = 0
        var decay: Float = 0
        var tick: Float = 0       // the impact: a millisecond of noise, so it is not a pure tone
        var gainL: Float = 0, gainR: Float = 0
    }

    /// A slap of water: thud, body, spray and a burst of bubbles.
    private struct Splash {
        var thud: Float = 0, thudDecay: Float = 0
        var body: Float = 0, bodyDecay: Float = 0, bodyAttack: Float = 1
        var spray: Float = 0, sprayDecay: Float = 0, sprayTarget: Float = 0, sprayRise: Float = 0
        var bubbleRate: Float = 0, bubbleDecay: Float = 0, bubbleLow: Float = 400, bubbleHigh: Float = 2400
        var ringing = false      // a poke: its bubbles ring longer, like drops into water
        var pan: Float = 0
        var gainL: Float = 0, gainR: Float = 0
        var low = SVF(), mid = SVF(), high = SVF()
        var active = false
    }

    /// The mix of the sea's layers (1 = as designed; the listening tests mute them one by one).
    struct Tuning: Sendable {
        var bed: Float = 1
        var foam: Float = 1
        var gurgles: Float = 1
        var babble: Float = 1
        var wavelets: Float = 1
        var spray: Float = 1
        var splashBubbles: Float = 1
        var lumps: Float = 1
        var motorBubbles: Float = 1
    }

    static let bubbleCount = 64
    static let splashCount = 6

    let sampleRate: Float
    let queue = DSPQueue<Command>(capacity: 256, filler: Command(kind: .silence))
    private var bubbles: UnsafeMutablePointer<Bubble>
    private var splashes: UnsafeMutablePointer<Splash>
    private var nextBubble = 0, nextSplash = 0
    private var noise = Noise(seed: 0x51A5_EA11)

    // the bed
    private var washTarget: Float = 0, washLevel: Float = 0
    private var pinkL = (Float(0), Float(0), Float(0)), pinkR = (Float(0), Float(0), Float(0))
    private var bandL = SVF(), bandR = SVF(), topL = SVF(), topR = SVF(), hissL = SVF(), hissR = SVF()
    private var swellPhase: Float = 0, swellStep: Float = 0
    private var flutter: Float = 1, flutterTarget: Float = 1, flutterTicks = 0
    private var tick = 0
    private var gate: Float = 1, gateTarget: Float = 1   // `silence` fades everything out; `water` brings it back

    // the motor
    private var motorOn = false
    private var motorSpeed: Float = 0, motorSpeedTarget: Float = 0
    private var motorLevel: Float = 0
    private var motorPhase: Float = 0
    private var motorKick: Float = 0       // the start: a quick burst of pops
    private var motorPan: Float = 0
    private var popLevel: Float = 0, popAttack: Float = 1, puffLevel: Float = 0
    private var puff = SVF(), exhaust1 = SVF(), exhaust2 = SVF(), steam = SVF(), wake = SVF()
    private let popDecay: Float, puffDecay: Float

    // per-sample constants
    private let washRise: Float, washFall: Float, invSR: Float

    let tuning: Tuning

    init(sampleRate: Float, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        let sr = sampleRate > 0 ? sampleRate : 44100
        self.sampleRate = sr
        invSR = 1 / sr
        bubbles = .allocate(capacity: Self.bubbleCount)
        bubbles.initialize(repeating: Bubble(), count: Self.bubbleCount)
        splashes = .allocate(capacity: Self.splashCount)
        splashes.initialize(repeating: Splash(), count: Self.splashCount)
        washRise = 1 - exp(-1 / (0.07 * sr))
        washFall = 1 - exp(-1 / (0.45 * sr))
        swellStep = 2 * .pi / (2.6 * sr)
        puff.tune(320, q: 0.7, sampleRate: sr)
        exhaust1.tune(650, q: 0.8, sampleRate: sr)
        exhaust2.tune(1500, q: 0.7, sampleRate: sr)
        steam.tune(5000, q: 0.6, sampleRate: sr)
        popDecay = exp(-1 / (0.005 * sr))
        puffDecay = exp(-1 / (0.009 * sr))
    }

    deinit {
        bubbles.deallocate()
        splashes.deallocate()
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let n = queue.drain()
        for i in 0..<n { apply(queue.taken[i]) }
        for i in 0..<frameCount {
            if tick <= 0 {
                tick = 32
                retune()
            }
            tick -= 1
            washLevel += (washTarget - washLevel) * (washTarget > washLevel ? washRise : washFall)
            flutter += (flutterTarget - flutter) * 0.0015
            let w = washLevel

            // the bed: calm lapping swell, then the wash
            let before = swellPhase
            swellPhase += swellStep
            if before < .pi / 2, swellPhase >= .pi / 2, w < 0.5 {
                // a wavelet laps at the top of each swell
                if tuning.wavelets > 0 { splash(strength: (0.3 + 0.35 * noise.unit()) * (1 - 2 * w) * tuning.wavelets, pan: noise.bipolar() * 0.7, kind: .wavelet) }
            }
            if swellPhase > 2 * .pi {
                swellPhase -= 2 * .pi
                swellStep = 2 * .pi / ((2.2 + 1.2 * noise.unit()) * sampleRate)
            }
            let swell = 0.5 + 0.5 * sinf(swellPhase)
            let calm: Float = 0.085 * (0.25 + 0.75 * swell * swell) * (1 - w)
            let level = (calm + 0.3 * powf(w, 1.1)) * flutter * tuning.bed
            let pl = pink(&pinkL), pr = pink(&pinkR)
            var outL = topL.process(bandL.process(pl).band).low * level
            var outR = topR.process(bandR.process(pr).band).low * level
            let foam = 0.2 * w * w * flutter * tuning.foam
            if foam > 0.0005 {
                outL += hissL.process(crackle(5000)).high * foam
                outR += hissR.process(crackle(5000)).high * foam
            }

            // gurgles: a few lazy blobs when calm, a stream when it churns
            let gurgles = (0.15 + 60 * powf(w, 1.4)) * tuning.gurgles
            if noise.unit() < gurgles * invSR {
                let size = 1 - w * 0.6
                bubble(from: (300 + 900 * noise.unit()) / max(0.5, size), rise: 1.4 + 1.0 * noise.unit(), seconds: (0.004 + 0.01 * noise.unit()) * (0.6 + size),
                       level: (0.01 + 0.025 * noise.unit()) * (0.4 + 1.2 * w), pan: noise.bipolar() * 0.8)
            }
            // the babble inside moving water: a dense stream of tiny bubbles
            if noise.unit() < (20 + 2400 * powf(w, 1.2)) * tuning.babble * invSR {
                let u = noise.unit()
                bubble(from: 4200 - 3500 * u * u, rise: 1.4 + 0.8 * noise.unit(), seconds: 0.0012 + 0.003 * u,
                       level: (0.003 + 0.009 * u) * (0.3 + w), pan: noise.bipolar() * 0.9)
            }

            // splashes
            for k in 0..<Self.splashCount where splashes[k].active {
                var s = splashes[k]
                let x = noise.bipolar()
                var o: Float = 0
                if s.thud > 0.0005 { o += s.low.process(x).low * s.thud; s.thud *= s.thudDecay }
                if s.bodyAttack < 1 { s.bodyAttack = min(1, s.bodyAttack + 1 / (0.004 * sampleRate)) }
                if s.body > 0.0005 { o += s.mid.process(x).band * s.body * s.bodyAttack; s.body *= s.bodyDecay }
                if s.sprayTarget > 0 {
                    s.spray += s.sprayRise
                    if s.spray >= s.sprayTarget { s.spray = s.sprayTarget; s.sprayTarget = 0 }
                } else {
                    s.spray *= s.sprayDecay
                }
                if s.spray > 0.0005 { o += s.high.process(s.ringing ? 1.2 * x : 0.5 * x + crackle(6000)).high * s.spray * 1.1 * tuning.spray }
                if s.bubbleRate > 1, noise.unit() < s.bubbleRate * invSR {
                    if s.ringing {
                        bubble(from: s.bubbleLow + (s.bubbleHigh - s.bubbleLow) * noise.unit(), rise: 1.15 + 0.7 * noise.unit(), seconds: 0.004 + 0.016 * noise.unit(),
                               level: 0.025 + 0.06 * noise.unit(), pan: s.pan + noise.bipolar() * 0.3, tick: 0.6)
                    } else {
                        bubble(from: s.bubbleLow + (s.bubbleHigh - s.bubbleLow) * noise.unit(), rise: 1.3 + 1.0 * noise.unit(), seconds: 0.003 + 0.009 * noise.unit(),
                               level: 0.012 + 0.035 * noise.unit(), pan: s.pan + noise.bipolar() * 0.3)
                    }
                }
                s.bubbleRate *= s.bubbleDecay
                outL += o * s.gainL
                outR += o * s.gainR
                if s.thud < 0.0005, s.body < 0.0005, s.spray < 0.0005, s.sprayTarget == 0, s.bubbleRate < 1 { s.active = false }
                splashes[k] = s
            }

            // the motor: a little tin putt-putt. Sharp clacks at a fixed pitch (only their
            // rate follows the speed), sputtering now and then, the tin hull rattling after
            // each, a hiss of steam, the exhaust bubbling and the wake washing behind it
            if motorLevel > 0.0005 || motorOn {
                motorSpeed += (motorSpeedTarget - motorSpeed) * 0.0004
                motorKick *= 0.99996
                let target: Float = motorOn ? 0.2 + 0.14 * motorSpeed : 0
                motorLevel += (target - motorLevel) * (motorOn ? 0.0008 : 0.00012)
                let rate = (motorOn ? 6.5 + 13 * motorSpeed : 2.5 + 4 * motorSpeed) + 14 * motorKick
                motorPhase += rate * invSR
                if motorPhase >= 1 {
                    motorPhase = max(0, 0.15 * noise.bipolar())
                    // a misfire now and then
                    if noise.unit() > 0.07 {
                        popLevel = 0.75 + 0.5 * noise.unit()
                        popAttack = 0
                        puffLevel = popLevel
                        let ring = 0.022 * popLevel * motorLevel / 0.3
                        bubble(from: 1850 * (0.98 + 0.04 * noise.unit()), rise: 1, seconds: 0.012, level: ring, pan: motorPan)
                        bubble(from: 2930 * (0.98 + 0.04 * noise.unit()), rise: 1, seconds: 0.009, level: ring * 0.7, pan: motorPan)
                        bubble(from: 4370 * (0.98 + 0.04 * noise.unit()), rise: 1, seconds: 0.006, level: ring * 0.45, pan: motorPan)
                        for _ in 0..<(Int((1 + noise.unit() * 2.5) * tuning.motorBubbles)) {
                            bubble(from: 240 + 380 * noise.unit(), rise: 1.5 + 0.8 * noise.unit(), seconds: 0.005 + 0.01 * noise.unit(), level: 0.045 * motorLevel / 0.3, pan: motorPan + 0.2 * noise.bipolar())
                        }
                    }
                }
                var o: Float = 0
                let x = noise.bipolar()
                if popLevel > 0.0005 {
                    popAttack = min(1, popAttack + 1 / (0.0005 * sampleRate))
                    let e = x * popLevel * popAttack
                    o += exhaust1.process(e).band * 0.9 + exhaust2.process(e).high * 0.45
                    popLevel *= popDecay
                }
                if puffLevel > 0.0005 {
                    o += puff.process(x).low * puffLevel * 0.9
                    puffLevel *= puffDecay
                }
                // steam, and the wake the boat drags behind it
                o += steam.process(noise.bipolar()).low * 0.05
                o += wake.process(noise.bipolar()).band * 0.35 * motorSpeed
                if motorOn, noise.unit() < 45 * motorSpeed * invSR {
                    bubble(from: 350 + 900 * noise.unit(), rise: 1.4 + 0.8 * noise.unit(), seconds: 0.004 + 0.01 * noise.unit(), level: 0.02 + 0.03 * noise.unit(), pan: motorPan + 0.3 * noise.bipolar())
                }
                o *= motorLevel
                let a = (motorPan + 1) * 0.25 * .pi
                outL += o * cosf(a)
                outR += o * sinf(a)
            }

            // every blip
            for k in 0..<Self.bubbleCount where bubbles[k].level > 0.0004 {
                var b = bubbles[k]
                var s = sinf(b.phase) * b.level
                if b.tick > 0.0002 {
                    s += noise.bipolar() * b.tick
                    b.tick *= 0.975
                }
                b.phase += b.step
                if b.phase > 2 * .pi { b.phase -= 2 * .pi }
                b.step = min(b.step * b.glide, 2.6)
                b.level *= b.decay
                outL += s * b.gainL
                outR += s * b.gainR
                bubbles[k] = b
            }

            gate += (gateTarget - gate) * 0.0006
            var lo = outL * gate, ro = outR * gate
            if !lo.isFinite { lo = 0 }
            if !ro.isFinite { ro = 0 }
            l[i] = lo
            r?[i] = ro
        }
    }

    // MARK: - pieces

    /// Foam: a dense crackle of bursting bubbles (random impulses, mostly tiny, a few
    /// big), which reads as fizz; plain high-passed noise reads as wind or metal.
    @inline(__always) private func crackle(_ density: Float) -> Float {
        guard noise.unit() < density * invSR else { return 0 }
        let u = noise.unit()
        return (noise.unit() < 0.5 ? -1 : 1) * u * u * u * 2.2
    }

    /// Paul Kellet's economy pink filter.
    @inline(__always) private func pink(_ b: inout (Float, Float, Float)) -> Float {
        let w = noise.bipolar()
        b.0 = 0.99765 * b.0 + w * 0.0990460
        b.1 = 0.96300 * b.1 + w * 0.2965164
        b.2 = 0.57000 * b.2 + w * 1.0526913
        return (b.0 + b.1 + b.2 + w * 0.1848) * 0.22
    }

    private func retune() {
        let w = washLevel
        bandL.tune(460 + 1100 * w, q: 0.6, sampleRate: sampleRate)
        bandR.tune(500 + 1150 * w, q: 0.6, sampleRate: sampleRate)
        topL.tune(1500 + 4500 * w, q: 0.6, sampleRate: sampleRate)
        topR.tune(1600 + 4600 * w, q: 0.6, sampleRate: sampleRate)
        hissL.tune(2600, q: 0.6, sampleRate: sampleRate)
        hissR.tune(2800, q: 0.6, sampleRate: sampleRate)
        wake.tune(900 + 1600 * motorSpeed, q: 0.7, sampleRate: sampleRate)
        flutterTicks -= 1
        if flutterTicks <= 0 {
            // moving water's level wavers some five to twelve times a second
            // the level wavers some five to twelve times a second (faster, deeper lumps read as wind)
            flutterTicks = Int(sampleRate / 32 / (5 + 7 * noise.unit()))
            flutterTarget = 1 - 0.3 * tuning.lumps + 0.6 * tuning.lumps * noise.unit()
        }
    }

    private func bubble(from f: Float, rise: Float, seconds: Float, level: Float, pan: Float, tick: Float = 0) {
        let life = max(0.002, seconds)
        let p = min(1, max(-1, pan))
        let a = (p + 1) * 0.25 * .pi
        bubbles[nextBubble] = Bubble(phase: 0, step: 2 * .pi * f * invSR, glide: powf(max(0.2, rise), 1 / (life * sampleRate)), level: level,
                                     decay: expf(-1 / (life * sampleRate)), tick: level * tick, gainL: cosf(a), gainR: sinf(a))
        nextBubble = (nextBubble + 1) % Self.bubbleCount
    }

    private enum SplashKind { case slap, poke, wavelet }

    private func splash(strength: Float, pan: Float, kind: SplashKind) {
        let poke = kind == .poke, wavelet = kind == .wavelet
        let s = min(1, max(0, strength))
        let p = min(1, max(-1, pan))
        let a = (p + 1) * 0.25 * .pi
        var v = Splash()
        v.active = true
        v.pan = p
        v.gainL = cosf(a)
        v.gainR = sinf(a)
        let size = 0.8 + 0.4 * noise.unit()          // every splash a little different
        v.low.tune(160 + 120 * noise.unit(), q: 0.7, sampleRate: sampleRate)
        v.mid.tune((520 + 600 * noise.unit()) / size, q: 0.9, sampleRate: sampleRate)
        v.high.tune(wavelet ? 1100 + 700 * noise.unit() : 2000 + 1800 * noise.unit(), q: 0.6, sampleRate: sampleRate)
        v.thud = wavelet ? 0 : (poke ? 0.35 : 0.5) * s
        v.thudDecay = expf(-1 / ((0.03 + 0.03 * noise.unit()) * sampleRate))
        v.body = wavelet ? 0.25 * s : (poke ? 0.5 : 0.6) * s
        v.bodyAttack = 0
        v.bodyDecay = expf(-1 / ((wavelet ? 0.25 : 0.08 + 0.1 * s) * size * sampleRate))
        // a wavelet is mostly foam: a soft hiss that swells and drains
        v.sprayTarget = wavelet ? 0.08 * s : (poke ? 0.07 + 0.14 * s * s : s * (0.08 + 0.14 * s))
        v.sprayRise = v.sprayTarget / ((wavelet ? 0.12 + 0.12 * noise.unit() : 0.012 + 0.02 * noise.unit()) * sampleRate)
        v.sprayDecay = expf(-1 / ((wavelet ? 0.45 : 0.12 + 0.3 * s) * sampleRate))
        // a wavelet is foam only: bubbles on every swell read as a game, not the sea
        v.bubbleRate = (wavelet ? 0 : (60 + 180 * s) * (poke ? 1.3 : 1)) * tuning.splashBubbles
        v.ringing = poke
        v.bubbleDecay = expf(-1 / ((0.1 + 0.15 * s) * sampleRate))
        v.bubbleLow = poke ? 500 : (wavelet ? 300 : 380)
        v.bubbleHigh = poke ? 2600 : (wavelet ? 1000 : 2000)
        splashes[nextSplash] = v
        nextSplash = (nextSplash + 1) % Self.splashCount
        if poke {
            // the cavity the finger leaves closes with a rising "bloop"
            bubble(from: 210 + 90 * noise.unit(), rise: 2.5 + 0.8 * noise.unit(), seconds: 0.03 + 0.015 * noise.unit(), level: 0.12 + 0.08 * s, pan: p, tick: 0.3)
        }
    }

    private func apply(_ c: Command) {
        switch c.kind {
        case .water:
            washTarget = min(1, max(0, c.a))
            gateTarget = 1
        case .slap:
            splash(strength: c.a, pan: c.pan, kind: .slap)
        case .poke:
            splash(strength: c.a, pan: c.pan, kind: .poke)
        case .plip:
            // a droplet falling back: a small bright bubble and the tick of its impact
            bubble(from: 1100 + 2000 * noise.unit(), rise: 1.3 + 0.8 * noise.unit(), seconds: 0.006 + 0.012 * noise.unit(), level: (0.04 + 0.06 * noise.unit()) * (0.5 + c.a), pan: c.pan, tick: 0.8)
        case .knock:
            // the boat hits the side: a thud, the tin hull's rattle, a slap of water
            let f = 190 + 70 * noise.unit()
            let s = min(1, max(0, c.a))
            bubble(from: f, rise: 0.9, seconds: 0.02, level: 0.14 * s, pan: c.pan, tick: 1.2)
            bubble(from: 1850 * (0.97 + 0.06 * noise.unit()), rise: 1, seconds: 0.03, level: 0.05 * s, pan: c.pan)
            bubble(from: 2930 * (0.97 + 0.06 * noise.unit()), rise: 1, seconds: 0.022, level: 0.035 * s, pan: c.pan)
            bubble(from: 4370 * (0.97 + 0.06 * noise.unit()), rise: 1, seconds: 0.015, level: 0.02 * s, pan: c.pan)
            splash(strength: 0.45 * s, pan: c.pan, kind: .slap)
        case .lap:
            // water rising on the hull: a soft hollow clop
            let s = min(1, max(0, c.a))
            bubble(from: 220 + 220 * noise.unit(), rise: 1.4 + 0.5 * noise.unit(), seconds: 0.012 + 0.012 * noise.unit(), level: 0.06 + 0.1 * s, pan: c.pan, tick: 0.5)
            splash(strength: 0.18 + 0.2 * s, pan: c.pan, kind: .slap)
        case .motor:
            if !motorOn { motorKick = 1 }
            motorOn = true
            motorSpeedTarget = min(1, max(0, c.a))
            motorPan = min(1, max(-1, c.pan))
        case .motorOff:
            motorOn = false
            motorSpeedTarget = 0
        case .silence:
            gateTarget = 0
            washTarget = 0
            motorOn = false
            motorSpeedTarget = 0
            for k in 0..<Self.splashCount where splashes[k].active {
                splashes[k].sprayTarget = 0
                splashes[k].bubbleRate = 0
            }
        }
    }
}
