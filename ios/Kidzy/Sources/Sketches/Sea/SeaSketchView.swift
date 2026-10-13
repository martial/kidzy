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

    var body: some View {
        TimelineView(.animation(paused: phase != .active)) { ctx in
            Canvas(rendersAsynchronously: false) { gc, size in
                let toy = box.toy(for: size, mode: mode, sensorAvailable: sensor.isAvailable)
                toy.advance(to: ctx.date)
                SeaPainter.draw(toy: toy, in: &gc, size: size, mode: mode)
            }
        }
        .ignoresSafeArea()
        .gesture(drag, including: mode == .toy ? .all : .none)
        .onAppear { startSensor() }
        .onDisappear { sensor.stop() }
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
            .onChanged { v in box.current?.dragChanged(location: v.location, start: v.startLocation) }
            .onEnded { v in box.current?.dragEnded(location: v.location, velocity: v.velocity.width) }
    }

    private func startSensor() {
        sensor.onTilt = { [box] in box.current?.setTilt($0) }
        sensor.start()
    }
}

/// Holds the toy so the Canvas can create it on its first frame, whatever the
/// order of appear callbacks; it is rebuilt only when the size changes.
@MainActor
final class SeaToyBox {
    private(set) var current: SeaToy?

    func toy(for size: CGSize, mode: SeaSketchView.Mode, sensorAvailable: Bool) -> SeaToy {
        if let current, abs(current.size.width - size.width) < 1, abs(current.size.height - size.height) < 1 {
            return current
        }
        let t = SeaToy(size: CGSize(width: max(1, size.width), height: max(1, size.height)), columns: mode == .toy ? 80 : 40, restFraction: mode == .toy ? 0.58 : 0.7)
        t.sensorAvailable = sensorAvailable
        if mode == .toy {
            t.onSplash = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
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
        if mode == .toy {
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Theme.sky, .white]), startPoint: .zero, endPoint: CGPoint(x: 0, y: restY)))
            SeaArt.drawSun(in: &gc, center: CGPoint(x: w - 76, y: 118), radius: 38)
            let t = sea.time
            let c1 = (t * 10 + 60).truncatingRemainder(dividingBy: w + 200) - 100
            let c2 = (t * 16 + 300).truncatingRemainder(dividingBy: w + 200) - 100
            SeaArt.drawCloud(in: &gc, at: CGPoint(x: c1, y: 150))
            SeaArt.drawCloud(in: &gc, at: CGPoint(x: c2, y: 230), scale: 0.7)
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
        gc.fill(deep, with: .color(Theme.oceanDeep))

        if mode == .toy {
            SeaArt.drawBoat(in: &gc, at: CGPoint(x: toy.boat.x, y: restY - toy.boat.y), angle: toy.boat.angle)
        }

        var band = surface
        for i in stride(from: sea.columns - 1, through: 0, by: -1) {
            band.addLine(to: CGPoint(x: sea.x(of: i), y: restY - sea.heights[i] + 26))
        }
        band.closeSubpath()
        gc.fill(band, with: .color(Theme.oceanLight.opacity(0.7)))
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
