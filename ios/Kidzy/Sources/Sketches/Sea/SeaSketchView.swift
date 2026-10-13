import SwiftUI

/// « La mer »: water that sloshes with the tilt, a boat that bobs and slides,
/// a splash on tap. In background mode it is quieter and ignores touches.
struct SeaSketchView: View {
    enum Mode {
        case toy
        case background
    }

    var mode: Mode = .toy
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var box = SeaToyBox()
    @State private var sensor = TiltSensor()
    @State private var sounds = SoundBank()
    @State private var synth = FingerSynth()

    var body: some View {
        TimelineView(.animation(paused: phase != .active)) { ctx in
            Canvas(rendersAsynchronously: false) { gc, size in
                let toy = box.toy(for: size, mode: mode, sensorAvailable: sensor.isAvailable, sounds: mode == .toy ? sounds : nil, synth: mode == .toy ? synth : nil)
                toy.advance(to: ctx.date)
                if mode == .toy {
                    // the scene is a square larger than the screen, rotated to follow the phone
                    gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sky))
                    gc.translateBy(x: size.width / 2, y: size.height / 2)
                    gc.rotate(by: .radians(toy.drawAngle))
                    gc.translateBy(x: -toy.size.width / 2, y: -toy.size.height / 2)
                }
                SeaPainter.draw(toy: toy, in: &gc, size: toy.size, mode: mode)
            }
        }
        .ignoresSafeArea()
        .gesture(drag, including: mode == .toy ? .all : .none)
        .onAppear {
            startSensor()
            if mode == .toy {
                sounds.load()
                synth.start()
            }
        }
        .onDisappear {
            sensor.stop()
            synth.stop()
            sounds.unload()
        }
        .onChange(of: phase) { _, p in
            if p == .active { startSensor() } else { sensor.stop() }
        }
        .task {
            guard mode == .toy else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if let toy = box.current, Date().timeIntervalSince(toy.lastActivity) > 300 { model.exitSketch() }
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard let toy = box.current else { return }
                toy.dragChanged(location: toy.scenePoint(v.location, screen: toy.screen), start: toy.scenePoint(v.startLocation, screen: toy.screen))
            }
            .onEnded { v in
                guard let toy = box.current else { return }
                let along = Double(v.velocity.width) * cos(toy.drawAngle) + Double(v.velocity.height) * sin(toy.drawAngle)
                toy.dragEnded(location: toy.scenePoint(v.location, screen: toy.screen), velocity: along)
            }
    }

    private func startSensor() {
        if mode == .toy {
            sensor.onGravity = { [box] gx, gy in box.current?.setGravity(gx: gx, gy: gy) }
        } else {
            sensor.onTilt = { [box] in box.current?.setTilt($0) }
        }
        sensor.start()
    }
}

/// Holds the toy so the Canvas can create it on its first frame, whatever the
/// order of appear callbacks; it is rebuilt only when the size changes.
@MainActor
final class SeaToyBox {
    private(set) var current: SeaToy?

    func toy(for size: CGSize, mode: SeaSketchView.Mode, sensorAvailable: Bool, sounds: SoundBank?, synth: FingerSynth?) -> SeaToy {
        if let current, abs(current.screen.width - size.width) < 1, abs(current.screen.height - size.height) < 1 {
            return current
        }
        // the toy's scene is a square of the screen's diagonal, so it can turn without gaps
        let diagonal = hypot(max(1, size.width), max(1, size.height))
        let sceneSize = mode == .toy ? CGSize(width: diagonal, height: diagonal) : CGSize(width: max(1, size.width), height: max(1, size.height))
        let screen = CGSize(width: max(1, size.width), height: max(1, size.height))
        let t = SeaToy(size: sceneSize, screen: screen, columns: mode == .toy ? 96 : 40, restFraction: mode == .toy ? 0.57 : 0.7)
        t.sensorAvailable = sensorAvailable
        if mode == .toy {
            t.onSplash = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            t.onSound = { [weak sounds] name in sounds?.play(name, volume: name == "bump" ? 0.6 : 0.9, rate: Double.random(in: 0.92...1.08)) }
            t.onBoatDrag = { [weak synth] x, speed in synth?.update(id: 100, voice: FingerMusic.boatVoice(x: x, speed: speed)) }
            t.onBoatRelease = { [weak synth] in synth?.ended(id: 100) }
        }
        #if DEBUG
        if let sunY = ProcessInfo.processInfo.environment["KIDZY_SUN_Y"].flatMap(Double.init) { t.sun.y = sunY }
        if let g = ProcessInfo.processInfo.environment["KIDZY_GRAVITY"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
            t.setGravity(gx: g[0], gy: g[1])
            t.sceneAngle = t.orientation
        }
        #endif
        current = t
        return t
    }
}

