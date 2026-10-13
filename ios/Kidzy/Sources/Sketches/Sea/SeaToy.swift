import Foundation
import SwiftUI

/// The toy's state: the simulation, the boat, the droplets, the finger.
/// A plain main-actor class so the Canvas can mutate it every frame.
@MainActor
final class SeaToy {
    struct Droplet {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var born: Double
        var radius: Double
    }

    enum Touch {
        case none
        case boat
        case sun(start: CGPoint, date: Date)
        case sky(startX: Double)
        case water(start: CGPoint, date: Date)
    }

    var sea: SeaSimulation
    var boat: Boat
    var droplets: [Droplet] = []
    var size: CGSize
    var restFraction: Double
    var lastDate: Date?
    var touch: Touch = .none
    var sensorAvailable = true
    var lastActivity = Date()
    var lastTilt = 0.0
    var onSplash: (() -> Void)?
    var onSound: ((String) -> Void)?
    /// The boat's hum while dragged: x in 0...1 and speed in pt/s; nil ends it.
    var onBoatDrag: ((Double, Double) -> Void)?
    var onBoatRelease: (() -> Void)?
    private var lastDragX = 0.0
    private var lastDragTime = Date()

    // The sun: draggable across the sky; low sun = sunset, below the sea = night.
    var sun: CGPoint
    static let sunRadius = 38.0
    var giggleStart = -10.0
    var wasNight = false

    init(size: CGSize, columns: Int, restFraction: Double) {
        self.size = size
        self.restFraction = restFraction
        sea = SeaSimulation(columns: columns, width: size.width)
        boat = Boat(x: size.width * 0.4)
        sun = CGPoint(x: size.width - 76, y: 118)
    }

    /// 1 = full day, 0 = the sun touches the horizon.
    var daylight: Double { min(1, max(0, (restY - sun.y) / (restY * 0.55))) }
    /// 0 above the horizon, 1 when the sun is well below it.
    var night: Double { min(1, max(0, (sun.y - restY + 10) / 140)) }
    /// 0...1 while the sun giggles (0.6 s).
    var giggle: Double {
        let p = (sea.time - giggleStart) / 0.6
        return p >= 0 && p <= 1 ? p : 0
    }

    var isNearSun: (CGPoint) -> Bool { { p in hypot(p.x - self.sun.x, p.y - self.sun.y) < Self.sunRadius + 24 } }

    var restY: Double { size.height * restFraction }

    func surfaceY(at x: Double) -> Double { restY - sea.height(at: x) }

    var boatCenter: CGPoint { CGPoint(x: boat.x, y: restY - boat.y - 20) }

    func setTilt(_ t: Double) {
        if abs(t - lastTilt) > 0.08 {
            lastActivity = Date()
            lastTilt = t
        }
        sea.tiltTarget = t
    }

    func advance(to date: Date) {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        sea.step(dt: dt)
        boat.step(dt: dt, in: &sea)
        if boat.bumped { onSound?("bump") }
        let nightNow = night > 0.5
        if nightNow != wasNight {
            wasNight = nightNow
            onSound?("chime")
        }
        guard dt > 0, !droplets.isEmpty else { return }
        let now = sea.time
        droplets = droplets.compactMap { d in
            var d = d
            d.vy += 900 * dt
            d.x += d.vx * dt
            d.y += d.vy * dt
            if now - d.born > 1.5 { return nil }
            if now - d.born > 0.15, d.y > surfaceY(at: d.x) { return nil }
            return d
        }
    }

    // MARK: - touch

    func dragChanged(location p: CGPoint, start: CGPoint) {
        lastActivity = Date()
        switch touch {
        case .none:
            let c = boatCenter
            if hypot(p.x - c.x, p.y - c.y) < Boat.grabRadius {
                boat.grab()
                onSound?("plop")
                lastDragX = p.x
                lastDragTime = Date()
                touch = .boat
            } else if isNearSun(p) {
                touch = .sun(start: start, date: Date())
            } else if !sensorAvailable, p.y < surfaceY(at: p.x) - 40 {
                touch = .sky(startX: p.x)
            } else {
                touch = .water(start: start, date: Date())
            }
        case .boat:
            let now = Date()
            let dt = max(1.0 / 120, now.timeIntervalSince(lastDragTime))
            let speed = abs(p.x - lastDragX) / dt
            lastDragX = p.x
            lastDragTime = now
            boat.drag(toX: p.x, width: size.width)
            onBoatDrag?(boat.x / size.width, speed)
        case .sun(let start, _):
            if hypot(p.x - start.x, p.y - start.y) > 12 {
                sun = CGPoint(x: min(size.width - 40, max(40, p.x)), y: min(restY + 150, max(70, p.y)))
            }
        case .sky(let startX):
            sea.tiltTarget = min(1, max(-1, (p.x - startX) / 120))
        case .water:
            break
        }
    }

    func dragEnded(location p: CGPoint, velocity: Double) {
        switch touch {
        case .boat:
            boat.release(velocity: velocity)
            onBoatRelease?()
        case .sun(let start, let date):
            if hypot(p.x - start.x, p.y - start.y) < 12, Date().timeIntervalSince(date) < 0.4 {
                giggleStart = sea.time
                onSound?("giggle")
            }
        case .sky:
            sea.tiltTarget = 0
        case .water(let start, let date):
            if hypot(p.x - start.x, p.y - start.y) < 12, Date().timeIntervalSince(date) < 0.35, p.y > surfaceY(at: p.x) - 30 {
                splash(at: p)
            }
        case .none:
            break
        }
        touch = .none
    }

    func splash(at p: CGPoint) {
        sea.splash(atX: p.x, strength: 9)
        boat.nudge(awayFrom: p.x)
        let y = surfaceY(at: p.x)
        for _ in 0..<10 {
            droplets.append(Droplet(x: p.x + Double.random(in: -6...6), y: y, vx: Double.random(in: 40...160) * (Bool.random() ? 1 : -1), vy: -Double.random(in: 220...360), born: sea.time, radius: Double.random(in: 3...5)))
        }
        onSplash?()
        onSound?("splash")
    }
}
