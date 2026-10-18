import SwiftUI
import UIKit

/// The « Sketches for kids! » look (docs/design/sketches, Brand.dc.html): a sunny
/// wall, a white toy cabinet, a night-blue grown-up zone, chunky buttons, Baloo 2.
enum Brand {
    static let sun = Color(hex: "FFC530")
    static let sunLight = Color(hex: "FFD95C")
    static let tangerine = Color(hex: "FF9F12")
    static let tangerineLight = Color(hex: "FFB21F")
    static let garlandString = Color(hex: "C97A00")
    static let coral = Color(hex: "F04A43")
    static let coralLight = Color(hex: "FF6A5E")
    static let coralLip = Color(hex: "C8322C")
    static let ink = Color(hex: "1F2A44")
    static let inkSoft = Color(hex: "4A5878")
    static let nightTop = Color(hex: "2A3768")
    static let nightBottom = Color(hex: "3D57A6")
    static let nightText = Color(hex: "DCE4FF")
    static let cabinet = Color(hex: "F4F0FA")
    static let cabinetLip = Color(hex: "E6DFF0")
    static let key = Color(hex: "F1F4FF")
    static let keyLip = Color(hex: "D3DAF0")
    static let cardLip = Color(hex: "C6D0EE")
    static let closeLip = Color(hex: "B9C4E6")
    static let wallButtonLip = Color(hex: "E5A80E")
    static let leaf = Color(hex: "5FD068")
    static let link = Color(hex: "3D57A6")
    static let divider = Color(hex: "EEF1FA")

    enum Weight {
        case semibold
        case bold
        case heavy
    }

    /// Baloo 2 (bundled, OFL), scaled with Dynamic Type around `size`.
    static func font(_ size: CGFloat, _ weight: Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .semibold: "Baloo2-SemiBold"
        case .bold: "Baloo2-Bold"
        case .heavy: "Baloo2-ExtraBold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// A 3D toy from Resources/Toys3D (`toy3d-<id>.png`).
    static func toyImage(_ id: String) -> UIImage? { UIImage(named: "toy3d-\(id)") }
}

/// A grid of soft dots, the wallpaper of both backgrounds.
struct DotPattern: View {
    var color: Color
    var spacing: CGFloat
    var radius: CGFloat

    var body: some View {
        Canvas { gc, size in
            var path = Path()
            var y = spacing / 2 - 2
            while y < size.height {
                var x = spacing / 2 - 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
                    x += spacing
                }
                y += spacing
            }
            gc.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

/// The kid side: a sunny yellow wall with polka dots and a soft light from above.
struct SunnyWall: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.sun, Brand.sunLight], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.72))
            DotPattern(color: .white.opacity(0.32), spacing: 32, radius: 2.6)
            RadialGradient(colors: [.white.opacity(0.5), .white.opacity(0)], center: .top, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// The grown-up side: calm night blue, faint dots, a glow from above.
struct NightSky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.nightTop, Brand.nightBottom], startPoint: .top, endPoint: .bottom)
            DotPattern(color: .white.opacity(0.10), spacing: 44, radius: 1.6)
            RadialGradient(colors: [Color(red: 0.47, green: 0.63, blue: 1).opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// The party garland across the top of the wall, ending on a pin at `end` (fraction of the width).
struct Garland: View {
    var end: CGFloat = 0.785
    private static let colors = ["FF6B5B", "4DA3FF", "FFFFFF", "5FD068", "B48CFF", "FF8FB1", "4DA3FF", "FF6B5B", "FFFFFF"].map { Color(hex: $0) }

    var body: some View {
        Canvas { gc, size in
            let w = size.width
            let p0 = CGPoint(x: -6, y: 18), c = CGPoint(x: w * 0.385, y: 70), p1 = CGPoint(x: w * end, y: 30)
            func point(_ t: CGFloat) -> CGPoint {
                CGPoint(x: (1 - t) * (1 - t) * p0.x + 2 * (1 - t) * t * c.x + t * t * p1.x,
                        y: (1 - t) * (1 - t) * p0.y + 2 * (1 - t) * t * c.y + t * t * p1.y)
            }
            func slope(_ t: CGFloat) -> CGFloat {
                let dx = 2 * (1 - t) * (c.x - p0.x) + 2 * t * (p1.x - c.x)
                let dy = 2 * (1 - t) * (c.y - p0.y) + 2 * t * (p1.y - c.y)
                return atan2(dy, dx)
            }
            var string = Path()
            string.move(to: p0)
            string.addQuadCurve(to: p1, control: c)
            gc.stroke(string, with: .color(Brand.garlandString), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let n = Self.colors.count
            for (i, color) in Self.colors.enumerated() {
                let t = 0.06 + CGFloat(i) * (0.88 / CGFloat(n - 1))
                var flag = gc
                let p = point(t)
                flag.translateBy(x: p.x, y: p.y)
                flag.rotate(by: .radians(slope(t)))
                var tri = Path()
                tri.move(to: CGPoint(x: -13, y: 0))
                tri.addLine(to: CGPoint(x: 13, y: 0))
                tri.addLine(to: CGPoint(x: 0, y: 30))
                tri.closeSubpath()
                flag.fill(tri, with: .color(color))
            }
            gc.fill(Path(ellipseIn: CGRect(x: p1.x - 5, y: p1.y - 5, width: 10, height: 10)), with: .color(Brand.garlandString))
        }
        .frame(height: 100)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A chunky button: the shape sits on a darker lip and sinks into it when pressed.
struct LipStyle<S: Shape>: ButtonStyle {
    var shape: S
    var fill: AnyShapeStyle
    var lip: Color
    var depth: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(shape.fill(fill))
            .contentShape(shape)
            .offset(y: pressed ? depth * 0.7 : 0)
            .background(shape.fill(lip).offset(y: depth))
            .padding(.bottom, depth)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: pressed)
    }
}

/// A round white button with a symbol (parent, close).
struct RoundButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 48
    var lip: Color = Brand.closeLip
    var tint: Color = Brand.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
        .buttonStyle(LipStyle(shape: Circle(), fill: AnyShapeStyle(LinearGradient(colors: [.white, Brand.key], startPoint: .top, endPoint: .bottom)), lip: lip))
        .accessibilityLabel(label)
    }
}

/// The big coral call to action.
struct CoralButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Brand.font(23, .heavy, relativeTo: .title3))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 62)
        }
        .buttonStyle(LipStyle(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), fill: AnyShapeStyle(LinearGradient(colors: [Brand.coralLight, Brand.coral], startPoint: .top, endPoint: .bottom)), lip: Brand.coralLip, depth: 6))
    }
}

/// The white card of the grown-up pages.
struct GrownUpCard<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white))
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Brand.cardLip).offset(y: 8))
            .shadow(color: Color(red: 0.04, green: 0.08, blue: 0.24).opacity(0.3), radius: 18, y: 14)
    }
}

/// A grown-up page: night sky, a close button top-right, the content below.
struct GrownUpScreen<Content: View>: View {
    var title: String?
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            NightSky()
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    if let title {
                        Text(title)
                            .font(Brand.font(30, .heavy, relativeTo: .largeTitle))
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    RoundButton(systemImage: "xmark", label: String(localized: "gate.close"), action: onClose)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                content
            }
        }
        .onAppear { OrientationLock.set(.portrait) }
    }
}