/// Draws one frame of the sea.
enum SeaPainter {
    @MainActor
    static func draw(toy: SeaToy, in gc: inout GraphicsContext, size: CGSize, mode: SeaSketchView.Mode) {
        let w = size.width, h = size.height
        let restY = toy.restY
        let sea = toy.sea
        let day = toy.daylight, night = toy.night
        let sunset = 1 - day
        var deepColor = Theme.oceanDeep
        var lightColor = Theme.oceanLight
        if mode == .toy {
            let top = SeaArt.mix(SeaArt.mix(Theme.sky, Theme.sunsetTop, sunset), Theme.nightTop, night)
            let bottom = SeaArt.mix(SeaArt.mix(.white, Theme.sunsetBottom, sunset), Theme.nightBottom, night)
            let view = toy.view
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: 0, y: view.minY), endPoint: CGPoint(x: 0, y: restY)))
            SeaArt.drawStars(in: &gc, size: size, below: restY, alpha: night)
            SeaArt.drawSun(in: &gc, center: toy.sun, radius: SeaToy.sunRadius, giggle: toy.giggle, warmth: sunset)
            // the clouds cross the part of the sky that is on screen; the sky is shorter sideways
            let t = sea.time
            let span = view.width + 200
            let c1 = view.minX - 100 + (t * 10 + 60).truncatingRemainder(dividingBy: span)
            let c2 = view.minX - 100 + (t * 16 + 300).truncatingRemainder(dividingBy: span)
            let k = min(1, (restY - view.minY) / 480)
            var clouds = gc
            clouds.opacity = 1 - 0.6 * night
            SeaArt.drawCloud(in: &clouds, at: CGPoint(x: c1, y: view.minY + 150 * k))
            SeaArt.drawCloud(in: &clouds, at: CGPoint(x: c2, y: view.minY + 230 * k), scale: 0.7)
            deepColor = SeaArt.mix(SeaArt.mix(Theme.oceanDeep, Theme.oceanSunset, sunset), Theme.oceanNight, night)
            lightColor = SeaArt.mix(Theme.oceanLight, Theme.oceanNightLight, night)
        }

        var surface = Path()
        for i in 0..<sea.columns {
            let p = CGPoint(x: sea.x(of: i), y: restY - sea.heights[i])
            if i == 0 { surface.move(to: p) } else { surface.addLine(to: p) }
        }
        var deep = surface
        deep.addLine(to: CGPoint(x: w, y: h))
        deep.addLine(to: CGPoint(x: 0, y: h))
        deep.closeSubpath()
        gc.fill(deep, with: .color(deepColor))

        if mode == .toy {
            SeaArt.drawBoat(in: &gc, at: CGPoint(x: toy.boat.x, y: restY - toy.boat.y), angle: toy.boat.angle)
        }

        var band = surface
        for i in stride(from: sea.columns - 1, through: 0, by: -1) {
            band.addLine(to: CGPoint(x: sea.x(of: i), y: restY - sea.heights[i] + 26))
        }
        band.closeSubpath()
        gc.fill(band, with: .color(lightColor.opacity(0.7)))
        gc.stroke(surface, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))

        if mode == .background {
            SeaArt.drawBoat(in: &gc, at: CGPoint(x: toy.boat.x, y: restY - toy.boat.y), angle: toy.boat.angle, scale: 0.8)
        }

        var foam = 0
        for i in 0..<sea.columns where sea.isCrest(i) && foam < 24 {
            foam += 1
            let p = CGPoint(x: sea.x(of: i), y: restY - sea.heights[i] - 6)
            let dot = Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            gc.fill(dot, with: .color(.white))
            gc.stroke(dot, with: .color(Theme.ink), lineWidth: 1.5)
        }

        for d in toy.droplets {
            let dot = Path(ellipseIn: CGRect(x: d.x - d.radius, y: d.y - d.radius, width: 2 * d.radius, height: 2 * d.radius))
            gc.fill(dot, with: .color(Theme.oceanLight))
            gc.stroke(dot, with: .color(Theme.ink), lineWidth: 1.5)
        }
    }
}
