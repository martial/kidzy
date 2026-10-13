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

    init(size: CGSize, columns: Int, restFraction: Double) {
        self.size = size
        self.restFraction = restFraction
        sea = SeaSimulation(columns: columns, width: size.width)
        boat = Boat(x: size.width * 0.4)
    }

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
                touch = .boat
            } else if !sensorAvailable, p.y < surfaceY(at: p.x) - 40 {
                touch = .sky(startX: p.x)
            } else {
                touch = .water(start: start, date: Date())
            }
        case .boat:
            boat.drag(toX: p.x, width: size.width)
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
    }
}
