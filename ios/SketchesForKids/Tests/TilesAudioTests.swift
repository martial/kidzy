@preconcurrency import AudioKit
import AVFoundation
import XCTest
@testable import SketchesForKids

/// The shapes' mallets (`MalletDSP`), rendered offline: they ring and die away,
/// hammering stays under the ceiling, and striking a bar that still rings, or
/// stealing a voice, adds no click beyond the hit itself. Measures from `ToyAudioTests`.
@MainActor
final class TilesAudioTests: XCTestCase {
    private typealias Stats = ToyAudioTests.Stats

    private static let instruments: [MalletDSP.Instrument] = [.marimba, .glockenspiel, .kalimba]

    /// Renders straight from the DSP into a stereo buffer, `script` sending commands between blocks.
    private func renderDSP(seconds: Double, rate: Double = 44100, voices: Int = 40, _ script: (MalletDSP, Int) -> Void) throws -> AVAudioPCMBuffer {
        let dsp = MalletDSP(sampleRate: Float(rate), voices: voices)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let total = Int(seconds * rate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        buffer.frameLength = AVAudioFrameCount(total)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        var at = 0
        while at < total {
            script(dsp, at)
            let frames = min(512, total - at)
            let abl = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(abl.unsafeMutablePointer) }
            abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: channels[0] + at)
            abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: channels[1] + at)
            dsp.render(frameCount: frames, buffers: abl)
            at += frames
        }
        return buffer
    }

    private func strike(_ dsp: MalletDSP, key: Int32, _ instrument: MalletDSP.Instrument, hz: Float, velocity: Float = 0.9) {
        dsp.queue.send(.init(kind: .strike, key: key, instrument: instrument, frequency: hz, velocity: velocity, pan: 0))
    }

    private func report(_ name: String, _ s: Stats) {
        print("audio \(name): peak \(s.peak) rms \(s.rms) curvature \(s.curvature) finite \(s.finite)")
    }

    // MARK: -

    func testEachInstrumentRingsAndDiesAway() throws {
        for instrument in Self.instruments {
            for hz: Float in [262, 880] {
                let f = instrument == .glockenspiel ? hz * 2 : hz
                let out = try renderDSP(seconds: 6) { dsp, at in
                    if at == 0 { strike(dsp, key: 1, instrument, hz: f) }
                }
                let s = ToyAudioTests.stats(out)
                let ringing = ToyAudioTests.stats(out, from: 4410, to: 22050)
                let tail = ToyAudioTests.stats(out, from: Int(out.frameLength) - 4410)
                report("\(instrument) \(f) Hz", s)
                XCTAssertTrue(s.finite)
                XCTAssertLessThan(s.peak, 0.9, "\(instrument): one hit is well under full scale")
                XCTAssertGreaterThan(ringing.rms, 0.003, "\(instrument) \(f) Hz rings")
                XCTAssertLessThan(tail.peak, 0.001, "\(instrument) \(f) Hz has died away after 6 s")
            }
        }
    }

    /// A bar that still rings, struck again, gets more energy: the new hit is no sharper than a
    /// fresh one. At 192 kHz, where the band-limited contact noise and buzz are smooth and only
    /// a discontinuity would stand out.
    func testReStrikingARingingBarDoesNotClick() throws {
        let rate = 192_000.0
        func at(_ seconds: Double) -> Int { Int(seconds * rate) }
        for instrument in Self.instruments {
            let fresh = try renderDSP(seconds: 0.3, rate: rate) { dsp, now in
                if now == 0 { strike(dsp, key: 7, instrument, hz: 392) }
            }
            let freshHit = ToyAudioTests.stats(fresh, to: at(0.1))
            // ring for 0.25 s, then strike the same bar four times, 60 ms apart
            let hits = [at(0.25), at(0.31), at(0.37), at(0.43)]
            let again = try renderDSP(seconds: 0.8, rate: rate) { dsp, now in
                if now == 0 || hits.contains(where: { $0 >= now && $0 < now + 512 }) { strike(dsp, key: 7, instrument, hz: 392) }
            }
            let reHits = ToyAudioTests.stats(again, from: at(0.24), to: at(0.55))
            report("\(instrument) fresh hit", freshHit)
            report("\(instrument) re-hits", reHits)
            XCTAssertTrue(reHits.finite)
            // the bar gets louder with each hit, so compare the sharpness relative to the level
            // (a step would be about as sharp as it is loud: a ratio near 1, not ~0.05)
            XCTAssertLessThanOrEqual(reHits.curvature / reHits.peak, freshHit.curvature / freshHit.peak * 1.6, "\(instrument): re-striking a ringing bar adds no click")
        }
    }

    /// The worst a finger can do: swiping over the whole grid, ~43 tiles a second for 2.4 s, hard,
    /// for 40 voices, so ringing notes are taken over. Under the ceiling, and the takeover is
    /// a fade: rendered again with 400 voices (nothing taken over), the difference is only the
    /// taken-over notes' tails (every strike its own bar, so nothing else differs). At 192 kHz
    /// a smooth tail has almost no curvature while a cut keeps a step.
    func testHammeringManyTilesStaysUnderTheCeilingWithoutClicks() throws {
        let notes: [Float] = [262, 294, 330, 392, 440, 523, 587, 659, 784, 880]
        let rate = 192_000.0
        func session(voices: Int) throws -> AVAudioPCMBuffer {
            var rng = SplitMix(seed: 42)
            var nextStrike = 0
            var key: Int32 = 0
            return try renderDSP(seconds: 3.4, rate: rate, voices: voices) { dsp, at in
                guard at < Int(2.4 * rate), at >= nextStrike else { return }
                nextStrike += Int(rate / 43)
                key += 1
                let instrument = Self.instruments[Int(rng.next() % 3)]
                let note = notes[Int(rng.next() % 10)] * (instrument == .glockenspiel ? 2 : 1)
                dsp.queue.send(.init(kind: .strike, key: key, instrument: instrument, frequency: note, velocity: 0.95, pan: Float(Int(rng.next() % 5) - 2) / 2.5))
            }
        }
        let crowded = try session(voices: 40)
        let roomy = try session(voices: 400)
        let s = ToyAudioTests.stats(crowded)
        report("hammering", s)
        XCTAssertTrue(s.finite)
        // ToyAudio's compressor and limiter take it from there (the engine test stays under 1)
        XCTAssertLessThan(s.peak, 2.5, "a finger swiping everything stays within the limiter's easy reach")

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let diff = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: crowded.frameCapacity))
        diff.frameLength = crowded.frameLength
        for c in 0..<2 {
            let a = try XCTUnwrap(crowded.floatChannelData)[c], b = try XCTUnwrap(roomy.floatChannelData)[c], d = try XCTUnwrap(diff.floatChannelData)[c]
            for i in 0..<Int(diff.frameLength) { d[i] = b[i] - a[i] }
        }
        let taken = ToyAudioTests.stats(diff)
        report("hammering, taken-over notes", taken)
        XCTAssertGreaterThan(taken.peak, 0.001, "notes were taken over (the test exercises it)")
        XCTAssertLessThan(taken.curvature, taken.peak * 0.15, "and they fade, no step")
    }

    /// Leaving the toy: everything ringing fades in 12 ms, no cut.
    func testSilenceFadesOut() throws {
        let stopAt = 22050
        let out = try renderDSP(seconds: 1) { dsp, at in
            if at == 0 {
                for (k, instrument) in Self.instruments.enumerated() { strike(dsp, key: Int32(k), instrument, hz: 330 * Float(k + 1)) }
            }
            if at <= stopAt, stopAt < at + 512 { dsp.queue.send(.init(kind: .silence)) }
        }
        let ringing = ToyAudioTests.stats(out, from: stopAt - 4410, to: stopAt - 512)
        let fading = ToyAudioTests.stats(out, from: stopAt - 512, to: stopAt + 2048)
        let after = ToyAudioTests.stats(out, from: stopAt + 4410)
        report("mallets ringing", ringing)
        report("mallets fading", fading)
        XCTAssertGreaterThan(ringing.rms, 0.003)
        XCTAssertLessThanOrEqual(fading.curvature, ringing.curvature * 1.1, "the fade adds no spike")
        XCTAssertLessThan(after.peak, 0.0001, "and then it is silent")
    }

    /// Through the real engine: taps, a swipe and the shuffle's run, under the ceiling, then silence.
    func testTheToyThroughTheEngine() throws {
        let audio = ToyAudio(offline: true)
        let mallets = MalletSynth(audio: audio)
        mallets.start()
        let out = audio.engine.startTest(totalDuration: 9)
        let kinds: [TileKind] = [.arcs, .triangle, .quarter]
        for k in 0..<20 {
            mallets.strike(column: k % 5, row: (k * 7) % 10, kind: kinds[k % 3], columns: 5, rows: 10, velocity: 0.9)
            out.append(audio.engine.render(duration: 0.09))
        }
        for c in 0..<5 {
            mallets.strike(column: c, row: 4, kind: .arcs, columns: 5, rows: 10, velocity: 0.65)
            out.append(audio.engine.render(duration: 0.05))
        }
        mallets.shuffle()
        out.append(audio.engine.render(duration: 1.2))
        let s = ToyAudioTests.stats(out)
        mallets.stop()
        out.append(audio.engine.render(duration: 3.5))
        let tail = ToyAudioTests.stats(out, from: Int(out.frameLength) - 4410)
        report("tiles", s)
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0)
        XCTAssertGreaterThan(s.rms, 0.01, "the shapes play")
        XCTAssertLessThan(tail.peak, 0.01, "and leaving the toy ends the sound")
    }
}
