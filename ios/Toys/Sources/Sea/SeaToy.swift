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
    var size: CGSize              // the scene (a square larger than the screen in toy mode)
    var screen: CGSize = .zero    // the view
    var restFraction: Double
    var lastDate: Date?
    var touch: Touch = .none
    var sensorAvailable = true
    var lastActivity = Date()
    var lastTilt = 0.0
    var onSplash: (() -> Void)?
    /// The recorded sounds that are not water (the night's chime, the sun's giggle).
    var onSound: ((String) -> Void)?
    /// The water, the boat's motor and knocks (nil: a silent sea).
    var sound: SeaSound?
    private var acoustics = SeaAcoustics()
    private var lastDragX = 0.0
    private var lastDragTime = Date()

    // The sun: draggable across the sky; low sun = sunset, below the sea = night.
    var sun: CGPoint
    static let sunRadius = 38.0

    // Orientation: the scene turns in quarter turns to keep the sea sensible
    // whichever edge of the phone is down; the rest of the tilt sloshes the water.
    var orientation = 0.0        // target, a multiple of π/2
    var sceneAngle = 0.0         // current, eased
    var gravityStrength = 0.0
    var giggleStart = -10.0
    var wasNight = false

    /// The part of the scene on screen, in scene coordinates: the screen's
    /// rectangle for the current orientation, centred on the scene. The sun,
    /// the clouds, the water level and the boat's lane all live in it.
    var view: CGRect

    init(size: CGSize, screen: CGSize, columns: Int, restFraction: Double) {
        self.size = size
        self.screen = screen
        self.restFraction = restFraction
        sea = SeaSimulation(columns: columns, width: size.width)
        let view = Self.viewRect(for: 0, size: size, screen: screen)
        self.view = view
        boat = Boat(x: view.minX + view.width * 0.4)
        boat.lane = view.minX...view.maxX
        sun = CGPoint(x: view.maxX - 76, y: view.minY + min(118, view.height * restFraction * 0.35))
    }

    static func viewRect(for orientation: Double, size: CGSize, screen: CGSize) -> CGRect {
        let quarter = Int((orientation / (.pi / 2)).rounded())
        let swapped = quarter % 2 != 0
        let w = swapped ? screen.height : screen.width
        let h = swapped ? screen.width : screen.height
        return CGRect(x: size.width / 2 - w / 2, y: size.height / 2 - h / 2, width: w, height: h)
    }

    /// 1 = full day, 0 = the sun touches the horizon; measured against the sky on screen.
    var daylight: Double { min(1, max(0, (restY - sun.y) / ((restY - view.minY) * 0.65))) }
    /// 0 above the horizon, 1 when the sun is well below it.
    var night: Double { min(1, max(0, (sun.y - restY + 10) / 140)) }
    /// 0...1 while the sun giggles (0.6 s).
    var giggle: Double {
        let p = (sea.time - giggleStart) / 0.6
        return p >= 0 && p <= 1 ? p : 0
    }

    var isNearSun: (CGPoint) -> Bool { { p in hypot(p.x - self.sun.x, p.y - self.sun.y) < Self.sunRadius + 24 } }

    var restY: Double { view.minY + view.height * restFraction }

    /// A scene x as a fraction across the screen (0 left, 1 right), for panning.
    func screenX(_ x: Double) -> Double { (x - view.minX) / view.width }

    func surfaceY(at x: Double) -> Double { restY - sea.height(at: x) }

    var boatCenter: CGPoint { CGPoint(x: boat.x, y: restY - boat.y - 20) }

    func setTilt(_ t: Double) {
        if abs(t - lastTilt) > 0.08 {
            lastActivity = Date()
            lastTilt = t
        }
        sea.tiltTarget = t
    }

    /// Gravity in the screen plane: which edge is down picks the orientation,
    /// the remainder (within ±45°) is the slosh.
    func setGravity(gx: Double, gy: Double) {
        let strength = min(1, hypot(gx, gy) / 0.35)
        gravityStrength = strength
        guard strength > 0.35 else {
            setTilt(0)
            return
        }
        let angle = atan2(gx, -gy)                       // 0 upright, +π/2 right edge down, ±π upside down
        let snapped = (angle / (.pi / 2)).rounded() * (.pi / 2)
        var residual = angle - snapped
        if residual > .pi { residual -= 2 * .pi }
        if residual < -.pi { residual += 2 * .pi }
        orientation = snapped
        let next = Self.viewRect(for: snapped, size: size, screen: screen)
        if next != view { reframe(to: next) }
        setTilt(min(1, max(-1, residual / (.pi / 4))) * strength)
    }

    /// The screen turned a quarter: keep the sun, the boat and the water level
    /// where they were relative to the screen.
    private func reframe(to next: CGRect) {
        let old = view, oldRest = restY
        let sunX = (sun.x - old.minX) / old.width
        let boatX = (boat.x - old.minX) / old.width
        let skyFraction = (oldRest - sun.y) / (oldRest - old.minY)
        let depth = sun.y - oldRest
        view = next
        sun.x = next.minX + sunX * next.width
        sun.y = skyFraction > 0 ? max(next.minY + 70, restY - skyFraction * (restY - next.minY)) : restY + depth
        boat.x = next.minX + boatX * next.width
        boat.lane = next.minX...next.maxX
    }

    /// The scene's rotation on screen. SwiftUI turns clockwise for a positive
    /// angle while the gravity angle grows counter-clockwise, hence the sign.
    var drawAngle: Double { -sceneAngle }

    /// Screen point → scene point, undoing the scene rotation about the screen centre.
    func scenePoint(_ p: CGPoint, screen: CGSize) -> CGPoint {
        let cx = screen.width / 2, cy = screen.height / 2
        let dx = p.x - cx, dy = p.y - cy
        let c = cos(sceneAngle), s = sin(sceneAngle)
        return CGPoint(x: dx * c - dy * s + size.width / 2, y: dx * s + dy * c + size.height / 2)
    }

    func advance(to date: Date) {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        var delta = orientation - sceneAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        sceneAngle += delta * min(1, dt * 5)
        sea.step(dt: dt)
        boat.step(dt: dt, in: &sea)
        if let sound {
            // the boat bounced: its speed before the bounce sets the knock
            if boat.bumped { sound.knock(x: screenX(boat.x), strength: min(1, abs(boat.vx) / Boat.bounce / 300 + 0.3)) }
            for hit in acoustics.listen(to: sea, boatX: boat.x) {
                if case .hull = hit.place {
                    sound.hit(SeaAcoustics.Hit(place: .hull(screenX(boat.x)), strength: hit.strength))
                } else {
                    sound.hit(hit)
                }
            }
            sound.water(acoustics.wash)
        }
        // a margin each way, so a sun near the horizon rings once, not on every wobble
        let nightNow = wasNight ? night > 0.4 : night > 0.6
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
            if now - d.born > 0.15, d.y > surfaceY(at: d.x) {
                sound?.droplet(x: screenX(d.x))
                return nil
            }
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
                sound?.motor(x: screenX(boat.x), speed: 0)
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
            sound?.motor(x: screenX(boat.x), speed: speed / 900)
        case .sun(let start, _):
            if hypot(p.x - start.x, p.y - start.y) > 12 {
                sun = CGPoint(x: min(view.maxX - 40, max(view.minX + 40, p.x)), y: min(min(restY + 150, view.maxY - 40), max(view.minY + 70, p.y)))
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
            sound?.motorOff()
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
        sound?.poke(x: screenX(p.x))
    }
}
