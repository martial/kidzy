import AVFoundation
import os

/// Sound computed sample by sample in Swift (a brush, the sea...). `RenderNode` plugs it into AudioKit.
protocol RenderDSP: AnyObject, Sendable {
    /// From the audio thread: fill `frameCount` frames of every buffer. Never allocates, never waits.
    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer)
}

/// Commands from the main thread to a render callback. The audio thread takes
/// them only when the lock is free (it never waits), into memory allocated up front.
final class DSPQueue<Command: Sendable>: @unchecked Sendable {
    private struct State: Sendable {
        var items: [Command]
        var count = 0
    }

    let capacity: Int
    private let lock: OSAllocatedUnfairLock<State>
    /// Audio thread only: the commands `drain` took.
    let taken: UnsafeMutablePointer<Command>

    init(capacity: Int, filler: Command) {
        self.capacity = capacity
        lock = OSAllocatedUnfairLock(initialState: State(items: [Command](repeating: filler, count: capacity)))
        taken = .allocate(capacity: capacity)
        taken.initialize(repeating: filler, count: capacity)
    }

    deinit { taken.deallocate() }

    /// From the main thread. A full queue drops the command (the audio thread is far behind).
    func send(_ command: Command) {
        lock.withLock { s in
            guard s.count < capacity else { return }
            s.items[s.count] = command
            s.count += 1
        }
    }

    /// From the audio thread: how many commands are now in `taken` (0 if the lock was busy).
    func drain() -> Int {
        nonisolated(unsafe) let taken = self.taken
        return lock.withLockIfAvailable { s -> Int in
            let n = s.count
            for i in 0..<n { taken[i] = s.items[i] }
            s.count = 0
            return n
        } ?? 0
    }
}

/// A state-variable filter (Simper's trapezoidal form): stable while its cutoff moves.
struct SVF {
    private var ic1: Float = 0, ic2: Float = 0
    private var a1: Float = 0, a2: Float = 0, a3: Float = 0
    private(set) var k: Float = 1

    mutating func tune(_ cutoff: Float, q: Float, sampleRate: Float) {
        let f = min(cutoff, sampleRate * 0.45)
        let g = tanf(.pi * f / sampleRate)
        k = 1 / max(0.05, q)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    /// Low-pass, band-pass (normalised to unity at the centre) and high-pass.
    @inline(__always) mutating func process(_ x: Float) -> (low: Float, band: Float, high: Float) {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1 * k, x - k * v1 - v2)
    }

    mutating func reset() { ic1 = 0; ic2 = 0 }
}

/// A fast noise source for the audio thread.
struct Noise {
    var seed: UInt32

    @inline(__always) mutating func next() -> UInt32 {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return seed
    }

    /// -1...1
    @inline(__always) mutating func bipolar() -> Float { Float(next()) * (2 / Float(UInt32.max)) - 1 }
    /// 0...1
    @inline(__always) mutating func unit() -> Float { Float(next()) * (1 / Float(UInt32.max)) }
}
