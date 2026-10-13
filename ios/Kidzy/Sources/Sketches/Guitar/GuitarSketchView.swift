import SwiftUI

/// « Guitare »: six strings, a finger across them strums the current chord,
/// chord stickers below, and the chords follow a Beatles-flavoured song when
/// the kid just strums. Tap the sound hole or bump the table: next song.
struct GuitarSketchView: View {
    @Environment(\.scenePhase) private var phase
    @State private var box = GuitarBox()
    @State private var synth = GuitarSynth()
    @State private var shake = ShakeSensor()
    @State private var sounds = SoundBank()

    var body: some View {
        TimelineView(.animation(paused: phase != .active)) { ctx in
            Canvas(rendersAsynchronously: false) { gc, size in
                let state = box.state(for: size)
                state.advance(to: ctx.date)
                GuitarPainter.draw(state, in: &gc, size: size)
            }
        }
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in box.current?.dragChanged(location: v.location, start: v.startLocation, synth: synth) }
                .onEnded { v in box.current?.dragEnded(location: v.location, start: v.startLocation, synth: synth, sounds: sounds) }
        )
        .onAppear {
            synth.start()
            sounds.load()
            shake.onShake = {
                box.current?.nextSong()
                sounds.play("chime", volume: 0.5, rate: 1.1)
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
}

@MainActor
final class GuitarBox {
    private(set) var current: GuitarState?
    func state(for size: CGSize) -> GuitarState {
        if let current, abs(current.size.width - size.width) < 1, abs(current.size.height - size.height) < 1 { return current }
        let s = GuitarState(size: size)
        current = s
        return s
    }
}

/// The model plus what the view needs: string wobble, the finger, the layout.
@MainActor
final class GuitarState {
    let size: CGSize
    var model = GuitarModel()
    var wobble = [Double](repeating: 0, count: GuitarModel.strings)   // visual amplitude per string
    var wobblePhase = [Double](repeating: 0, count: GuitarModel.strings)
    var lastDate: Date?
    var time = 0.0
    var lastX: Double?
    var lastTime = 0.0
    var chordFlash = 0.0
    var holeFlash = 0.0

    static let colors: [Color] = [Theme.coral, Theme.lemon, Theme.ocean, Theme.grass]

    init(size: CGSize) { self.size = size }

    var stringTop: Double { size.height * 0.16 }
    var stringBottom: Double { size.height * 0.70 }
    var holeCenter: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.5) }
    var holeRadius: Double { size.width * 0.17 }
    var stickerY: Double { size.height * 0.84 }
    var stickerRadius: Double { min(34, size.width / 12) }

    func stickerX(_ i: Int, of n: Int) -> Double {
        let span = size.width * 0.7
        return n > 1 ? size.width * 0.15 + span * Double(i) / Double(n - 1) : size.width / 2
    }

    func advance(to date: Date) {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        time += dt
        for i in wobble.indices {
            wobble[i] *= pow(0.12, dt)
            wobblePhase[i] += dt * (30 + Double(i) * 6)
        }
        chordFlash = max(0, chordFlash - dt)
        holeFlash = max(0, holeFlash - dt)
    }

    func dragChanged(location p: CGPoint, start: CGPoint, synth: GuitarSynth) {
        guard p.y > stringTop - 20, p.y < stringBottom + 20 else { return }
        guard let lastX else {
            lastX = p.x
            lastTime = time
            return
        }
        let dt = max(1.0 / 120, time - lastTime)
        let speed = abs(p.x - lastX) / dt
        for s in GuitarModel.crossed(from: lastX, to: p.x, width: size.width) {
            pluck(s, velocity: min(1, 0.25 + speed / 1800), synth: synth)
        }
        self.lastX = p.x
        lastTime = time
    }

    func dragEnded(location p: CGPoint, start: CGPoint, synth: GuitarSynth, sounds: SoundBank) {
        defer { lastX = nil }
        let moved = hypot(p.x - start.x, p.y - start.y)
        if moved < 12 {
            // a tap: a sticker, the sound hole, or one string
            let palette = model.song.palette
            for (i, chord) in palette.enumerated() where hypot(p.x - stickerX(i, of: palette.count), p.y - stickerY) < stickerRadius + 14 {
                model.choose(chord: chord, at: time)
                chordFlash = 0.4
                strum(synth: synth, velocity: 0.7)
                return
            }
            if hypot(p.x - holeCenter.x, p.y - holeCenter.y) < holeRadius {
                nextSong()
                sounds.play("chime", volume: 0.5, rate: 1.1)
                return
            }
            if p.y > stringTop, p.y < stringBottom {
                let nearest = (0..<GuitarModel.strings).min { abs(GuitarModel.stringX($0, width: size.width) - p.x) < abs(GuitarModel.stringX($1, width: size.width) - p.x) }!
                if abs(GuitarModel.stringX(nearest, width: size.width) - p.x) < 26 { pluck(nearest, velocity: 0.6, synth: synth) }
            }
            return
        }
        model.gestureEnded(at: time)
    }

    func pluck(_ i: Int, velocity: Double, synth: GuitarSynth) {
        model.pluckedStrings(1)
        wobble[i] = 6 + 8 * velocity
        if let midi = model.chord.notes[i] {
            synth.pluck(string: i, frequency: Chord.frequency(midi: midi), velocity: velocity)
        } else {
            synth.mute(string: i)
        }
    }

    /// All six strings in a quick downstroke, for a sticker tap.
    func strum(synth: GuitarSynth, velocity: Double) {
        for i in 0..<GuitarModel.strings {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(28 * i))
                self.wobble[i] = 10
                if let midi = self.model.chord.notes[i] { synth.pluck(string: i, frequency: Chord.frequency(midi: midi), velocity: velocity) }
            }
        }
    }

    func nextSong() {
        model.nextSong()
        holeFlash = 0.5
        chordFlash = 0.5
    }
}

