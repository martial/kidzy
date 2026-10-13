import SwiftUI

/// A sticker: white frame, ink border, hard offset shadow, a colour dot, a slight tilt.
struct StickerTile<Content: View>: View {
    var color: Color
    var tilt: Double
    var radius: CGFloat = 28
    var innerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.ink)
                .offset(x: 8, y: 8)
            content
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
                .padding(8)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.ink, lineWidth: 6))
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(color)
                .overlay(Circle().stroke(Theme.ink, lineWidth: 4))
                .frame(width: 34, height: 34)
                .offset(x: 8, y: 8)
        }
        .rotationEffect(.degrees(tilt))
    }
}

/// A big round button with the same sticker look (house, close).
struct StickerButton: View {
    var size: CGFloat = 72
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.ink).offset(x: 6, y: 6)
                Circle().fill(Theme.paper).overlay(Circle().stroke(Theme.ink, lineWidth: 6))
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Five stars: the time left today. They go out one by one.
struct StarsRow: View {
    var lit: Int
    var total = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(i < lit ? Theme.lemon : Theme.starOff)
                    .overlay(Image(systemName: "star").font(.system(size: 26, weight: .medium)).foregroundStyle(i < lit ? Theme.ink : Theme.starOffStroke))
            }
        }
        .accessibilityLabel("Temps restant aujourd'hui : \(lit) étoiles sur \(total)")
    }
}

/// Soft clouds behind the tiles.
struct Cloud: View {
    var body: some View {
        ZStack {
            Ellipse().frame(width: 112, height: 44).offset(x: -40, y: 8)
            Ellipse().frame(width: 80, height: 52)
            Ellipse().frame(width: 88, height: 40).offset(x: 44, y: 10)
        }
        .foregroundStyle(Theme.paper)
    }
}

/// The sun mascot peeking from the bottom of the library.
struct SunMascot: View {
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Theme.ink)
                    .frame(width: 6, height: 16)
                    .offset(y: -58)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle().fill(Theme.lemon).overlay(Circle().stroke(Theme.ink, lineWidth: 6)).frame(width: 84, height: 84)
            HStack(spacing: 20) {
                Circle().fill(Theme.ink).frame(width: 10, height: 10)
                Circle().fill(Theme.ink).frame(width: 10, height: 10)
            }
            .offset(y: -8)
            Path { p in
                p.move(to: CGPoint(x: -17, y: 10))
                p.addQuadCurve(to: CGPoint(x: 17, y: 10), control: CGPoint(x: 0, y: 28))
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 1, height: 1)
            HStack(spacing: 50) {
                Circle().fill(Theme.bubblegum).frame(width: 12, height: 12)
                Circle().fill(Theme.bubblegum).frame(width: 12, height: 12)
            }
            .offset(y: 6)
        }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }
}

/// The default end-of-day picture: a sleeping moon over hills.
struct MoonScene: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.night
                ForEach(0..<14, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: CGFloat(2 + i % 3), height: CGFloat(2 + i % 3))
                        .position(x: w * CGFloat((i * 37) % 100) / 100, y: h * CGFloat((i * 53) % 55) / 100)
                }
                Circle()
                    .fill(Color(hex: "FFF3B0"))
                    .overlay(Circle().stroke(Theme.ink, lineWidth: 8))
                    .frame(width: w * 0.62, height: w * 0.62)
                    .overlay {
                        VStack(spacing: w * 0.1) {
                            HStack(spacing: w * 0.1) {
                                sleepingEye(w)
                                sleepingEye(w)
                            }
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: 0))
                                p.addQuadCurve(to: CGPoint(x: w * 0.14, y: 0), control: CGPoint(x: w * 0.07, y: w * 0.07))
                            }
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .frame(width: w * 0.14, height: 10)
                        }
                    }
                    .position(x: w / 2, y: h * 0.39)
                Ellipse().fill(Color(hex: "2E5D4A")).frame(width: w * 1.1, height: h * 0.28).position(x: w * 0.2, y: h * 0.92)
                Ellipse().fill(Color(hex: "244A3C")).frame(width: w * 1.0, height: h * 0.26).position(x: w * 0.85, y: h * 0.97)
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Image de fin de journée : une lune qui dort")
    }

    private func sleepingEye(_ w: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 0.09, y: 0), control: CGPoint(x: w * 0.045, y: w * 0.035))
        }
        .stroke(Theme.ink, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        .frame(width: w * 0.09, height: 8)
    }
}

/// A transparent zone that counts the secret taps; taps elsewhere reset it.
struct SecretCorner: View {
    var onUnlock: () -> Void
    @State private var lock = CornerTapLock()

    var body: some View {
        Color.clear
            .frame(width: Theme.cornerSide, height: Theme.cornerSide)
            .contentShape(Rectangle())
            .onTapGesture {
                if lock.tap(inCorner: true) { onUnlock() }
            }
            .accessibilityHidden(true)
    }
}
