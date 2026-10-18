import AVFoundation
import Accelerate
import Foundation
import os

/// The parrot's ear and voice: listens through the microphone, cuts out each
/// phrase when the voice stops, and plays it back pitched. The view reads
/// `state`, `level` (the voice coming in) and `mouth` (the voice going out).
@MainActor
@Observable
final class ParrotEar {
    enum State {
        case idle
        case listening
        case repeating
    }

    private(set) var state: State = .idle
    private(set) var level = 0.0
    private(set) var mouth = 0.0
    /// "heard" when a voice starts, "repeat" when the parrot starts talking.
    var onEvent: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let shifter = AVAudioUnitTimePitch()
    private let tape = Tape()
    private var detector = RepeatDetector()
    private var loop: Task<Void, Never>?
    private var last: AVAudioPCMBuffer?
    private var voiceFormat: AVAudioFormat?
    private var wired = false
    /// Set while asking for the microphone: the permission alert makes the
    /// scene inactive then active again, which calls `start()` a second time.
    private var starting = false
    /// False once the toy is gone: a permission answered after leaving must not open the microphone.
    private var wanted = false
    private var lastVoice = -1
    private var lastLevelLog = 0.0
    private let traceEvery = ProcessInfo.processInfo.environment["KIDZY_PARROT_TRACE"] == nil ? 2.0 : 0.25
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.screenclub", category: "parrot")

    /// The silly voices, in cents and speed: mostly tiny, now and then a giant.
    static let voices: [(pitch: Float, rate: Float)] = [(900, 1.0), (700, 1.12), (1100, 1.0), (1200, 1.15), (-500, 0.92)]

