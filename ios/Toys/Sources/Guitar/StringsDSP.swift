import AVFoundation
import os

/// Extended Karplus-Strong strings. Everything the audio thread touches is
/// allocated up front; commands arrive through a small queue that the audio
/// thread only reads when the lock is free (it never waits).
final class StringsDSP: RenderDSP, @unchecked Sendable {
    struct Command: Sendable {
        enum Kind: UInt8, Sendable { case pluck, damp, silence }
        var kind: Kind
        var voice: Int32 = 0
        var frequency: Float = 0
        var velocity: Float = 0
        var pan: Float = 0
        var t60: Float = 3
        var time: Float = 0.06
    }

    private struct Queue: Sendable {
        var items = [Command](repeating: Command(kind: .silence), count: StringsDSP.queueCapacity)
        var count = 0
    }

    private struct Voice {
        var length = 0          // whole samples in the loop
        var index = 0
        var previous: Float = 0 // loop filter memory
        var apIn: Float = 0, apOut: Float = 0, apCoef: Float = 0
        var rho: Float = 0.996  // loop gain per period
        var gainL: Float = 0, gainR: Float = 0
        var envelope: Float = 1 // 1, or falling to 0 while damped
        var envelopeStep: Float = 0
        var active = false
        var quiet = 0           // samples in a row below the floor
    }

    static let voiceCount = 16  // two per string, four melody
    static let queueCapacity = 128
    static let maxLength = 4096

    let sampleRate: Float
    private let queue = OSAllocatedUnfairLock(initialState: Queue())
    private let pending: UnsafeMutablePointer<Command>
    private let voices: UnsafeMutablePointer<Voice>
    private let lines: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private var seed: UInt32 = 0x9E37_79B9
    private var dcIn: Float = 0, dcOutL: Float = 0, dcOutR: Float = 0, dcInR: Float = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        pending = .allocate(capacity: Self.queueCapacity)
        pending.initialize(repeating: Command(kind: .silence), count: Self.queueCapacity)
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        lines = .allocate(capacity: Self.voiceCount * Self.maxLength)
        lines.initialize(repeating: 0, count: Self.voiceCount * Self.maxLength)
        scratch = .allocate(capacity: Self.maxLength)
        scratch.initialize(repeating: 0, count: Self.maxLength)
    }

    deinit {
        pending.deallocate()
        voices.deallocate()
        lines.deallocate()
        scratch.deallocate()
    }

    /// From the main thread.
    func send(_ command: Command) {
        queue.withLock { q in
            guard q.count < StringsDSP.queueCapacity else { return }
            q.items[q.count] = command
            q.count += 1
        }
    }

    /// From the audio thread.
    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        // only this thread reads `pending`; the lock guards the queue it copies from
        nonisolated(unsafe) let pending = self.pending
        let n = queue.withLockIfAvailable { q -> Int in
            let n = q.count
            for i in 0..<n { pending[i] = q.items[i] }
            q.count = 0
            return n
        } ?? 0
        for i in 0..<n { apply(pending[i]) }

        for i in 0..<frameCount {
            l[i] = 0
            r?[i] = 0
        }
        for v in 0..<Self.voiceCount where voices[v].active {
            var s = voices[v]
            let line = lines + v * Self.maxLength
            for i in 0..<frameCount {
                let y = line[s.index]
                // loop: two-point average (the string's losses), allpass (exact pitch), gain (decay)
                let averaged = 0.5 * (y + s.previous)
                s.previous = y
                let ap = s.apCoef * averaged + s.apIn - s.apCoef * s.apOut
                s.apIn = averaged
                s.apOut = ap
                line[s.index] = ap * s.rho
                s.index += 1
                if s.index >= s.length { s.index = 0 }
                var out = y * s.envelope
                if s.envelopeStep > 0 {
                    s.envelope = max(0, s.envelope - s.envelopeStep)
                }
                if !out.isFinite { out = 0 }
                l[i] += out * s.gainL
                r?[i] += out * s.gainR
                s.quiet = abs(out) < 0.0002 ? s.quiet + 1 : 0
            }
            if s.envelope <= 0 || s.quiet > Int(sampleRate * 0.25) {
                s.active = false
                for k in 0..<s.length { line[k] = 0 }
            }
            voices[v] = s
        }
        // remove any DC the strings carry (one-pole high-pass at ~20 Hz)
        let R: Float = 0.9972
        for i in 0..<frameCount {
            let x = l[i]
            dcOutL = x - dcIn + R * dcOutL
            dcIn = x
            l[i] = dcOutL
            if let r {
                let xr = r[i]
                dcOutR = xr - dcInR + R * dcOutR
                dcInR = xr
                r[i] = dcOutR
            }
        }
    }

    private func apply(_ c: Command) {
        switch c.kind {
        case .silence:
            for v in 0..<Self.voiceCount where voices[v].active {
                voices[v].envelopeStep = 1 / (0.04 * sampleRate)
            }
        case .damp:
            let v = Int(c.voice)
            guard (0..<Self.voiceCount).contains(v), voices[v].active else { return }
            voices[v].envelopeStep = 1 / (max(0.005, c.time) * sampleRate)
        case .pluck:
            pluck(c)
        }
    }

    private func pluck(_ c: Command) {
        let v = Int(c.voice)
        guard (0..<Self.voiceCount).contains(v), c.frequency > 20 else { return }
        // loop length P = N + 0.5 (average) + d (allpass), 0.1 <= d < 1.1
        let period = sampleRate / c.frequency
        let whole = max(8, min(Self.maxLength - 1, Int(period - 0.6)))
        let d = max(0.1, period - 0.5 - Float(whole))
        let velocity = max(0.12, min(1, c.velocity))
        // excitation: noise, low-passed by the velocity, combed at the pick position, centred
        let brightness = 0.22 + 0.62 * velocity
        var lp: Float = 0
        var mean: Float = 0
        for k in 0..<whole {
            lp += brightness * (noise() - lp)
            scratch[k] = lp
        }
        let pick = max(1, Int(Float(whole) * 0.13))
        for k in stride(from: whole - 1, through: pick, by: -1) { scratch[k] -= scratch[k - pick] }
        for k in 0..<whole { mean += scratch[k] }
        mean /= Float(whole)
        var peak: Float = 0.0001
        for k in 0..<whole {
            scratch[k] -= mean
            peak = max(peak, abs(scratch[k]))
        }
        let level = 0.55 * pow(velocity, 1.3) / peak
        let line = lines + v * Self.maxLength
        for k in 0..<whole { line[k] = scratch[k] * level }
        let angle = (min(1, max(-1, c.pan)) + 1) * 0.25 * .pi
        voices[v] = Voice(
            length: whole, index: 0, previous: 0, apIn: 0, apOut: 0,
            apCoef: (1 - d) / (1 + d),
            rho: pow(10, -3 / (max(0.3, c.t60) * c.frequency)),
            gainL: cos(angle), gainR: sin(angle),
            envelope: 1, envelopeStep: 0, active: true, quiet: 0
        )
    }

    private func noise() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }
}
