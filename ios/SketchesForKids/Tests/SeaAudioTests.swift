@preconcurrency import AudioKit
import AVFoundation
import XCTest
@testable import SketchesForKids

/// « La mer », rendered offline through the real engine, driven by the real
/// simulation exactly as SeaToy drives it: never NaN, never above full scale,
/// alive but quiet when calm, a rush when it sloshes, silent once stopped.
@MainActor
final class SeaAudioTests: XCTestCase {
    @MainActor
    private struct Scene {
        let audio = ToyAudio(offline: true)
        let sound: SeaSound
        var sea = SeaSimulation(columns: 96, width: 1100)
        var boat = Boat(x: 400)
        var ears = SeaAcoustics()

        init() { sound = SeaSound(audio: audio) }

        /// One frame of the toy: simulation, acoustics, sound, then 1/60 s of audio.
        mutating func frame(_ out: AVAudioPCMBuffer) {
            sea.step(dt: 1.0 / 60)
            boat.step(dt: 1.0 / 60, in: &sea)
            if boat.bumped { sound.knock(x: boat.x / sea.width, strength: 0.8) }
            for hit in ears.listen(to: sea, boatX: boat.x) { sound.hit(hit) }
            sound.water(ears.wash)
            out.append(audio.engine.render(duration: 1.0 / 60))
        }

        mutating func run(_ seconds: Double, _ out: AVAudioPCMBuffer) {
            for _ in 0..<Int(seconds * 60) { frame(out) }
        }
    }

    private func stats(_ b: AVAudioPCMBuffer, from start: Int = 0, to end: Int? = nil) -> ToyAudioTests.Stats {
        ToyAudioTests.stats(b, from: start, to: end)
    }

    func testCalmSeaIsAliveButQuiet() throws {
        var scene = Scene()
        scene.sound.start()
        let out = scene.audio.engine.startTest(totalDuration: 6)
        scene.run(6, out)
        let s = stats(out, from: Int(out.format.sampleRate))
        print("audio sea calm: peak \(s.peak) rms \(s.rms)")
        XCTAssertTrue(s.finite)
        XCTAssertGreaterThan(s.rms, 0.0005, "a calm sea still breathes")
        XCTAssertLessThan(s.rms, 0.03, "but quietly")
    }

    func testSloshTapsAndBoatStayUnderTheCeiling() throws {
        var scene = Scene()
        scene.sound.start()
        let out = scene.audio.engine.startTest(totalDuration: 16)
        scene.run(1, out)
        let calm = stats(out)
        // full tilts one way and the other
        for tilt in [1.0, -1.0, 1.0, 0] {
            scene.sea.tiltTarget = tilt
            scene.run(1.2, out)
        }
        let sloshEnd = Int(out.frameLength)
        let slosh = stats(out, from: Int(out.format.sampleRate))
        // pokes and their droplets
        for k in 0..<4 {
            scene.sea.splash(atX: 300 + 150 * Double(k), strength: 9)
            scene.sound.poke(x: 0.3 + 0.15 * Double(k))
            for d in 0..<10 {
                scene.frame(out)
                if d % 2 == 0 { scene.sound.droplet(x: Double(d) / 10) }
            }
        }
        // the boat: dragged with its motor, then shoved into the side
        scene.boat.grab()
        for step in 0..<120 {
            let x = 400 + 300 * sin(Double(step) / 20)
            scene.boat.drag(toX: x, width: 1100)
            scene.sound.motor(x: x / 1100, speed: Double(step % 60) / 60)
            scene.frame(out)
        }
        scene.boat.release(velocity: 400)
        scene.sound.motorOff()
        scene.run(2, out)
        let s = stats(out)
        print("audio sea: peak \(s.peak) rms \(s.rms); calm rms \(calm.rms), slosh rms \(slosh.rms)")
        XCTAssertTrue(s.finite)
        XCTAssertLessThanOrEqual(s.peak, 1.0, "slaps, pokes, the motor and the knock never clip")
        XCTAssertGreaterThan(slosh.rms, calm.rms * 3, "a slosh is a rush, the calm a whisper")
        XCTAssertGreaterThan(Int(out.frameLength), sloshEnd)
    }

    /// What stop() sends before the engine unplugs the sea: everything fades out,
    /// the calm bed included, and nothing rings on.
    func testSilenceFadesTheWholeSeaOut() throws {
        let dsp = SeaDSP(sampleRate: 44100)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let total = 44100 * 3
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        buffer.frameLength = AVAudioFrameCount(total)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        var at = 0
        func render(_ seconds: Double) {
            for _ in 0..<Int(seconds * 44100 / 512) {
                let abl = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(abl.unsafeMutablePointer) }
                abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(512 * 4), mData: channels[0] + at)
                abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(512 * 4), mData: channels[1] + at)
                dsp.render(frameCount: 512, buffers: abl)
                at += 512
            }
        }
        dsp.queue.send(.init(kind: .water, a: 1))
        dsp.queue.send(.init(kind: .motor, a: 1, pan: 0))
        dsp.queue.send(.init(kind: .slap, a: 1, pan: -0.7))
        render(1)
        let loud = stats(buffer, from: 0, to: at)
        dsp.queue.send(.init(kind: .silence))
        render(1.5)
        let tail = stats(buffer, from: at - 4410, to: at)
        print("audio sea: loud rms \(loud.rms), after silence peak \(tail.peak)")
        XCTAssertTrue(loud.finite && tail.finite)
        XCTAssertGreaterThan(loud.rms, 0.01, "a full sea with its motor sounds")
        XCTAssertLessThan(tail.peak, 0.003, "and silence fades all of it out")
    }
}