    func start() async {
        wanted = true
        guard state == .idle, !starting else { return }
        starting = true
        defer { starting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            log.notice("microphone refused")
            return
        }
        guard wanted, state == .idle, !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            log.error("session: \(error.localizedDescription)")
            return
        }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0, let format = AVAudioFormat(standardFormatWithSampleRate: inFormat.sampleRate, channels: 1) else {
            log.notice("no microphone")
            return
        }
        tape.reset(sampleRate: inFormat.sampleRate)
        voiceFormat = format
        if !wired {
            wired = true
            engine.attach(player)
            engine.attach(shifter)
        }
        engine.connect(player, to: shifter, format: format)
        engine.connect(shifter, to: engine.mainMixerNode, format: format)
        input.removeTap(onBus: 0)   // never two taps on one bus: that is an exception, not an error
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat, block: Self.tapBlock(for: tape))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            log.error("engine: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            return
        }
        detector = RepeatDetector()
        state = .listening
        log.notice("listening at \(inFormat.sampleRate) Hz")
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        wanted = false
        loop?.cancel()
        loop = nil
        player.stop()
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        state = .idle
        level = 0
        mouth = 0
    }

    /// Says the last phrase again; false when there is none yet.
    @discardableResult
    func replay() -> Bool {
        guard state == .listening, let last else { return false }
        Task { await speak(last) }
        return true
    }

    // The tap runs on the audio thread: built outside the actor so it inherits no isolation.
    nonisolated private static func tapBlock(for tape: Tape) -> AVAudioNodeTapBlock {
        { buffer, _ in tape.append(buffer) }
    }

    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            guard state == .listening else { continue }
            let (raw, written) = tape.snapshot()
            let t = Double(written) / tape.sampleRate
            // for the eyes: how far above the room the voice is
            level += (min(1, raw / (detector.threshold * 4)) - level) * 0.35
            if t - lastLevelLog > traceEvery {
                lastLevelLog = t
                log.info("level \(raw, format: .fixed(precision: 4)) room \(self.detector.noiseFloor, format: .fixed(precision: 4)) threshold \(self.detector.threshold, format: .fixed(precision: 4))")
            }
            switch detector.feed(level: raw, at: t) {
            case .started:
                log.notice("heard, level \(raw, format: .fixed(precision: 3))")
                onEvent?("heard")
            case .ended(let from, let to):
                log.notice("phrase \(to - from, format: .fixed(precision: 2)) s")
                if let buffer = voice(from: from, to: to) {
                    last = buffer
                    await speak(buffer)
                }
            case nil:
                break
            }
        }
    }

    private func voice(from: Double, to: Double) -> AVAudioPCMBuffer? {
        guard let format = voiceFormat else { return nil }
        let samples = tape.cut(from: from, to: to)
        let n = samples.count
        guard n > Int(format.sampleRate * 0.2) else { return nil }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(n))
        guard peak > 0.002 else { return nil }
        // loud and clean: a small voice becomes a big one, with short fades against clicks
        var gain = min(8, 0.9 / peak)
        var out = [Float](repeating: 0, count: n)
        vDSP_vsmul(samples, 1, &gain, &out, 1, vDSP_Length(n))
        let fade = min(n / 2, Int(format.sampleRate * 0.015))
        for i in 0..<fade {
            let k = Float(i) / Float(fade)
            out[i] *= k
            out[n - 1 - i] *= k
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(n)
        out.withUnsafeBufferPointer { src in channel.update(from: src.baseAddress!, count: n) }
        return buffer
    }

    private func speak(_ buffer: AVAudioPCMBuffer) async {
        guard engine.isRunning, state != .repeating else { return }
        state = .repeating
        var i = Int.random(in: 0..<Self.voices.count)
        if i == lastVoice { i = (i + 1) % Self.voices.count }
        lastVoice = i
        let v = Self.voices[i]
        shifter.pitch = v.pitch
        shifter.rate = v.rate
        log.notice("repeat: pitch \(v.pitch) rate \(v.rate)")
        onEvent?("repeat")
        let window = 0.04
        let envelope = Self.envelope(of: buffer, window: window)
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate / Double(v.rate)
        player.stop()
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()
        let started = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > seconds + 0.15 { break }
            let slot = Int(elapsed * Double(v.rate) / window)
            mouth += ((slot < envelope.count ? envelope[slot] : 0) - mouth) * 0.6
            try? await Task.sleep(for: .milliseconds(33))
        }
        mouth = 0
        level = 0
        try? await Task.sleep(for: .milliseconds(350))
        detector.reset()
        _ = tape.snapshot()
        if state == .repeating { state = .listening }
    }

    /// Loudness per window, 0...1, so the beak follows the voice.
    nonisolated private static func envelope(of buffer: AVAudioPCMBuffer, window: Double) -> [Double] {
        guard let data = buffer.floatChannelData?[0] else { return [] }
        let n = Int(buffer.frameLength)
        let w = max(1, Int(window * buffer.format.sampleRate))
        var out: [Double] = []
        var i = 0
        while i < n {
            let m = min(w, n - i)
            var rms: Float = 0
            vDSP_rmsqv(data + i, 1, &rms, vDSP_Length(m))
            out.append(Double(rms))
            i += m
        }
        let peak = out.max() ?? 0
        return peak > 0 ? out.map { min(1, $0 / peak * 1.4) } : out
    }
}

/// The last seconds of microphone audio: written on the audio thread, read on
/// the main one. Positions are counted in samples since the start.
final class Tape: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: [Float] = []
    private var capacity = 0
    private var written = 0
    private var peak: Float = 0
    private(set) var sampleRate = 48000.0

    func reset(sampleRate: Double, seconds: Double = 12) {
        lock.withLock {
            self.sampleRate = sampleRate
            capacity = Int(sampleRate * seconds)
            ring = [Float](repeating: 0, count: capacity)
            written = 0
            peak = 0
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(n))
        lock.withLock {
            guard capacity > 0 else { return }
            for i in 0..<n { ring[(written + i) % capacity] = data[i] }
            written += n
            peak = max(peak, rms)
        }
    }

    /// The loudest reading since the last call, and the samples written so far.
    func snapshot() -> (level: Double, written: Int) {
        lock.withLock {
            defer { peak = 0 }
            return (Double(peak), written)
        }
    }

    /// The samples between two times, as far as the tape still has them.
    func cut(from: Double, to: Double) -> [Float] {
        lock.withLock {
            let lo = max(Int(from * sampleRate), written - capacity, 0)
            let hi = min(Int(to * sampleRate), written)
            guard hi > lo else { return [] }
            return (lo..<hi).map { ring[$0 % capacity] }
        }
    }
}
