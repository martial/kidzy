@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import XCTest
@testable import SketchesForKids

/// The parrot's voices, the guitar's body and the animals' little sounds,
/// rendered offline through the real engine: never NaN, never above full
/// scale, they sound, and they end.
@MainActor
final class VoicesAudioTests: XCTestCase {
    /// A voice-like phrase: a 180 Hz buzz with harmonics, five syllables a second, the fades ParrotEar adds.
    private static func phrase(seconds: Double = 1.2, sampleRate: Double = 48000) -> [Float] {
        let n = Int(seconds * sampleRate)
        return (0..<n).map { i in
            let t = Float(Double(i) / sampleRate)
            let syllable = max(0, sin(.pi * t * 5))
            var v: Float = 0
            for h in 1...8 { v += sin(2 * .pi * 180 * Float(h) * t) / Float(h) }
            let fade = min(1, Float(i) / 720, Float(n - 1 - i) / 720)
            return 0.45 * v * syllable * fade
        }
    }

    func testEveryParrotCharacterSpeaksAndEnds() throws {
        let phrase = Self.phrase()
        for character in VoiceDSP.Character.allCases {
            let audio = ToyAudio(offline: true)
            let format = AudioKit.Settings.audioFormat
            let voice = RenderNode(VoiceDSP(sampleRate: Float(format.sampleRate)), format: format)
            let out = Fader(voice, gain: 1)
            audio.attach(out)
            let count = phrase.withUnsafeBufferPointer { voice.dsp.load($0, into: 1) }
            XCTAssertEqual(count, phrase.count)
            let settings = VoiceDSP.Settings.of(character)
            let prefix = VoiceDSP.Settings.prefix(character, roll: 0)
            let speech = VoiceDSP.duration(of: prefix) + Double(count) / 48000 / settings.rate
            let rendered = audio.engine.startTest(totalDuration: speech + settings.tail + 1)
            voice.dsp.queue.send(.init(kind: .play, slot: 1, length: Int32(count), phraseRate: 48000, character: Int32(character.rawValue), prefix: prefix, seed: 42))
            rendered.append(audio.engine.render(duration: speech))
            let speaking = ToyAudioTests.stats(rendered)
            rendered.append(audio.engine.render(duration: settings.tail + 1))
            let all = ToyAudioTests.stats(rendered)
            let end = ToyAudioTests.stats(rendered, from: Int(rendered.frameLength) - Int(format.sampleRate * 0.25))
            print("audio parrot \(character): peak \(all.peak) rms \(speaking.rms) end \(end.peak)")
            XCTAssertTrue(all.finite, "\(character)")
            XCTAssertLessThanOrEqual(all.peak, 1.0, "\(character) stays under the ceiling")
            XCTAssertGreaterThan(speaking.rms, 0.02, "\(character) speaks")
            XCTAssertLessThan(end.peak, 0.01, "\(character) ends, echoes included, within its tail")
        }
    }

    /// The parrot never uses the same voice twice in a row, and every voice comes up.
    func testTheParrotChangesVoiceEveryTime() {
        var last: VoiceDSP.Character?
        var seen = Set<VoiceDSP.Character>()
        for _ in 0..<400 {
            let next = ParrotEar.pick(after: last)
            XCTAssertNotEqual(next, last)
            seen.insert(next)
            last = next
        }
        XCTAssertEqual(seen.count, VoiceDSP.Character.allCases.count)
    }

