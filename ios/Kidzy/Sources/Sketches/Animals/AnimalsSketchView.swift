import AVFoundation
import SwiftUI

/// « Animaux »: one big animal sticker. Tap: it bounces, says its name and
/// makes its cry. Swipe left or right: the next or previous animal.
struct AnimalsSketchView: View {
    struct Animal: Identifiable {
        let id: String      // image and sound file stem
        let name: String    // spoken, French with the article
        let color: Color
    }

    static let animals: [Animal] = [
        Animal(id: "vache", name: "la vache", color: Theme.grass),
        Animal(id: "chat", name: "le chat", color: Theme.bubblegum),
        Animal(id: "chien", name: "le chien", color: Theme.lemon),
        Animal(id: "canard", name: "le canard", color: Theme.ocean),
        Animal(id: "mouton", name: "le mouton", color: Color(hex: "9B5DE5")),
        Animal(id: "coq", name: "le coq", color: Theme.coral),
        Animal(id: "lion", name: "le lion", color: Color(hex: "FFA62B")),
        Animal(id: "ane", name: "l'âne", color: Theme.sky),
        Animal(id: "grenouille", name: "la grenouille", color: Theme.grass),
        Animal(id: "cochon", name: "le cochon", color: Theme.bubblegum),
    ]

    @Environment(\.scenePhase) private var phase
    @State private var index = 0
    @State private var bounce = false
    @State private var offset: CGFloat = 0
    @State private var sounds = AnimalSounds()
    @State private var busy = false

    private var animal: Animal { Self.animals[index] }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, geo.size.height * 0.55)
            ZStack {
                LinearGradient(colors: [Theme.sky, .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Cloud().offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.36)
                Cloud().scaleEffect(0.7).offset(x: geo.size.width * 0.32, y: geo.size.height * 0.3)
                VStack(spacing: 0) {
                    Spacer()
                    StickerTile(color: animal.color, tilt: index % 2 == 0 ? -2 : 2, radius: 36, innerRadius: 24) {
                        AnimalImage(id: animal.id)
                            .frame(width: side - 28, height: side - 28)
                    }
                    .frame(width: side, height: side)
                    .scaleEffect(bounce ? 1.12 : 1)
                    .rotationEffect(.degrees(bounce ? (index % 2 == 0 ? 4 : -4) : 0))
                    .offset(x: offset)
                    .animation(.spring(duration: 0.35, bounce: 0.55), value: bounce)
                    .animation(.spring(duration: 0.45, bounce: 0.3), value: offset)
                    .accessibilityLabel(animal.name)
                    Spacer()
                    HStack(spacing: 10) {
                        ForEach(Self.animals.indices, id: \.self) { i in
                            Circle()
                                .fill(i == index ? Theme.ink : Theme.paper)
                                .overlay(Circle().stroke(Theme.ink, lineWidth: 2))
                                .frame(width: 12, height: 12)
                        }
                    }
                    .padding(.bottom, 48)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { v in
                        let dx = v.translation.width
                        if abs(dx) > 50 {
                            go(dx < 0 ? 1 : -1, width: geo.size.width)
                        } else if abs(v.translation.height) < 30 {
                            play()
                        }
                    }
            )
        }
        .onAppear { sounds.prepare() }
        .onDisappear { sounds.stop() }
        .onChange(of: phase) { _, p in
            if p != .active { sounds.stop() }
        }
    }

    private func play() {
        guard !busy else { return }
        busy = true
        bounce = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            bounce = false
            await sounds.say(animal.id, fallback: animal.name)
            sounds.cry(animal.id)
            try? await Task.sleep(for: .milliseconds(400))
            busy = false
        }
    }

    private func go(_ direction: Int, width: CGFloat) {
        sounds.stop()
        offset = CGFloat(-direction) * width
        index = (index + direction + Self.animals.count) % Self.animals.count
        offset = CGFloat(direction) * width
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { offset = 0 }
        sounds.plop()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            play()
        }
    }
}

/// The sticker image from Resources/Animals, with a drawn stand-in when missing.
struct AnimalImage: View {
    let id: String

    var body: some View {
        if let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: nil), let ui = UIImage(contentsOfFile: url.path) {
            Image(uiImage: ui).resizable().scaledToFit().background(Color.white)
        } else {
            ZStack {
                Color.white
                Image(systemName: "pawprint.fill").font(.system(size: 80)).foregroundStyle(Theme.ink)
            }
        }
    }
}

/// The name (name-<id>.wav, a Gemini TTS voice) then the cry (animal-<id>.wav,
/// Gemini TTS performing the onomatopoeia); the system voice only as fallback.
@MainActor
final class AnimalSounds {
    private let synthesizer = AVSpeechSynthesizer()
    private var cries: [String: AVAudioPlayer] = [:]
    private var names: [String: AVAudioPlayer] = [:]
    private let bank = SoundBank()

    func prepare() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        bank.load()
        for a in AnimalsSketchView.animals {
            if let url = Bundle.main.url(forResource: "animal-" + a.id, withExtension: "wav"), let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                cries[a.id] = p
            }
            if let url = Bundle.main.url(forResource: "name-" + a.id, withExtension: "wav"), let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                names[a.id] = p
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        for p in cries.values { p.stop() }
        for p in names.values { p.stop() }
    }

    /// Plays the recorded name and waits for it; falls back to the system voice.
    func say(_ id: String, fallback text: String) async {
        if let p = names[id] {
            p.currentTime = 0
            p.play()
            try? await Task.sleep(for: .seconds(max(0.3, p.duration + 0.15)))
            return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(u)
        try? await Task.sleep(for: .seconds(0.35 + Double(text.count) * 0.07))
    }

    func cry(_ id: String) {
        guard let p = cries[id] else { return }
        p.currentTime = 0
        p.play()
    }

    func plop() { bank.play("plop", volume: 0.3, rate: Double.random(in: 0.9...1.2)) }
}

/// The library tile: the cow sticker.
struct AnimalsSticker: View {
    var body: some View {
        ZStack {
            Color.white
            AnimalImage(id: "vache").padding(6)
        }
    }
}
