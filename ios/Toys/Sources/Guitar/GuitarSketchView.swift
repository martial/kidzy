import SwiftUI

/// « Guitare »: a finger across the strings strums the chord, and real strums
/// walk through a Beatles-flavoured song; eight chord stickers hold a chord;
/// the neck is a melody pad in the song's key; the sky and a glow behind the
/// guitar take the chord's mood colour. Tap the sound hole or bump the table:
/// next song.
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
                state.advance(to: ctx.date, synth: synth)
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

/// Layout, model, sequencer and the finger.
@MainActor
final class GuitarState {
    let size: CGSize
    var model = GuitarModel()
    var wobble = [Double](repeating: 0, count: GuitarModel.strings)
    var wobblePhase = [Double](repeating: 0, count: GuitarModel.strings)
    var lastDate: Date?
    var time = 0.0
    var lastX: Double?
    var lastTime = 0.0
    var chordFlash = 0.0
    var holeFlash = 0.0
    var mood: (r: Double, g: Double, b: Double) = (1, 0.82, 0.25)   // follows the chord colour
    var melodyGlow: (y: Double, until: Double, note: Int)?
    var lastMelodyNote = -1
    var touchMode: TouchMode = .none

    enum TouchMode {
        case none, strum, melody
    }

    init(size: CGSize) {
        self.size = size
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["KIDZY_CHORD"], let c = Chord.palette.first(where: { $0.name == name }) {
            model.choose(chord: c, at: 0)
            mood = Self.rgb(c.colorHex)
        }
        #endif
    }

    var moodColor: Color { Color(.sRGB, red: mood.r, green: mood.g, blue: mood.b, opacity: 1) }

