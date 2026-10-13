import SwiftUI

/// « Formes »: a grid of geometric stickers. Tap one: a quarter turn with a
/// bounce and a note. Swipe: every tile under the finger turns. Bump the
/// table: everything shuffles.
struct TilesSketchView: View {
    @Environment(\.scenePhase) private var phase
    @State private var box = TilesBox()
    @State private var synth = FingerSynth()
    @State private var shake = ShakeSensor()
    @State private var sounds = SoundBank()

    static let colors: [Color] = [Theme.coral, Color(hex: "FFA62B"), Theme.lemon, Theme.grass, Theme.ocean, Color(hex: "9B5DE5"), Theme.bubblegum]

    var body: some View {
        TimelineView(.animation(paused: phase != .active)) { ctx in
            Canvas(rendersAsynchronously: false) { gc, size in
                let state = box.state(for: size)
                state.advance(to: ctx.date)
                TilesPainter.draw(state, in: &gc, size: size)
            }
        }
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in box.current?.dragChanged(location: v.location, start: v.startLocation, play: play) }
                .onEnded { v in box.current?.dragEnded(location: v.location, start: v.startLocation, play: play) }
        )
        .onAppear {
            synth.start()
            sounds.load()
            shake.onShake = {
                box.current?.shuffle()
                sounds.play("chime", volume: 0.5, rate: Double.random(in: 0.9...1.2))
            }
            shake.start()
        }
        .onDisappear {
            shake.stop()
            synth.stop()
            sounds.unload()
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                shake.start()
                synth.start()
            } else {
                shake.stop()
                synth.stop()
            }
        }
    }

    private func play(_ column: Int, _ row: Int, _ grid: TileGrid) {
        let id = 200 + row * grid.columns + column
        synth.began(id: id, voice: FingerMusic.tileVoice(column: column, row: row, columns: grid.columns, rows: grid.rows))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            synth.ended(id: id)
        }
    }
}

@MainActor
final class TilesBox {
    private(set) var current: TilesState?

    func state(for size: CGSize) -> TilesState {
        if let current, abs(current.size.width - size.width) < 1, abs(current.size.height - size.height) < 1 { return current }
        let s = TilesState(size: size)
        current = s
        return s
    }
}

/// The grid plus the finger: which cells the current swipe already turned.
@MainActor
final class TilesState {
    let size: CGSize
    let columns = 5
    let rows: Int
    let cell: CGFloat
    let origin: CGPoint
    var grid: TileGrid
    var lastDate: Date?
    private var visited: Set<Int> = []
    private var swiping = false

    init(size: CGSize) {
        self.size = size
        cell = size.width / CGFloat(columns)
        rows = max(1, Int(size.height / cell))
        origin = CGPoint(x: 0, y: (size.height - CGFloat(rows) * cell) / 2)
        grid = TileGrid(columns: columns, rows: rows, seed: UInt64(Date().timeIntervalSince1970))
    }

    func advance(to date: Date) {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        grid.step(dt: dt)
    }

    func cellAt(_ p: CGPoint) -> (Int, Int)? {
        let c = Int((p.x - origin.x) / cell), r = Int((p.y - origin.y) / cell)
        guard c >= 0, c < columns, r >= 0, r < rows else { return nil }
        return (c, r)
    }

    func dragChanged(location p: CGPoint, start: CGPoint, play: (Int, Int, TileGrid) -> Void) {
        guard hypot(p.x - start.x, p.y - start.y) > 14 else { return }
        swiping = true
        guard let (c, r) = cellAt(p), let i = grid.index(column: c, row: r), !visited.contains(i) else { return }
        visited.insert(i)
        let direction = (p.x - start.x) + (p.y - start.y) >= 0 ? 1 : -1
        grid.turn(column: c, row: r, direction: direction)
        play(c, r, grid)
    }

    func dragEnded(location p: CGPoint, start: CGPoint, play: (Int, Int, TileGrid) -> Void) {
        defer {
            visited.removeAll()
            swiping = false
        }
        guard !swiping, let (c, r) = cellAt(p) else { return }
        grid.turn(column: c, row: r)
        play(c, r, grid)
    }