enum GuitarPainter {
    @MainActor
    static func draw(_ s: GuitarState, in gc: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sky))
        // body: two rounded lobes, tangerine with ink outline, a darker pickguard
        let bodyColor = Color(hex: "FFA62B")
        var body = Path()
        body.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.34, width: w * 0.84, height: h * 0.34))
        body.addEllipse(in: CGRect(x: w * 0.02, y: h * 0.50, width: w * 0.96, height: h * 0.34))
        gc.fill(body, with: .color(Theme.ink))
        var bodyIn = Path()
        bodyIn.addEllipse(in: CGRect(x: w * 0.08 + 6, y: h * 0.34 + 6, width: w * 0.84 - 12, height: h * 0.34 - 12))
        bodyIn.addEllipse(in: CGRect(x: w * 0.02 + 6, y: h * 0.50 + 6, width: w * 0.96 - 12, height: h * 0.34 - 12))
        gc.fill(bodyIn, with: .color(bodyColor))
        // neck
        let neck = CGRect(x: w * 0.5 - w * 0.25, y: -10, width: w * 0.5, height: h * 0.42)
        gc.fill(Path(roundedRect: neck, cornerRadius: 18), with: .color(Color(hex: "8B5A2B")))
        gc.stroke(Path(roundedRect: neck, cornerRadius: 18), with: .color(Theme.ink), lineWidth: 5)
        for f in 1...6 {
            let y = h * 0.04 + Double(f) * h * 0.052
            gc.stroke(Path { $0.move(to: CGPoint(x: neck.minX + 6, y: y)); $0.addLine(to: CGPoint(x: neck.maxX - 6, y: y)) }, with: .color(Theme.lemon), lineWidth: 3)
        }
        // sound hole
        let hr = s.holeRadius * (1 + 0.15 * s.holeFlash)
        let hole = Path(ellipseIn: CGRect(x: s.holeCenter.x - hr, y: s.holeCenter.y - hr, width: 2 * hr, height: 2 * hr))
        gc.fill(hole, with: .color(Theme.ink))
        gc.stroke(Path(ellipseIn: CGRect(x: s.holeCenter.x - hr - 7, y: s.holeCenter.y - hr - 7, width: 2 * hr + 14, height: 2 * hr + 14)), with: .color(Theme.lemon), lineWidth: 6)
        // bridge
        let bridge = CGRect(x: w * 0.5 - w * 0.27, y: s.stringBottom - 4, width: w * 0.54, height: 22)
        gc.fill(Path(roundedRect: bridge, cornerRadius: 8), with: .color(Theme.ink))
        // strings, wobbling
        for i in 0..<GuitarModel.strings {
            let x = GuitarModel.stringX(i, width: w)
            var path = Path()
            let steps = 40
            for k in 0...steps {
                let t = Double(k) / Double(steps)
                let y = s.stringTop + (s.stringBottom - s.stringTop) * t
                let dx = s.wobble[i] * sin(t * .pi) * sin(s.wobblePhase[i] + Double(k) * 0.4)
                let p = CGPoint(x: x + dx, y: y)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let width = 5.0 - Double(i) * 0.5
            let muted = s.model.chord.notes[i] == nil
            gc.stroke(path, with: .color(muted ? Theme.ink.opacity(0.35) : Theme.ink), lineWidth: width + 2)
            gc.stroke(path, with: .color(muted ? Color(hex: "C9CFDA") : .white), lineWidth: width)
        }
        // chord stickers
        let palette = s.model.song.palette
        for (i, chord) in palette.enumerated() {
            let c = CGPoint(x: s.stickerX(i, of: palette.count), y: s.stickerY)
            let current = chord == s.model.chord
            let r = s.stickerRadius * (current ? 1.25 + 0.15 * s.chordFlash : 1)
            gc.fill(Path(ellipseIn: CGRect(x: c.x - r + 5, y: c.y - r + 5, width: 2 * r, height: 2 * r)), with: .color(Theme.ink))
            gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(GuitarState.colors[i % GuitarState.colors.count]))
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.ink), lineWidth: current ? 6 : 4)
            // a little shape per chord so they can be told apart without reading
            var mark = Path()
            switch i % 4 {
            case 0: mark.addEllipse(in: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6))
            case 1: mark.addRect(CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6))
            case 2:
                mark.move(to: CGPoint(x: c.x, y: c.y - r * 0.36))
                mark.addLine(to: CGPoint(x: c.x + r * 0.36, y: c.y + r * 0.3))
                mark.addLine(to: CGPoint(x: c.x - r * 0.36, y: c.y + r * 0.3))
                mark.closeSubpath()
            default:
                mark.move(to: CGPoint(x: c.x, y: c.y - r * 0.38))
                mark.addLine(to: CGPoint(x: c.x + r * 0.38, y: c.y))
                mark.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.38))
                mark.addLine(to: CGPoint(x: c.x - r * 0.38, y: c.y))
                mark.closeSubpath()
            }
            gc.fill(mark, with: .color(.white))
            gc.stroke(mark, with: .color(Theme.ink), lineWidth: 3)
        }
    }
}

