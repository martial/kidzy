import AVFoundation
import SwiftUI

/// « Perroquet »: the parrot listens; when the voice stops it repeats the
/// phrase in a silly voice. A tap: it says the last phrase again, or squawks.
struct ParrotSketchView: View {
    enum Frame: Hashable {
        case idle
        case talk
        case listen
    }

    @Environment(\.toyExit) private var toyExit
    @Environment(\.scenePhase) private var phase
    @State private var ear = ParrotEar()
    @State private var frames = ParrotFrames()
    @State private var squawk = Squawk()
    @State private var notes = FlyingNotes()
    @State private var beakOpen = false
    @State private var perked = false
    @State private var pop = false
    @State private var lastActivity = Date()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = min(w - 64, h * 0.46)
            let center = CGPoint(x: w / 2, y: h * 0.47)
            let beak = CGPoint(x: center.x - side * 0.3, y: center.y - side * 0.14)
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let talking = ear.state == .repeating
                let energy = talking ? ear.mouth : ear.level
                let frame: Frame = talking ? (beakOpen ? .talk : .idle) : (perked ? .listen : .idle)
                ZStack {
                    LinearGradient(colors: [Theme.sky, .white], startPoint: .top, endPoint: .bottom)
                    Cloud().position(x: w * 0.2, y: h * 0.12)
                    Cloud().scaleEffect(0.7).position(x: w * 0.82, y: h * 0.22)
                    Foliage()
                    Branch()
                        .frame(width: w + 80, height: 30)
                        .position(x: center.x, y: center.y + side / 2 + 4)
                    StickerTile(color: Color(hex: "9B5DE5"), tilt: 0, radius: 36, innerRadius: 24) {
                        ParrotImage(image: frames.image(for: frame))
                            .frame(width: side - 28, height: side - 28)
                    }
                    .frame(width: side, height: side)
                    .scaleEffect((pop ? 1.1 : 1) * (1 + energy * 0.08))
                    .rotationEffect(.degrees(sin(t * 1.3) * 2 + (talking ? sin(t * 11) * ear.mouth * 6 : -ear.level * 5)))
                    .position(x: center.x, y: center.y - (talking ? ear.mouth * 18 : 0))
                    .animation(.spring(duration: 0.3, bounce: 0.5), value: pop)
                    .accessibilityLabel("Le perroquet")
                    ParrotFX(notes: notes, listening: ear.state == .listening ? ear.level : 0, beak: beak, now: t)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tapped() }
        .onAppear {
            squawk.load()
            ear.onEvent = { event in
                lastActivity = Date()
                if event == "repeat" { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
            Task { await ear.start() }
        }
        .onDisappear { ear.stop() }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await ear.start() } } else { ear.stop() }
        }
        .onChange(of: ear.level) { _, l in
            if l > 0.3 { perked = true } else if l < 0.1 { perked = false }
        }
        .onChange(of: ear.mouth) { _, m in
            if m > 0.3 {
                if !beakOpen { notes.spawn() }
                beakOpen = true
            } else if m < 0.12 {
                beakOpen = false
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Date().timeIntervalSince(lastActivity) > 300 { toyExit() }
            }
        }
    }

    private func tapped() {
        lastActivity = Date()
        pop = true
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            pop = false
        }
        if !ear.replay() { squawk.play() }
    }
}

/// The three stickers from Resources/Parrot, loaded once.
@MainActor
final class ParrotFrames {
    private var cache: [ParrotSketchView.Frame: UIImage] = [:]

    func image(for frame: ParrotSketchView.Frame) -> UIImage? {
        if let image = cache[frame] { return image }
        let name = switch frame {
        case .idle: "parrot-idle"
        case .talk: "parrot-talk"
        case .listen: "parrot-listen"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[frame] = image
        return image
    }
}

struct ParrotImage: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit().background(Color.white)
        } else {
            ZStack {
                Color.white
                Image(systemName: "bird.fill").font(.system(size: 80)).foregroundStyle(Theme.ink)
            }
        }
    }
}

/// The parrot's own cry (a Gemini TTS performance), for a tap before any phrase.
@MainActor
final class Squawk {
    private var player: AVAudioPlayer?

    func load() {
        guard player == nil, let url = Bundle.main.url(forResource: "animal-perroquet", withExtension: "wav") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.volume = 0.8
        player.play()
    }
}

/// Little notes that fly out of the beak while the parrot talks.
@MainActor
final class FlyingNotes {
    struct Note {
        var vx: Double
        var vy: Double
        var born: Double
        var spin: Double
        var color: Color
    }

