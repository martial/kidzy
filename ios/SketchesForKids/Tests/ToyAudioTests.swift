@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import XCTest
@testable import SketchesForKids

/// The toys' sound, rendered offline through the real engine (AudioKit manual
/// rendering): never NaN, never above full scale, and no clicks.
///
/// A click is a jump in the waveform's slope: the second difference
/// |x[n] - 2x[n-1] + x[n-2]|. A smooth tone keeps it tiny; a cut or a jump makes
/// it spike (`testTheClickDetectorSeesAClick` proves the measure catches one).
@MainActor
final class ToyAudioTests: XCTestCase {
    struct Stats {
        var finite = true
        var peak: Float = 0
        var curvature: Float = 0
        var rms: Float = 0
    }

    static func stats(_ buffer: AVAudioPCMBuffer, from start: Int = 0, to end: Int? = nil) -> Stats {
        var s = Stats()
        guard let data = buffer.floatChannelData else { return s }
        let n = end.map { min($0, Int(buffer.frameLength)) } ?? Int(buffer.frameLength)
        var sum: Double = 0
        var count = 0
        for c in 0..<Int(buffer.format.channelCount) {
            let x = data[c]
            for i in max(2, start)..<max(2, n) {
                let v = x[i]
                if !v.isFinite { s.finite = false; continue }
                s.peak = max(s.peak, abs(v))
                s.curvature = max(s.curvature, abs(v - 2 * x[i - 1] + x[i - 2]))
                sum += Double(v * v)
                count += 1
            }
        }
        s.rms = count > 0 ? Float((sum / Double(count)).squareRoot()) : 0
        return s
    }

    private func report(_ name: String, _ s: Stats) {
        print("audio \(name): peak \(s.peak) rms \(s.rms) curvature \(s.curvature) finite \(s.finite)")
    }

    // MARK: - the measure

