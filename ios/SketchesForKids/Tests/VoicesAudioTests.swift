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
        print("audio guitar body: peak \(s.peak) rms \(playing.rms) end \(end.peak)")
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0, "sixteen full strums with the body, the open strings and the room stay under the ceiling")
        XCTAssertGreaterThan(playing.rms, 0.03, "it plays")
        XCTAssertLessThan(end.peak, 0.02, "the strings, the body and the open strings ring out")
    }

    /// The body is there: the low mids (the air and top modes) are louder than on the bare strings.
    func testTheBodyWarmsTheStrings() throws {
        func lowMidShare(_ body: Bool) throws -> Float {
            let sr: Float = 48000
            let guitar = GuitarDSP(sampleRate: sr)
            for (s, midi) in [(0, 40), (1, 45), (2, 50), (3, 55), (4, 59), (5, 64)] {
                guitar.strings.send(.init(kind: .pluck, voice: Int32(s * 2), frequency: Float(Chord.frequency(midi: midi)), velocity: 0.8, pan: 0, t60: 3))
            }
            guitar.picks.send(.init(velocity: 0.8, pan: 0))
            let n = 48000
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)))
            buffer.frameLength = AVAudioFrameCount(n)
            let ch = try XCTUnwrap(buffer.floatChannelData)
            var at = 0
            while at < n {
                let abl = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(abl.unsafeMutablePointer) }
                abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 2048, mData: ch[0] + at)
                abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 2048, mData: ch[1] + at)
                if body { guitar.render(frameCount: 512, buffers: abl) } else { guitar.strings.render(frameCount: 512, buffers: abl) }
                at += 512
            }
            // share of energy below 300 Hz: a one-pole low-pass against the whole
            var low: Float = 0, lowEnergy: Float = 0, all: Float = 0
            let k = 1 - expf(-2 * .pi * 300 / sr)
            for i in 0..<n {
                let x = 0.5 * (ch[0][i] + ch[1][i])
                low += (x - low) * k
                lowEnergy += low * low
                all += x * x
            }
            return lowEnergy / max(all, 1e-9)
        }
        let bare = try lowMidShare(false), warm = try lowMidShare(true)
        print("audio guitar low share: bare \(bare) body \(warm)")
        XCTAssertGreaterThan(warm, bare * 1.2, "the body adds warmth")
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