    private(set) var notes: [Note] = []
    static let life = 1.4

    func spawn() {
        notes.append(Note(vx: -Double.random(in: 30...110), vy: -Double.random(in: 90...170), born: Date().timeIntervalSinceReferenceDate, spin: Double.random(in: -1...1), color: [Theme.coral, Theme.lemon, Theme.ocean, Theme.grass].randomElement() ?? Theme.coral))
        if notes.count > 12 { notes.removeFirst() }
    }

    func prune(now: Double) {
        notes.removeAll { now - $0.born > Self.life }
    }
}

/// Over the scene: sound coming in while listening, notes going out while talking.
struct ParrotFX: View {
    let notes: FlyingNotes
    let listening: Double
    let beak: CGPoint
    let now: Double

    var body: some View {
        Canvas { gc, _ in
            if listening > 0.05 {
                // waves coming toward the beak from the left
                let c = CGPoint(x: beak.x - 90, y: beak.y)
                for (i, r) in [28.0, 48.0, 68.0].enumerated() {
                    var arc = Path()
                    arc.addArc(center: c, radius: r, startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
                    let a = min(1, max(0, listening * 1.6 - Double(i) * 0.3))
                    gc.stroke(arc, with: .color(Theme.ink.opacity(a)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
            notes.prune(now: now)
            for n in notes.notes {
                let age = now - n.born
                let p = CGPoint(x: beak.x + n.vx * age, y: beak.y + n.vy * age + 40 * age * age)
                let alpha = 1 - age / FlyingNotes.life
                var ctx = gc
                ctx.opacity = alpha
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: .degrees(n.spin * age * 40))
                ctx.scaleBy(x: 1 + age * 0.3, y: 1 + age * 0.3)
                Self.drawNote(in: &ctx, color: n.color)
            }
        }
        .allowsHitTesting(false)
    }

    /// A sticker note: a tilted head, a stem and a flag, inked.
    static func drawNote(in gc: inout GraphicsContext, color: Color) {
        var stem = Path()
        stem.move(to: CGPoint(x: 7, y: 2))
        stem.addLine(to: CGPoint(x: 7, y: -26))
        stem.addQuadCurve(to: CGPoint(x: 20, y: -12), control: CGPoint(x: 18, y: -24))
        gc.stroke(stem, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        gc.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        var head = Path(ellipseIn: CGRect(x: -8, y: -5, width: 16, height: 11))
        head = head.applying(CGAffineTransform(rotationAngle: -0.4))
        gc.fill(head, with: .color(color))
        gc.stroke(head, with: .color(Theme.ink), lineWidth: 2.5)
    }
}

/// Big leaves in the corners, the top-left one left clear for the secret corner.
struct Foliage: View {
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            let leaves: [(CGPoint, Double, Double, Color)] = [
                (CGPoint(x: -6, y: h * 0.8), -40, 200, Theme.grass),
                (CGPoint(x: 30, y: h + 10), -70, 170, Color(hex: "3FB54B")),
                (CGPoint(x: w + 6, y: h * 0.86), 220, 220, Theme.grass),
                (CGPoint(x: w - 40, y: h + 10), 250, 160, Color(hex: "3FB54B")),
                (CGPoint(x: w + 10, y: h * 0.1), 160, 150, Color(hex: "3FB54B")),
                (CGPoint(x: -10, y: h * 0.34), 10, 130, Theme.grass),
            ]
            for (base, angle, length, color) in leaves {
                var ctx = gc
                ctx.translateBy(x: base.x, y: base.y)
                ctx.rotate(by: .degrees(angle))
                let leaf = Path(ellipseIn: CGRect(x: 0, y: -length * 0.21, width: length, height: length * 0.42))
                ctx.fill(leaf, with: .color(color))
                ctx.stroke(leaf, with: .color(Theme.ink), lineWidth: 4)
                var rib = Path()
                rib.move(to: CGPoint(x: 10, y: 0))
                rib.addLine(to: CGPoint(x: length - 14, y: 0))
                ctx.stroke(rib, with: .color(Theme.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

struct Branch: View {
    var body: some View {
        Capsule()
            .fill(Color(hex: "8B5A2B"))
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 4))
    }
}

/// The library tile: the parrot sticker.
struct ParrotSticker: View {
    var body: some View {
        ZStack {
            Color.white
            ParrotImage(image: Bundle.main.url(forResource: "parrot-idle", withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }).padding(6)
        }
    }
}
