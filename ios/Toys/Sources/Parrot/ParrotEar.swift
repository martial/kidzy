@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import Accelerate
import Foundation
import os

/// The parrot's ear and voice: listens through the microphone, cuts out each
/// phrase when the voice stops, and says it again as a character (chipmunk,
/// squawky parrot, singing robot, canyon echo, little choir, underwater:
/// `VoiceDSP`), never the same twice in a row, through the
/// shared `ToyAudio` engine. The view reads `state`, `level` (the voice coming
/// in) and `mouth` (the voice going out).
///
/// While the parrot talks, and until its echoes are over, the detector is not
/// fed: the parrot never answers itself.
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

    private let audio: ToyAudio
    private var voiceNodes: (voice: RenderNode<VoiceDSP>, out: Fader)?
    /// The phrase goes in the slot the voice is not reading.
    private var nextSlot = 0
    private var lastCharacter: VoiceDSP.Character?
    private var tapped = false
    private let tape = Tape()
    private var detector = RepeatDetector()
    private var loop: Task<Void, Never>?
    private var last: AVAudioPCMBuffer?
    private var voiceFormat: AVAudioFormat?
    /// Set while asking for the microphone: the permission alert makes the
    /// scene inactive then active again, which calls `start()` a second time.
    private var starting = false
    /// False once the toy is gone: a permission answered after leaving must not open the microphone.
    private var wanted = false
    private var lastLevelLog = 0.0
    private let traceEvery = ProcessInfo.processInfo.environment["KIDZY_PARROT_TRACE"] == nil ? 2.0 : 0.25
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.screenclub", category: "parrot")
    #if DEBUG
    /// `KIDZY_PARROT_VOICE=robot` (any `VoiceDSP.Character` name): always that voice.
    private let forcedCharacter = ProcessInfo.processInfo.environment["KIDZY_PARROT_VOICE"].flatMap { name in
        VoiceDSP.Character.allCases.first { String(describing: $0) == name }
    }
    #endif

    /// A character by its weight (the chipmunk most), never the last one again.
    static func pick(after last: VoiceDSP.Character?) -> VoiceDSP.Character {
        let options = VoiceDSP.Character.allCases.filter { $0 != last }
        var roll = Double.random(in: 0..<options.reduce(0) { $0 + VoiceDSP.Settings.weight($1) })
        for c in options {
            roll -= VoiceDSP.Settings.weight(c)
            if roll < 0 { return c }
        }
        return options[0]
    }

    init(audio: ToyAudio = .shared) {
        self.audio = audio
    }

    func start() async {
        wanted = true
        guard state == .idle, !starting else { return }
        starting = true
        defer { starting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            log.notice("microphone refused")
            return
        }
        guard wanted, state == .idle, !tapped else { return }
        let nodes = voiceNodes ?? {
            let format = AudioKit.Settings.audioFormat
            let voice = RenderNode(VoiceDSP(sampleRate: Float(format.sampleRate)), format: format)
            return (voice, Fader(voice, gain: 1))
        }()
        voiceNodes = nodes
        nodes.out.gain = 1
        audio.attach(nodes.out)
        audio.setRoom(.small)
        audio.acquire(mic: true)   // play-and-record, the engine running, before the tap
        let input = audio.engine.avEngine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard audio.isRunning, inFormat.sampleRate > 0, inFormat.channelCount > 0, let format = AVAudioFormat(standardFormatWithSampleRate: inFormat.sampleRate, channels: 1) else {
            log.notice("no microphone")
            audio.detach(nodes.out)
            audio.release(mic: true)
            return
        }
        tape.reset(sampleRate: inFormat.sampleRate)
        voiceFormat = format
        input.removeTap(onBus: 0)   // never two taps on one bus: that is an exception, not an error
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat, block: Self.tapBlock(for: tape))
        tapped = true
        detector = RepeatDetector()
        state = .listening
        log.notice("listening at \(inFormat.sampleRate) Hz")
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        wanted = false
        loop?.cancel()
        loop = nil
        if tapped {
            tapped = false
            audio.engine.avEngine.inputNode.removeTap(onBus: 0)
            if let nodes = voiceNodes {
                nodes.voice.dsp.queue.send(.init(kind: .stop))
                audio.detach(nodes.out)
            }
            audio.release(mic: true)
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
        guard tapped, audio.isRunning, state != .repeating, let nodes = voiceNodes, let samples = buffer.floatChannelData?[0] else { return }
        state = .repeating
        var character = Self.pick(after: lastCharacter)
        #if DEBUG
        if let forcedCharacter { character = forcedCharacter }
        #endif
        lastCharacter = character
        let settings = VoiceDSP.Settings.of(character)
        let prefix = VoiceDSP.Settings.prefix(character, roll: Double.random(in: 0..<1))
        log.notice("repeat: \(String(describing: character), privacy: .public)")
        onEvent?("repeat")
        let window = 0.04
        let envelope = Self.envelope(of: buffer, window: window)
        // the slot the voice is not reading: the last phrase, its echoes included, is over
        let slot = nextSlot
        nextSlot = 1 - slot
        let count = nodes.voice.dsp.load(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)), into: slot)
        audio.setRoom(character == .choir ? .hall : .small)
        nodes.voice.dsp.queue.send(.init(kind: .play, slot: Int32(slot), length: Int32(count), phraseRate: Float(buffer.format.sampleRate), character: Int32(character.rawValue), prefix: prefix, seed: UInt32.random(in: 1...UInt32.max)))
        let lead = VoiceDSP.duration(of: prefix)
        let seconds = Double(count) / buffer.format.sampleRate / settings.rate
        let started = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > lead + seconds + 0.15 { break }
            // the beak opens a little for the "hmm?" or the chirp, then follows the words
            let target = elapsed < lead ? (prefix == .hmm ? 0.15 : 0.4) : {
                let i = Int((elapsed - lead) * settings.rate / window)
                return i < envelope.count ? envelope[i] : 0
            }()
            mouth += (target - mouth) * 0.6
            try? await Task.sleep(for: .milliseconds(33))
        }
        mouth = 0
        level = 0
        // the echoes and the choir's tail must be over before the parrot listens again
        try? await Task.sleep(for: .seconds(settings.tail + 0.35))
        audio.setRoom(.small)
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