    /// A new phrase played while the last one still echoes: no NaN, no jump above the ceiling.
    func testAPhraseCutByTheNextOne() throws {
        let audio = ToyAudio(offline: true)
        let format = AudioKit.Settings.audioFormat
        let voice = RenderNode(VoiceDSP(sampleRate: Float(format.sampleRate)), format: format)
        audio.attach(Fader(voice, gain: 1))
        let phrase = Self.phrase()
        let count = phrase.withUnsafeBufferPointer { voice.dsp.load($0, into: 0) }
        _ = phrase.withUnsafeBufferPointer { voice.dsp.load($0, into: 1) }
        let rendered = audio.engine.startTest(totalDuration: 6)
        voice.dsp.queue.send(.init(kind: .play, slot: 0, length: Int32(count), phraseRate: 48000, character: Int32(VoiceDSP.Character.canyon.rawValue), prefix: .none, seed: 1))
        rendered.append(audio.engine.render(duration: 1.0))
        voice.dsp.queue.send(.init(kind: .play, slot: 1, length: Int32(count), phraseRate: 48000, character: Int32(VoiceDSP.Character.choir.rawValue), prefix: .none, seed: 2))
        rendered.append(audio.engine.render(duration: 1.0))
        voice.dsp.queue.send(.init(kind: .stop))
        rendered.append(audio.engine.render(duration: 0.5))
        let s = ToyAudioTests.stats(rendered)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0)
        let end = ToyAudioTests.stats(rendered, from: Int(rendered.frameLength) - 4410)
        XCTAssertLessThan(end.peak, 0.01, "stop silences the voice and its echoes")
    }

    // MARK: - guitar

    func testGuitarFullStrumsStayUnderTheCeilingAndRingOut() throws {
        let audio = ToyAudio(offline: true)
        let guitar = GuitarSynth(audio: audio)
        guitar.start()
        // 16 bars of 0.35 s, then 7 s to ring out
        let out = audio.engine.startTest(totalDuration: 14)
        let chords = Chord.palette
        for bar in 0..<16 {
            let chord = chords[bar % chords.count]
            for i in 0..<6 {
                if let midi = chord.notes[i] { guitar.pluck(string: i, frequency: Chord.frequency(midi: midi), velocity: 1) }
                out.append(audio.engine.render(duration: 0.025))
            }
            guitar.melody(midi: 67 + bar % 5, velocity: 1)
            out.append(audio.engine.render(duration: 0.2))
        }
        let playing = ToyAudioTests.stats(out)
        out.append(audio.engine.render(duration: 7))
        let s = ToyAudioTests.stats(out)
        let end = ToyAudioTests.stats(out, from: Int(out.frameLength) - 4410)
        print("audio guitar: peak \(s.peak) rms \(playing.rms) end \(end.peak)")
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0, "sixteen full strums and the room stay under the ceiling")
        XCTAssertGreaterThan(playing.rms, 0.03, "it plays")
        XCTAssertLessThan(end.peak, 0.02, "the strings ring out")
    }

    /// The guitar is the recorded nylon guitar: every note is in the bundle, and the
    /// nearest recording is retuned by at most a semitone, exactly.
    func testTheGuitarIsRecordedAndInTune() {
        let samples = GuitarSamples.shared
        XCTAssertEqual(samples.lengths.count, 27)
        XCTAssertTrue(samples.lengths.allSatisfy { $0 > 44100 }, "every note is there and lasts over a second")
        for midi in 40...91 {
            let f = Chord.frequency(midi: midi)
            let (index, rate) = samples.nearest(f, outputRate: samples.sampleRate)
            let recorded = GuitarSamples.notes[index]
            XCTAssertLessThanOrEqual(abs(midi - recorded), 1, "MIDI \(midi) plays a note at most a semitone away")
            XCTAssertEqual(rate, pow(2, Double(midi - recorded) / 12), accuracy: 1e-9)
        }
    }

    /// What the guitar plays is in tune: notes taken straight from a recording and notes
    /// retuned a semitone from their neighbour, measured on the sampler's output.
    func testTheGuitarPlaysInTune() throws {
        for midi in [40, 47, 55, 62, 64, 71] {
            let sr: Float = 48000
            let dsp = NylonDSP(sampleRate: sr)
            let f = Chord.frequency(midi: midi)
            dsp.queue.send(.init(kind: .pluck, voice: 0, frequency: Float(f), velocity: 0.8, pan: 0))
            let n = Int(sr)
            var left = [Float](repeating: 0, count: n), right = [Float](repeating: 0, count: n)
            var at = 0
            while at < n {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        let abl = AudioBufferList.allocate(maximumBuffers: 2)
                        defer { free(abl.unsafeMutablePointer) }
                        abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 2048, mData: l.baseAddress! + at)
                        abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 2048, mData: r.baseAddress! + at)
                        dsp.render(frameCount: 512, buffers: abl)
                    }
                }
                at += 512
            }
            // squared-difference minimum near the expected period, from 0.3 s, refined by a parabola
            let x = zip(left, right).map { $0 + $1 }
            let start = Int(0.3 * sr), window = Int(0.3 * sr)
            let period = Double(sr) / f
            let lo = Int(period * 0.6), hi = Int(period * 1.4) + 2
            let values: [Double] = (lo...hi).map { lag in
                var s = 0.0
                for i in 0..<window { let v = Double(x[start + i] - x[start + i + lag]); s += v * v }
                return s
            }
            let k = values.indices.min(by: { values[$0] < values[$1] })!
            var lag = Double(lo + k)
            if k > 0, k < values.count - 1 { lag += 0.5 * (values[k - 1] - values[k + 1]) / (values[k - 1] - 2 * values[k] + values[k + 1]) }
            let cents = 1200 * log2(Double(sr) / lag / f)
            print("audio guitar tuning: MIDI \(midi) \(String(format: "%+.1f", cents)) cents")
            // the sampler adds up to ±4 cents of human detune on purpose
            XCTAssertLessThan(abs(cents), 12, "MIDI \(midi) is in tune")
        }
    }

    // MARK: - animals

    func testAnimalWhooshAndBoing() throws {
        let audio = ToyAudio(offline: true)
        let format = AudioKit.Settings.audioFormat
        let fx = RenderNode(AnimalFX(sampleRate: Float(format.sampleRate)), format: format)
        audio.attach(Fader(fx, gain: 1))
        let out = audio.engine.startTest(totalDuration: 3)
        fx.dsp.queue.send(.init(kind: .whoosh, direction: -1, seed: 3))
        out.append(audio.engine.render(duration: 0.6))
        fx.dsp.queue.send(.init(kind: .boing, seed: 4))
        out.append(audio.engine.render(duration: 0.3))
        fx.dsp.queue.send(.init(kind: .whoosh, direction: 1, seed: 5))
        fx.dsp.queue.send(.init(kind: .boing, seed: 6))
        out.append(audio.engine.render(duration: 1.2))
        let s = ToyAudioTests.stats(out)
        let end = ToyAudioTests.stats(out, from: Int(out.frameLength) - 4410)
        print("audio animal fx: peak \(s.peak) rms \(s.rms)")
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0)
        XCTAssertGreaterThan(s.rms, 0.005, "they sound")
        XCTAssertLessThan(end.peak, 0.005, "and end")
    }
}