    func shuffle() {
        grid.shuffle(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    }
}

enum TilesPainter {
    @MainActor
    static func draw(_ s: TilesState, in gc: inout GraphicsContext, size: CGSize) {
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sky))
        let cell = s.cell
        for r in 0..<s.rows {
            for c in 0..<s.columns {
                guard let i = s.grid.index(column: c, row: r) else { continue }
                let t = s.grid.tiles[i]
                let rect = CGRect(x: s.origin.x + CGFloat(c) * cell, y: s.origin.y + CGFloat(r) * cell, width: cell, height: cell)
                gc.fill(Path(rect), with: .color((c + r) % 2 == 0 ? .white : Color(hex: "FFF6CC")))
                var tile = gc
                tile.clip(to: Path(rect))
                tile.translateBy(x: rect.midX, y: rect.midY)
                tile.rotate(by: .radians(t.angle))
                tile.translateBy(x: -cell / 2, y: -cell / 2)
                drawShape(t, cell: cell, in: &tile)
                gc.stroke(Path(rect), with: .color(Theme.ink), lineWidth: 3)
            }
        }
    }

    static func drawShape(_ t: Tile, cell: CGFloat, in gc: inout GraphicsContext) {
        let color = TilesSketchView.colors[t.colorIndex % TilesSketchView.colors.count]
        switch t.kind {
        case .arcs:
            var arcs = Path()
            arcs.addArc(center: .zero, radius: cell / 2, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            arcs.move(to: CGPoint(x: cell, y: cell / 2))
            arcs.addArc(center: CGPoint(x: cell, y: cell), radius: cell / 2, startAngle: .degrees(-90), endAngle: .degrees(-180), clockwise: true)
            gc.stroke(arcs, with: .color(Theme.ink), style: StrokeStyle(lineWidth: cell * 0.30, lineCap: .butt))
            gc.stroke(arcs, with: .color(color), style: StrokeStyle(lineWidth: cell * 0.22, lineCap: .butt))
        case .triangle:
            var tri = Path()
            tri.move(to: .zero)
            tri.addLine(to: CGPoint(x: cell, y: 0))
            tri.addLine(to: CGPoint(x: 0, y: cell))
            tri.closeSubpath()
            gc.fill(tri, with: .color(color))
            gc.stroke(tri, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        case .quarter:
            var pie = Path()
            pie.move(to: .zero)
            pie.addArc(center: .zero, radius: cell * 0.92, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            pie.closeSubpath()
            gc.fill(pie, with: .color(color))
            gc.stroke(pie, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            gc.fill(Path(ellipseIn: CGRect(x: cell * 0.5 - 7, y: cell * 0.5 - 7, width: 14, height: 14)), with: .color(.white))
            gc.stroke(Path(ellipseIn: CGRect(x: cell * 0.5 - 7, y: cell * 0.5 - 7, width: 14, height: 14)), with: .color(Theme.ink), lineWidth: 2.5)
        }
    }
}

/// The library tile: a small 3 × 3 grid of shapes.
struct TilesSticker: View {
    var body: some View {
        Canvas { gc, size in
            let cell = size.width / 3
            let grid = TileGrid(columns: 3, rows: 3, seed: 11)
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for r in 0..<3 {
                for c in 0..<3 {
                    let t = grid.tiles[r * 3 + c]
                    let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                    gc.fill(Path(rect), with: .color((c + r) % 2 == 0 ? .white : Color(hex: "FFF6CC")))
                    var tile = gc
                    tile.clip(to: Path(rect))
                    tile.translateBy(x: rect.midX, y: rect.midY)
                    tile.rotate(by: .radians(t.angle))
                    tile.translateBy(x: -cell / 2, y: -cell / 2)
                    TilesPainter.drawShape(t, cell: cell, in: &tile)
                    gc.stroke(Path(rect), with: .color(Theme.ink), lineWidth: 2)
                }
            }
        }
    }
}