    // layout, portrait
    var headBottom: Double { size.height * 0.10 }
    var nutY: Double { headBottom + 4 }
    var neckBottom: Double { size.height * 0.46 }
    var bodyTop: Double { size.height * 0.40 }
    var bridgeY: Double { size.height * 0.745 }
    var holeCenter: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.575) }
    var holeRadius: Double { size.width * 0.15 }
    var stickerRadius: Double { min(27, size.width / 14.5) }

    func stickerCenter(_ i: Int) -> CGPoint {
        let row = i / 4, col = i % 4
        let span = size.width * 0.64
        return CGPoint(x: size.width * 0.18 + span * Double(col) / 3, y: size.height * (row == 0 ? 0.845 : 0.93))
    }

    /// String x at a given y: narrow at the nut, wide at the bridge.
    func stringX(_ i: Int, atY y: Double) -> Double {
        let spread = min(1, max(0, (y - nutY) / (bridgeY - nutY)))
        return GuitarModel.stringX(i, width: size.width, spread: spread)
    }

    func advance(to date: Date, synth: GuitarSynth) {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        time += dt
        for i in wobble.indices {
            wobble[i] *= pow(0.12, dt)
            wobblePhase[i] += dt * (30 + Double(i) * 6)
        }
        chordFlash = max(0, chordFlash - dt)
        holeFlash = max(0, holeFlash - dt)
        model.tick(at: time)
        let target = Self.rgb(model.chord.colorHex)
        let k = min(1, dt * 4)
        mood = (mood.r + (target.r - mood.r) * k, mood.g + (target.g - mood.g) * k, mood.b + (target.b - mood.b) * k)
    }

    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    func dragChanged(location p: CGPoint, start: CGPoint, synth: GuitarSynth) {
        if touchMode == .none {
            touchMode = start.y < bodyTop && start.y > headBottom ? .melody : (start.y >= bodyTop && start.y < bridgeY + 24 ? .strum : .none)
        }
        switch touchMode {
        case .melody:
            let fraction = (p.y - nutY) / (neckBottom - nutY)
            let note = model.melodyNote(at: fraction)
            if note != lastMelodyNote {
                lastMelodyNote = note
                synth.melody(midi: note, velocity: 0.75)
                melodyGlow = (y: Double(p.y), until: time + 0.5, note: note)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .strum:
            guard let lastX else {
                lastX = p.x
                lastTime = time
                return
            }
            let dt = max(1.0 / 120, time - lastTime)
            let speed = abs(p.x - lastX) / dt
            let spread = min(1, max(0, (p.y - nutY) / (bridgeY - nutY)))
            for s in GuitarModel.crossed(from: lastX, to: p.x, width: size.width, spread: spread) {
                pluck(s, velocity: min(1, 0.3 + speed / 1600), synth: synth)
            }
            self.lastX = p.x
            lastTime = time
        case .none:
            break
        }
    }

    func dragEnded(location p: CGPoint, start: CGPoint, synth: GuitarSynth, sounds: SoundBank) {
        defer {
            lastX = nil
            lastMelodyNote = -1
            touchMode = .none
            if model.gestureEnded(at: time) { chordFlash = 0.35 }
        }
        let moved = hypot(p.x - start.x, p.y - start.y)
        guard moved < 12 else { return }
        for (i, chord) in Chord.palette.enumerated() {
            let c = stickerCenter(i)
            if hypot(p.x - c.x, p.y - c.y) < stickerRadius + 12 {
                model.choose(chord: chord, at: time)
                chordFlash = 0.4
                strum(synth: synth, velocity: 0.7)
                return
            }
        }
        if hypot(p.x - holeCenter.x, p.y - holeCenter.y) < holeRadius {
            nextSong()
            sounds.play("chime", volume: 0.5, rate: 1.1)
            return
        }
        if touchMode == .strum {
            let nearest = (0..<GuitarModel.strings).min { abs(stringX($0, atY: p.y) - p.x) < abs(stringX($1, atY: p.y) - p.x) }!
            if abs(stringX(nearest, atY: p.y) - p.x) < 24 { pluck(nearest, velocity: 0.6, synth: synth) }
        } else if touchMode == .melody, lastMelodyNote < 0 {
            let note = model.melodyNote(at: (p.y - nutY) / (neckBottom - nutY))
            synth.melody(midi: note, velocity: 0.75)
            melodyGlow = (y: Double(p.y), until: time + 0.5, note: note)
        }
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

    func strum(synth: GuitarSynth, velocity: Double) {
        // a hand's strum: about 28 ms a string, never quite even
        var at = 0
        for i in 0..<GuitarModel.strings {
            let delay = at
            at += Int.random(in: 22...36)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delay))
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
    static let wood = Color(hex: "F2A541")
    static let woodDark = Color(hex: "D9842B")
    static let neckWood = Color(hex: "7A4A24")
    static let neckLight = Color(hex: "9A6236")

    @MainActor
    static func draw(_ s: GuitarState, in gc: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        // the sky takes the chord's mood: a light tint of its colour down to white
        let mood = s.moodColor
        let tint = SeaArt.mix(.white, mood, 0.45)
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [tint, .white]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let glowR = w * 0.62
        gc.fill(Path(ellipseIn: CGRect(x: w / 2 - glowR, y: s.holeCenter.y - glowR * 0.95, width: 2 * glowR, height: 2 * glowR)), with: .radialGradient(Gradient(colors: [mood.opacity(0.55), mood.opacity(0)]), center: CGPoint(x: w / 2, y: s.holeCenter.y), startRadius: 0, endRadius: glowR))

        // body: an acoustic silhouette, hard shadow, wood gradient, binding
        let body = GuitarArt.bodyPath(in: CGRect(x: w * 0.04, y: s.bodyTop, width: w * 0.92, height: h * 0.44))
        var shadow = gc
        shadow.translateBy(x: 7, y: 8)
        shadow.fill(body, with: .color(Theme.ink.opacity(0.9)))
        gc.fill(body, with: .radialGradient(Gradient(colors: [wood, woodDark]), center: CGPoint(x: w * 0.45, y: s.holeCenter.y - 20), startRadius: 20, endRadius: w * 0.7))
        var inner = gc
        inner.clip(to: body)
        inner.stroke(body, with: .color(Theme.lemon.opacity(0.9)), lineWidth: 10)
        gc.stroke(body, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 6, lineJoin: .round))

        // pickguard
        var guard_ = Path()
        guard_.move(to: CGPoint(x: s.holeCenter.x + s.holeRadius + 10, y: s.holeCenter.y - s.holeRadius * 0.7))
        guard_.addQuadCurve(to: CGPoint(x: w * 0.84, y: s.holeCenter.y + s.holeRadius * 0.9), control: CGPoint(x: w * 0.92, y: s.holeCenter.y - s.holeRadius * 0.6))
        guard_.addQuadCurve(to: CGPoint(x: s.holeCenter.x + s.holeRadius * 0.4, y: s.holeCenter.y + s.holeRadius + 14), control: CGPoint(x: w * 0.78, y: s.holeCenter.y + s.holeRadius * 1.3))
        guard_.addQuadCurve(to: CGPoint(x: s.holeCenter.x + s.holeRadius + 10, y: s.holeCenter.y - s.holeRadius * 0.7), control: CGPoint(x: s.holeCenter.x + s.holeRadius + 24, y: s.holeCenter.y + 8))
        guard_.closeSubpath()
        gc.fill(guard_, with: .color(Theme.ink.opacity(0.18)))

        // rosette and sound hole
        let hr = s.holeRadius * (1 + 0.1 * s.holeFlash)
        for (ring, color) in [(hr + 22, Theme.ink), (hr + 17, Theme.lemon), (hr + 12, Theme.coral), (hr + 7, Theme.ink)] {
            gc.stroke(Path(ellipseIn: CGRect(x: s.holeCenter.x - ring, y: s.holeCenter.y - ring, width: 2 * ring, height: 2 * ring)), with: .color(color), lineWidth: 4)
        }
        gc.fill(Path(ellipseIn: CGRect(x: s.holeCenter.x - hr, y: s.holeCenter.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(Theme.ink))

        // neck, frets, dots
        let neck = CGRect(x: w * 0.5 - w * 0.165, y: s.headBottom - 8, width: w * 0.33, height: s.neckBottom - s.headBottom + 8)
        gc.fill(Path(roundedRect: neck, cornerRadius: 10), with: .linearGradient(Gradient(colors: [neckLight, neckWood]), startPoint: CGPoint(x: neck.minX, y: 0), endPoint: CGPoint(x: neck.maxX, y: 0)))
        gc.stroke(Path(roundedRect: neck, cornerRadius: 10), with: .color(Theme.ink), lineWidth: 5)
        let fretCount = 9
        for f in 0...fretCount {
            let y = s.nutY + (s.neckBottom - s.nutY) * Double(f) / Double(fretCount)
            gc.stroke(Path { $0.move(to: CGPoint(x: neck.minX + 4, y: y)); $0.addLine(to: CGPoint(x: neck.maxX - 4, y: y)) }, with: .color(f == 0 ? .white : Theme.lemon), lineWidth: f == 0 ? 6 : 3)
        }
        for f in [3, 5, 7] {
            let y = s.nutY + (s.neckBottom - s.nutY) * (Double(f) - 0.5) / Double(fretCount)
            gc.fill(Path(ellipseIn: CGRect(x: neck.midX - 5, y: y - 5, width: 10, height: 10)), with: .color(.white.opacity(0.9)))
        }
        if let glow = s.melodyGlow, glow.until > s.time {
            let a = (glow.until - s.time) / 0.5
            let r = 18 + 14 * (1 - a)
            gc.fill(Path(ellipseIn: CGRect(x: neck.midX - r, y: glow.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.lemon.opacity(0.7 * a)))
        }

        // headstock with pegs
        let head = CGRect(x: w * 0.5 - w * 0.19, y: -16, width: w * 0.38, height: s.headBottom + 16)
        gc.fill(Path(roundedRect: head, cornerRadius: 16), with: .color(Theme.ink))
        gc.fill(Path(roundedRect: head.insetBy(dx: 5, dy: 5), cornerRadius: 12), with: .color(neckWood))
        for i in 0..<3 {
            let y = 14 + Double(i) * (s.headBottom - 24) / 2.5
            for sx in [-1.0, 1.0] {
                let x = w * 0.5 + sx * w * 0.21
                gc.fill(Path(ellipseIn: CGRect(x: x - 8, y: y - 6, width: 16, height: 12)), with: .color(Theme.ink))
                gc.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 3.5, width: 10, height: 7)), with: .color(.white))
            }
        }

        // bridge with saddle and pins
        let bridge = CGRect(x: w * 0.5 - w * 0.29, y: s.bridgeY - 8, width: w * 0.58, height: 26)
        gc.fill(Path(roundedRect: bridge, cornerRadius: 9), with: .color(Theme.ink))
        gc.fill(Path(roundedRect: CGRect(x: bridge.minX + 10, y: bridge.minY + 5, width: bridge.width - 20, height: 5), cornerRadius: 2), with: .color(.white))
        for i in 0..<GuitarModel.strings {
            let x = s.stringX(i, atY: s.bridgeY)
            gc.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: bridge.maxY - 10, width: 7, height: 7)), with: .color(Theme.lemon))
        }

        // strings, fanned from the nut to the bridge, wobbling
        for i in 0..<GuitarModel.strings {
            var path = Path()
            let steps = 44
            for k in 0...steps {
                let t = Double(k) / Double(steps)
                let y = s.nutY + (s.bridgeY - s.nutY) * t
                let dx = s.wobble[i] * sin(t * .pi) * sin(s.wobblePhase[i] + Double(k) * 0.4)
                let p = CGPoint(x: s.stringX(i, atY: y) + dx, y: y)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let width = 4.6 - Double(i) * 0.45
            let muted = s.model.chord.notes[i] == nil
            gc.stroke(path, with: .color(Theme.ink.opacity(muted ? 0.3 : 0.9)), lineWidth: width + 2)
            gc.stroke(path, with: .color(muted ? Color(hex: "C9CFDA") : Color(hex: "F4F7FB")), lineWidth: width)
        }

        // chord stickers, two rows, each in its chord's colour; the current one is bigger
        for (i, chord) in Chord.palette.enumerated() {
            let c = s.stickerCenter(i)
            let current = chord == s.model.chord
            let r = s.stickerRadius * (current ? 1.28 + 0.15 * s.chordFlash : 1)
            let color = Color(hex: chord.colorHex)
            gc.fill(Path(ellipseIn: CGRect(x: c.x - r + 4, y: c.y - r + 4, width: 2 * r, height: 2 * r)), with: .color(Theme.ink))
            gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.ink), lineWidth: current ? 5 : 3.5)
            // a mark per chord: majors get open shapes, minors a little moon
            var mark = Path()
            let minor = chord.name.hasSuffix("m")
            if minor {
                mark.addArc(center: CGPoint(x: c.x + r * 0.08, y: c.y), radius: r * 0.36, startAngle: .degrees(50), endAngle: .degrees(310), clockwise: false)
                mark.addArc(center: CGPoint(x: c.x + r * 0.3, y: c.y), radius: r * 0.36, startAngle: .degrees(240), endAngle: .degrees(120), clockwise: true)
                mark.closeSubpath()
            } else {
                switch i % 4 {
                case 0: mark.addEllipse(in: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6))
                case 1: mark.addRect(CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6))
                case 2:
                    mark.move(to: CGPoint(x: c.x, y: c.y - r * 0.36))
                    mark.addLine(to: CGPoint(x: c.x + r * 0.36, y: c.y + r * 0.3))
                    mark.addLine(to: CGPoint(x: c.x - r * 0.36, y: c.y + r * 0.3))
                    mark.closeSubpath()
                default:
                    for k in 0..<5 {
                        let a = Double(k) / 5 * 2 * .pi - .pi / 2
                        let b = a + .pi / 5
                        let outer = CGPoint(x: c.x + r * 0.4 * cos(a), y: c.y + r * 0.4 * sin(a))
                        let innerP = CGPoint(x: c.x + r * 0.17 * cos(b), y: c.y + r * 0.17 * sin(b))
                        if k == 0 { mark.move(to: outer) } else { mark.addLine(to: outer) }
                        mark.addLine(to: innerP)
                    }
                    mark.closeSubpath()
                }
            }
            gc.fill(mark, with: .color(.white))
            gc.stroke(mark, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
    }
}

