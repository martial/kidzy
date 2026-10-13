import Foundation

/// Turns a finger's motion into music: pentatonic pitch by height, bent up by
/// speed; pan and timbre by direction; loudness and vibrato by speed.
public struct FingerVoice: Equatable, Sendable {
    public var frequency: Double
    public var amplitude: Double   // 0...1
    public var pan: Double         // -1 left ... 1 right
    public var vibrato: Double     // depth, 0...0.04
    public var brightness: Double  // 0...1, harmonic mix
}

public enum FingerMusic {
    /// C major pentatonic over two octaves, bottom of the screen = low.
    public static let notes: [Int] = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81]

    public static func frequency(midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    /// `x`, `y` in 0...1 (origin top-left), `speed` in points per second,
    /// `angle` the direction of motion in radians (0 = right, π/2 = down).
    public static func voice(x: Double, y: Double, speed: Double, angle: Double) -> FingerVoice {
        let row = min(notes.count - 1, max(0, Int((1 - min(1, max(0, y))) * Double(notes.count))))
        let bend = min(7, log2(1 + max(0, speed) / 300) * 3)
        let freq = frequency(midi: Double(notes[row]) + bend)
        let amp = speed < 5 ? 0 : min(1, 0.15 + speed / 900)
        let pan = min(1, max(-1, cos(angle) * 0.6 + (x - 0.5) * 0.8))
        let vib = min(0.04, speed / 25000)
        let bright = 0.5 + 0.5 * sin(angle)
        return FingerVoice(frequency: freq, amplitude: amp, pan: pan, vibrato: vib, brightness: bright)
    }

    /// The boat being dragged: a low hum, pitched by speed, panned by position.
    public static func boatVoice(x: Double, speed: Double) -> FingerVoice {
        let freq = 110 * pow(2, min(1.6, max(0, speed) / 500))
        let amp = speed < 10 ? 0 : min(0.6, 0.1 + speed / 1200)
        return FingerVoice(frequency: freq, amplitude: amp, pan: min(1, max(-1, (x - 0.5) * 1.6)), vibrato: 0.01, brightness: 0.2)
    }
}
