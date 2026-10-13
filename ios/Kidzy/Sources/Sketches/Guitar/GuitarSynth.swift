import AVFoundation
import Foundation

private let stringCount = 6
private let bufferSize = 2400

/// Six plucked strings (Karplus-Strong) rendered in real time.
@MainActor
final class GuitarSynth {
    private let engine = AVAudioEngine()
    private let bank = StringBank()
    private var source: AVAudioSourceNode?
    private var running = false

    func start() {
        guard !running else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let output = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        bank.sampleRate = Float(sampleRate)
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: bank))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.8
        source = node
        do {
            try engine.start()
            running = true
        } catch {
            engine.detach(node)
            source = nil
        }
    }

    nonisolated static func renderBlock(for bank: StringBank) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, audioBufferList -> OSStatus in
            bank.render(frameCount: Int(frameCount), buffers: UnsafeMutableAudioBufferListPointer(audioBufferList))
            return noErr
        }
    }

    func stop() {
        guard running else { return }
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        running = false
        bank.silence()
    }

    /// Plucks string `index` (0 = low E) at `frequency`; `velocity` 0...1 sets loudness and brightness.
    func pluck(string index: Int, frequency: Double, velocity: Double) {
        bank.pluck(index: index, frequency: Float(frequency), velocity: Float(velocity))
    }

    func mute(string index: Int) { bank.mute(index: index) }
}

/// Karplus-Strong ring buffers, one per string, shared with the audio thread.
final class StringBank: @unchecked Sendable {
    private struct Str {
        var buffer = [Float](repeating: 0, count: bufferSize)
        var length = 100
        var index = 0
        var active = false
        var decay: Float = 0.996
        var pan: Float = 0
        var ticks = 0
    }

    private let lock = NSLock()
    private var strings = [Str](repeating: Str(), count: stringCount)
    var sampleRate: Float = 48000

    func pluck(index: Int, frequency: Float, velocity: Float) {
        guard index >= 0, index < stringCount, frequency > 20 else { return }
        lock.lock()
        defer { lock.unlock() }
        var s = strings[index]
        s.length = max(2, min(bufferSize - 1, Int(sampleRate / frequency)))
        let v = max(0.15, min(1, velocity))
        var prev: Float = 0
        let brightness = 0.35 + 0.65 * v  // a harder strum has more treble
        for i in 0..<s.length {
            let noise = Float.random(in: -1...1)
            let smoothed = prev + (noise - prev) * brightness
            s.buffer[i] = smoothed * v
            prev = smoothed
        }
        s.index = 0
        s.active = true
        s.decay = 0.994 + 0.004 * (1 - Float(index) / Float(stringCount - 1))  // low strings ring longer
        s.pan = (Float(index) / Float(stringCount - 1) - 0.5) * 0.8
        s.ticks = 0
        strings[index] = s
    }

    func mute(index: Int) {
        guard index >= 0, index < stringCount else { return }
        lock.lock()
        strings[index].decay = 0.9
        lock.unlock()
    }

    func silence() {
        lock.lock()
        strings = [Str](repeating: Str(), count: stringCount)
        lock.unlock()
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 1 else { return }
        let left = UnsafeMutablePointer<Float>(OpaquePointer(buffers[0].mData!))
        let right = buffers.count > 1 ? UnsafeMutablePointer<Float>(OpaquePointer(buffers[1].mData!)) : nil
        for i in 0..<frameCount {
            left[i] = 0
            right?[i] = 0
        }
        lock.lock()
        for k in strings.indices where strings[k].active {
            var s = strings[k]
            let angle = (s.pan + 1) * 0.25 * Float.pi
            let gl = cos(angle), gr = sin(angle)
            var energy: Float = 0
            for i in 0..<frameCount {
                let cur = s.buffer[s.index]
                let nextIndex = s.index + 1 == s.length ? 0 : s.index + 1
                let next = s.buffer[nextIndex]
                let out = cur * 0.45
                s.buffer[s.index] = (cur + next) * 0.5 * s.decay
                s.index = nextIndex
                left[i] += out * gl
                right?[i] += out * gr
                energy += abs(out)
            }
            s.ticks += 1
            if s.ticks > 20, energy / Float(frameCount) < 0.0004 { s.active = false }
            strings[k] = s
        }
        lock.unlock()
    }
}