    func testTheClickDetectorSeesAClick() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        let x = try XCTUnwrap(buffer.floatChannelData?[0])
        // cut a quarter period after a zero crossing, where the tone is at its peak
        for i in 0..<44100 { x[i] = 0.3 * sin(2 * .pi * 440 * Float(i) / 44100) * (i < 22075 ? 1 : 0) }
        let smooth = Self.stats(buffer, to: 22000)
        let cut = Self.stats(buffer, from: 22000, to: 22100)
        XCTAssertLessThan(smooth.curvature, 0.01, "a 440 Hz tone is smooth")
        XCTAssertGreaterThan(cut.curvature, 0.05, "stopping it dead is a click")
    }

    // MARK: - fingers (paint, the boat, the tiles)

    func testFingersPlayful() throws { try fingers(.playful) }
    func testFingersDreamy() throws { try fingers(.dreamy) }

    private func fingers(_ style: FingerSynth.Style) throws {
        let audio = ToyAudio(offline: true)
        let synth = FingerSynth(audio: audio)
        synth.style = style
        synth.start()
        let out = audio.engine.startTest(totalDuration: 10)
        // fourteen fingers for twelve voices: some voices are stolen while sounding
        for finger in 0..<14 {
            synth.began(id: finger, voice: FingerMusic.voice(x: Double(finger) / 14, y: Double(finger % 7) / 7, speed: 300, angle: Double(finger)))
            out.append(audio.engine.render(duration: 0.03))
        }
        for step in 0..<120 {
            for finger in 0..<14 where finger % 2 == step % 2 {
                let t = Double(step) / 120
                synth.update(id: finger, voice: FingerMusic.voice(x: 0.5 + 0.4 * sin(t * 6 + Double(finger)), y: 0.5 + 0.4 * cos(t * 5 + Double(finger)), speed: 200 + 600 * t, angle: t * 9))
            }
            out.append(audio.engine.render(duration: 0.02))
        }
        for finger in 0..<14 {
            synth.ended(id: finger)
            out.append(audio.engine.render(duration: 0.02))
        }
        // the dreamy echo and the hall ring for a few seconds after the last finger
        out.append(audio.engine.render(duration: style == .dreamy ? 4.5 : 1.6))
        let s = Self.stats(out)
        report("fingers \(style)", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0)
        XCTAssertGreaterThan(s.rms, 0.01, "it plays")
        XCTAssertLessThan(s.curvature, 0.05, "no clicks: starts, steals, glides and releases are ramps")
        let tail = Self.stats(out, from: Int(out.frameLength) - 4410)
        XCTAssertLessThan(tail.peak, 0.02, "all released")
    }

    // MARK: - the paint brush

    func testBrushStrokesDabsAndLifts() throws {
        let audio = ToyAudio(offline: true)
        let brush = BrushSynth(audio: audio)
        brush.start()
        let out = audio.engine.startTest(totalDuration: 6)
        // eleven fingers for ten voices: one voice is taken over while it sounds
        for finger in 0..<11 {
            brush.began(id: finger, x: Double(finger) / 10)
            out.append(audio.engine.render(duration: 0.02))
        }
        for step in 0..<90 {
            let t = Double(step) / 90
            for finger in 0..<11 {
                brush.moved(id: finger, x: 0.5 + 0.4 * sin(t * 6 + Double(finger)), speed: 1600 * sin(.pi * t) + 200 * Double(finger % 3))
            }
            out.append(audio.engine.render(duration: 1.0 / 60))
        }
        for finger in 0..<11 { brush.ended(id: finger) }
        out.append(audio.engine.render(duration: 0.6))
        let s = Self.stats(out)
        report("brush", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0, "eleven fast strokes stay under the ceiling")
        XCTAssertGreaterThan(s.rms, 0.005, "it sounds")
        let tail = Self.stats(out, from: Int(out.frameLength) - 4410)
        XCTAssertLessThan(tail.peak, 0.01, "lifting the brushes ends the sound")
    }

    /// A brush that stops moving on the paper goes quiet, as a real one does.
    func testBrushHeldStillIsQuiet() throws {
        let audio = ToyAudio(offline: true)
        let brush = BrushSynth(audio: audio)
        brush.start()
        let out = audio.engine.startTest(totalDuration: 2)
        brush.began(id: 1, x: 0.5)
        for _ in 0..<20 {
            brush.moved(id: 1, x: 0.5, speed: 900)
            out.append(audio.engine.render(duration: 1.0 / 60))
        }
        let moving = Self.stats(out, from: Int(out.frameLength) - 4410)
        let held = Int(out.frameLength)
        out.append(audio.engine.render(duration: 0.6))
        let still = Self.stats(out, from: held + Int(out.format.sampleRate * 0.25))
        report("brush moving", moving)
        report("brush still", still)
        XCTAssertGreaterThan(moving.rms, 0.01, "a moving brush sounds")
        XCTAssertLessThan(still.rms, moving.rms * 0.05, "and a still one is quiet within a quarter second")
    }

    // MARK: - guitar

    func testGuitarStrumsChordsAndMelody() throws {
        let audio = ToyAudio(offline: true)
        let guitar = GuitarSynth(audio: audio)
        guitar.start()
        let out = audio.engine.startTest(totalDuration: 8)
        let chords = Chord.palette
        for bar in 0..<12 {
            let chord = chords[bar % chords.count]
            for i in 0..<6 {
                if let midi = chord.notes[i] {
                    guitar.pluck(string: i, frequency: Chord.frequency(midi: midi), velocity: bar % 3 == 0 ? 1 : 0.6)
                } else {
                    guitar.mute(string: i)
                }
                out.append(audio.engine.render(duration: 0.028))
            }
            if bar % 2 == 1 { guitar.melody(midi: 64 + bar, velocity: 0.75) }
            out.append(audio.engine.render(duration: 0.25))
        }
        out.append(audio.engine.render(duration: 2))
        let s = Self.stats(out)
        report("guitar", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0, "twelve fast full strums stay under the ceiling")
        XCTAssertGreaterThan(s.rms, 0.02, "it plays")
    }

    /// Damping a ringing string (a re-pluck, a muted string, leaving the toy) is a fade, not a cut.
    func testStringsDampWithoutAClick() throws {
        let dsp = StringsDSP(sampleRate: 44100)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let total = 44100
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        buffer.frameLength = AVAudioFrameCount(total)
        dsp.send(.init(kind: .pluck, voice: 0, frequency: 82.4, velocity: 1, pan: 0, t60: 4.6))
        var at = 0
        let channels = try XCTUnwrap(buffer.floatChannelData)
        func render(_ frames: Int) {
            // the DSP writes straight into the test buffer, at the current position
            let abl = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(abl.unsafeMutablePointer) }
            abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: channels[0] + at)
            abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: channels[1] + at)
            dsp.render(frameCount: frames, buffers: abl)
            at += frames
        }
        for _ in 0..<20 { render(512) }          // ~0.23 s ringing
        let dampAt = at
        dsp.send(.init(kind: .damp, voice: 0, time: 0.06))
        for _ in 0..<10 { render(512) }
        let ringing = Self.stats(buffer, from: dampAt - 4410, to: dampAt)
        let damped = Self.stats(buffer, from: dampAt, to: at)
        report("string ringing", ringing)
        report("string damped", damped)
        XCTAssertTrue(ringing.finite && damped.finite)
        XCTAssertGreaterThan(ringing.rms, 0.01, "the low E rings")
        XCTAssertLessThanOrEqual(damped.curvature, ringing.curvature * 1.05, "the damp adds no spike")
        let end = Self.stats(buffer, from: at - 1024, to: at)
        XCTAssertLessThan(end.peak, 0.001, "and it is silent after the damp")
    }

    // MARK: - recorded sounds

    func testSamplesOverlapWithoutCuts() throws {
        let audio = ToyAudio(offline: true)
        let bank = SoundBank(audio: audio)
        bank.load()
        XCTAssertTrue(bank.has("splash"), "the clips are in the app bundle")
        let out = audio.engine.startTest(totalDuration: 4)
        for (k, name) in ["splash", "splash", "splash", "splash", "chime", "bump", "giggle", "plop", "plop"].enumerated() {
            bank.play(name, volume: 1, rate: 0.9 + 0.05 * Double(k % 4))
            out.append(audio.engine.render(duration: 0.06))
        }
        out.append(audio.engine.render(duration: 2.5))
        let s = Self.stats(out)
        report("samples", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0)
        XCTAssertGreaterThan(s.rms, 0.005, "they play")
    }

    // MARK: - the parrot's voice

    func testParrotVoiceThroughTheVarispeed() throws {
        let audio = ToyAudio(offline: true)
        let player = AudioPlayer()
        let speed = VariSpeed(player)
        let voiceOut = Fader(speed, gain: 1)
        audio.attach(voiceOut)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let n = 48000
        let phrase = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)))
        phrase.frameLength = AVAudioFrameCount(n)
        let x = try XCTUnwrap(phrase.floatChannelData?[0])
        // a voice-like phrase: a 180 Hz buzz with harmonics, syllables, the 15 ms fades ParrotEar adds
        for i in 0..<n {
            let t = Float(i) / 48000
            let syllable = max(0, sin(.pi * t * 5))
            var v: Float = 0
            for h in 1...8 { v += sin(2 * .pi * 180 * Float(h) * t) / Float(h) }
            let fade = min(1, Float(i) / 720, Float(n - 1 - i) / 720)
            x[i] = 0.45 * v * syllable * fade
        }
        let out = audio.engine.startTest(totalDuration: 3)
        let fitted = try XCTUnwrap(ParrotEar.fitted(phrase, to: player.playerNode.outputFormat(forBus: 0)), "the phrase fits the player")
        XCTAssertEqual(fitted.format.channelCount, player.playerNode.outputFormat(forBus: 0).channelCount)
        player.load(buffer: fitted)
        speed.rate = ParrotEar.voices[2]
        player.play()
        out.append(audio.engine.render(duration: 1.5))
        let s = Self.stats(out)
        report("parrot", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0)
        XCTAssertGreaterThan(s.rms, 0.01, "the parrot speaks")
        let after = Self.stats(out, from: Int(out.frameLength) - 22050)
        XCTAssertLessThan(after.peak, 0.02, "and stops: 1 s of voice at 1.74× lasts 0.57 s")
    }

    // MARK: - everything at once

    func testEverythingAtOnceStaysUnderTheCeiling() throws {
        let audio = ToyAudio(offline: true)
        let synth = FingerSynth(audio: audio)
        let guitar = GuitarSynth(audio: audio)
        let bank = SoundBank(audio: audio)
        let brush = BrushSynth(audio: audio)
        synth.start()
        guitar.start()
        bank.load()
        brush.start()
        for f in 0..<10 { brush.began(id: f, x: Double(f) / 10) }
        let out = audio.engine.startTest(totalDuration: 4)
        for f in 0..<12 {
            synth.began(id: f, voice: FingerVoice(frequency: 200 + 60 * Double(f), amplitude: 1, pan: 0, vibrato: 0, brightness: 1))
        }
        for round in 0..<6 {
            for i in 0..<6 { guitar.pluck(string: i, frequency: 82.4 * pow(2, Double(i) * 5 / 12), velocity: 1) }
            bank.play(["splash", "bump", "chime"][round % 3], volume: 1)
            for f in 0..<10 { brush.moved(id: f, x: Double(f) / 10, speed: 1600) }
            out.append(audio.engine.render(duration: 0.3))
        }
        out.append(audio.engine.render(duration: 1))
        let s = Self.stats(out)
        report("everything", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0, "twelve loud fingers, full strums and splashes: the limiter holds")
    }
}
