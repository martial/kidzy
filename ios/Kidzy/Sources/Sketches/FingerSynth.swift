import AVFoundation
import Foundation

private let maxVoices = 8

/// A tiny polyphonic synth rendered in real time: one voice per finger.
/// The main actor sets targets; the audio thread smooths and renders them.
@MainActor
final class FingerSynth {
    private let engine = AVAudioEngine()
    private let bank = VoiceBank()
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
        // The render block runs on the audio thread: it must not carry main-actor isolation.
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: bank))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
        source = node
        do {
            try engine.start()
            running = true
        } catch {
            engine.detach(node)
            source = nil
        }
    }

    nonisolated static func renderBlock(for bank: VoiceBank) -> AVAudioSourceNodeRenderBlock {
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
        bank.reset()
    }

    /// A finger (or the boat) starts: a short "boing" slides down to the voice's pitch.
    func began(id: Int, voice: FingerVoice) {
        bank.set(id: id, voice: voice, boing: true)
    }

    func update(id: Int, voice: FingerVoice) {
        bank.set(id: id, voice: voice, boing: false)
    }

    func ended(id: Int) {
        bank.release(id: id)
    }
}

/// Shared between the main actor and the audio thread, guarded by a lock
/// held for microseconds per render.
final class VoiceBank: @unchecked Sendable {
    private struct Voice {
        var id = -1
        var active = false
        var targetFreq: Float = 220
        var targetAmp: Float = 0
        var targetPan: Float = 0
        var vibrato: Float = 0
        var brightness: Float = 0.5
        var freq: Float = 220
        var amp: Float = 0
        var pan: Float = 0
        var phase: Float = 0
        var vibPhase: Float = 0
        var boing: Float = 0  // seconds left of the pitch drop
    }

    private let lock = NSLock()
    private var voices = [Voice](repeating: Voice(), count: maxVoices)
    var sampleRate: Float = 48000

    func set(id: Int, voice: FingerVoice, boing: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var slot = voices.firstIndex { $0.id == id }
        if slot == nil {
            slot = voices.firstIndex { !$0.active && $0.amp < 0.001 } ?? voices.firstIndex { !$0.active }
            if let s = slot {
                voices[s] = Voice()
                voices[s].id = id
                voices[s].freq = Float(voice.frequency)
                voices[s].pan = Float(voice.pan)
            }
        }
        guard let s = slot else { return }
        voices[s].active = true
        voices[s].targetFreq = Float(voice.frequency)
        voices[s].targetAmp = Float(voice.amplitude)
        voices[s].targetPan = Float(voice.pan)
        voices[s].vibrato = Float(voice.vibrato)
        voices[s].brightness = Float(voice.brightness)
        if boing { voices[s].boing = 0.14 }
    }

    func release(id: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let s = voices.firstIndex(where: { $0.id == id }) {
            voices[s].active = false
            voices[s].targetAmp = 0
        }
    }

    func reset() {
        lock.lock()
        voices = [Voice](repeating: Voice(), count: maxVoices)
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
        let dt = 1 / sampleRate
        let ampSmooth: Float = 0.0025, freqSmooth: Float = 0.004, panSmooth: Float = 0.002
        for v in voices.indices where voices[v].amp > 0.0005 || voices[v].targetAmp > 0 {
            var voice = voices[v]
            for i in 0..<frameCount {
                voice.amp += (voice.targetAmp - voice.amp) * (voice.targetAmp > voice.amp ? ampSmooth * 3 : ampSmooth)
                voice.freq += (voice.targetFreq - voice.freq) * freqSmooth
                voice.pan += (voice.targetPan - voice.pan) * panSmooth
                var f = voice.freq
                if voice.boing > 0 {
                    f *= 1 + 1.5 * (voice.boing / 0.14)
                    voice.boing -= dt
                }
                voice.vibPhase += 2 * .pi * 6 * dt
                f *= 1 + voice.vibrato * sin(voice.vibPhase)
                voice.phase += 2 * .pi * f * dt
                if voice.phase > 2 * .pi { voice.phase -= 2 * .pi }
                let s = sin(voice.phase) + voice.brightness * 0.45 * sin(2 * voice.phase) + voice.brightness * 0.18 * sin(3 * voice.phase) + 0.08 * sin(0.5 * voice.phase)
                let sample = s * voice.amp * 0.35
                let angle = (voice.pan + 1) * 0.25 * .pi
                left[i] += sample * cos(angle)
                right?[i] += sample * sin(angle)
            }
            voices[v] = voice
        }
        lock.unlock()
        if right == nil {
            for i in 0..<frameCount { left[i] *= 1.4 }
        }
    }
}