enum GuitarArt {
    /// An acoustic body: upper bout, waist, lower bout, as one smooth path.
    static func bodyPath(in r: CGRect) -> Path {
        let cx = r.midX
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: cx, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.42), control1: CGPoint(x: r.minX + w * 0.12, y: r.minY - h * 0.02), control2: CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.18))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.72), control1: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.58), control2: CGPoint(x: r.minX - w * 0.04, y: r.minY + h * 0.56))
        p.addCurve(to: CGPoint(x: cx, y: r.maxY), control1: CGPoint(x: r.minX + w * 0.02, y: r.maxY + h * 0.02), control2: CGPoint(x: r.minX + w * 0.28, y: r.maxY + h * 0.02))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.72), control1: CGPoint(x: r.maxX - w * 0.28, y: r.maxY + h * 0.02), control2: CGPoint(x: r.maxX - w * 0.02, y: r.maxY + h * 0.02))
        p.addCurve(to: CGPoint(x: r.maxX - w * 0.12, y: r.minY + h * 0.42), control1: CGPoint(x: r.maxX + w * 0.04, y: r.minY + h * 0.56), control2: CGPoint(x: r.maxX - w * 0.2, y: r.minY + h * 0.58))
        p.addCurve(to: CGPoint(x: cx, y: r.minY), control1: CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.18), control2: CGPoint(x: r.maxX - w * 0.12, y: r.minY - h * 0.02))
        p.closeSubpath()
        return p
    }
}