/// The library tile: a small guitar.
struct GuitarSticker: View {
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sky))
            var body = Path()
            body.addEllipse(in: CGRect(x: w * 0.22, y: h * 0.38, width: w * 0.56, height: h * 0.3))
            body.addEllipse(in: CGRect(x: w * 0.16, y: h * 0.55, width: w * 0.68, height: h * 0.36))
            gc.fill(body, with: .color(Theme.ink))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: w * 0.22 + 4, y: h * 0.38 + 4, width: w * 0.56 - 8, height: h * 0.3 - 8))
            inner.addEllipse(in: CGRect(x: w * 0.16 + 4, y: h * 0.55 + 4, width: w * 0.68 - 8, height: h * 0.36 - 8))
            gc.fill(inner, with: .color(Color(hex: "FFA62B")))
            let neck = CGRect(x: w * 0.42, y: h * 0.06, width: w * 0.16, height: h * 0.45)
            gc.fill(Path(roundedRect: neck, cornerRadius: 6), with: .color(Color(hex: "8B5A2B")))
            gc.stroke(Path(roundedRect: neck, cornerRadius: 6), with: .color(Theme.ink), lineWidth: 3)
            gc.fill(Path(ellipseIn: CGRect(x: w * 0.5 - w * 0.09, y: h * 0.56, width: w * 0.18, height: w * 0.18)), with: .color(Theme.ink))
            for i in 0..<6 {
                let x = w * 0.44 + Double(i) * w * 0.024
                gc.stroke(Path { $0.move(to: CGPoint(x: x, y: h * 0.1)); $0.addLine(to: CGPoint(x: x, y: h * 0.8)) }, with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}