/// The library tile: a small guitar.
struct GuitarSticker: View {
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sky))
            let body = GuitarArt.bodyPath(in: CGRect(x: w * 0.14, y: h * 0.36, width: w * 0.72, height: h * 0.58))
            var shadow = gc
            shadow.translateBy(x: 3, y: 4)
            shadow.fill(body, with: .color(Theme.ink))
            gc.fill(body, with: .color(GuitarPainter.wood))
            gc.stroke(body, with: .color(Theme.ink), lineWidth: 3)
            let neck = CGRect(x: w * 0.42, y: h * 0.05, width: w * 0.16, height: h * 0.42)
            gc.fill(Path(roundedRect: neck, cornerRadius: 5), with: .color(GuitarPainter.neckWood))
            gc.stroke(Path(roundedRect: neck, cornerRadius: 5), with: .color(Theme.ink), lineWidth: 2.5)
            let hr = w * 0.1
            gc.stroke(Path(ellipseIn: CGRect(x: w * 0.5 - hr - 4, y: h * 0.6 - hr - 4, width: 2 * hr + 8, height: 2 * hr + 8)), with: .color(Theme.lemon), lineWidth: 3)
            gc.fill(Path(ellipseIn: CGRect(x: w * 0.5 - hr, y: h * 0.6 - hr, width: 2 * hr, height: 2 * hr)), with: .color(Theme.ink))
            for i in 0..<6 {
                let x = w * 0.44 + Double(i) * w * 0.024
                gc.stroke(Path { $0.move(to: CGPoint(x: x, y: h * 0.08)); $0.addLine(to: CGPoint(x: x, y: h * 0.82)) }, with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}
