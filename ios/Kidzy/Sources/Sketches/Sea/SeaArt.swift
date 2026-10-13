import SwiftUI

/// The sticker-style drawings of the sea: boat, sun, cloud.
enum SeaArt {
    /// The boat, origin at the waterline under the mast, y down, before rotation.
    static func drawBoat(in gc: inout GraphicsContext, at origin: CGPoint, angle: Double, scale: CGFloat = 1) {
        var c = gc
        c.translateBy(x: origin.x, y: origin.y)
        c.rotate(by: .radians(-angle))
        c.scaleBy(x: scale, y: scale)
        var mast = Path()
        mast.addRect(CGRect(x: 2, y: -60, width: 4, height: 52))
        c.fill(mast, with: .color(Theme.ink))
        var sail = Path()
        sail.move(to: CGPoint(x: 4, y: -56))
        sail.addLine(to: CGPoint(x: 36, y: -12))
        sail.addLine(to: CGPoint(x: 4, y: -12))
        sail.closeSubpath()
        c.fill(sail, with: .color(.white))
        c.stroke(sail, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        var pennant = Path()
        pennant.move(to: CGPoint(x: 4, y: -60))
        pennant.addLine(to: CGPoint(x: 18, y: -55))
        pennant.addLine(to: CGPoint(x: 4, y: -50))
        pennant.closeSubpath()
        c.fill(pennant, with: .color(Theme.lemon))
        c.stroke(pennant, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        var hull = Path()
        hull.move(to: CGPoint(x: -45, y: -8))
        hull.addLine(to: CGPoint(x: 45, y: -8))
        hull.addQuadCurve(to: CGPoint(x: 30, y: 10), control: CGPoint(x: 44, y: 8))
        hull.addLine(to: CGPoint(x: -30, y: 10))
        hull.addQuadCurve(to: CGPoint(x: -45, y: -8), control: CGPoint(x: -44, y: 8))
        hull.closeSubpath()
        c.fill(hull, with: .color(Theme.coral))
        c.stroke(hull, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        let porthole = Path(ellipseIn: CGRect(x: -17, y: -5, width: 10, height: 10))
        c.fill(porthole, with: .color(Theme.lemon))
        c.stroke(porthole, with: .color(Theme.ink), lineWidth: 2)
    }

    /// The sun. `giggle` 0...1 bounces it and spins the rays; `warmth` 0...1 reddens it at sunset.
    static func drawSun(in gc: inout GraphicsContext, center: CGPoint, radius base: CGFloat, giggle: Double = 0, warmth: Double = 0) {
        let r = base * (1 + 0.25 * CGFloat(sin(giggle * .pi)))
        let spin = giggle * 2 * .pi
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 + spin
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + CGFloat(cos(a)) * (r + 12), y: center.y + CGFloat(sin(a)) * (r + 12)))
            ray.addLine(to: CGPoint(x: center.x + CGFloat(cos(a)) * (r + 26), y: center.y + CGFloat(sin(a)) * (r + 26)))
            gc.stroke(ray, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        gc.fill(disc, with: .color(Theme.lemon))
        if warmth > 0 { gc.fill(disc, with: .color(Theme.coral.opacity(0.55 * warmth))) }
        gc.stroke(disc, with: .color(Theme.ink), lineWidth: 5)
        if giggle > 0 {
            for dx in [-r * 0.32, r * 0.32] {
                var eye = Path()
                eye.move(to: CGPoint(x: center.x + dx - 6, y: center.y - r * 0.15))
                eye.addQuadCurve(to: CGPoint(x: center.x + dx + 6, y: center.y - r * 0.15), control: CGPoint(x: center.x + dx, y: center.y - r * 0.15 - 9))
                gc.stroke(eye, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        } else {
            for dx in [-r * 0.32, r * 0.32] {
                gc.fill(Path(ellipseIn: CGRect(x: center.x + dx - 4.5, y: center.y - r * 0.2 - 4.5, width: 9, height: 9)), with: .color(Theme.ink))
            }
        }
        var smile = Path()
        let open = CGFloat(0.65 + 0.3 * sin(giggle * .pi))
        smile.move(to: CGPoint(x: center.x - r * 0.4, y: center.y + r * 0.25))
        smile.addQuadCurve(to: CGPoint(x: center.x + r * 0.4, y: center.y + r * 0.25), control: CGPoint(x: center.x, y: center.y + r * open))
        gc.stroke(smile, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
    }

    static func drawStars(in gc: inout GraphicsContext, size: CGSize, below: CGFloat, alpha: Double) {
        guard alpha > 0.01 else { return }
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10000) / 10000
        }
        for _ in 0..<26 {
            let p = CGPoint(x: next() * size.width, y: next() * below * 0.9)
            let r = 1.5 + next() * 2
            gc.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(alpha * (0.6 + 0.4 * Double(next())))))
        }
    }

    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = min(1, max(0, t))
        let ca = UIColor(a), cb = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(.sRGB, red: Double(ar + (br - ar) * t), green: Double(ag + (bg - ag) * t), blue: Double(ab + (bb - ab) * t), opacity: 1)
    }

    static func drawCloud(in gc: inout GraphicsContext, at p: CGPoint, scale s: CGFloat = 1) {
        for (dx, dy, w, h) in [(-40.0, 8.0, 112.0, 44.0), (0, 0, 80, 52), (44, 10, 88, 40)] {
            let rect = CGRect(x: p.x + CGFloat(dx) * s - CGFloat(w) * s / 2, y: p.y + CGFloat(dy) * s - CGFloat(h) * s / 2, width: CGFloat(w) * s, height: CGFloat(h) * s)
            gc.fill(Path(ellipseIn: rect), with: .color(.white))
        }
    }
}

/// The library tile for the sea: a little sea with the boat, static.
struct SeaSticker: View {
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Theme.sky, .white]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.6)))
            SeaArt.drawSun(in: &gc, center: CGPoint(x: w * 0.78, y: h * 0.22), radius: w * 0.09)
            SeaArt.drawCloud(in: &gc, at: CGPoint(x: w * 0.22, y: h * 0.3), scale: w / 400)
            var water = Path()
            let rest = h * 0.66
            water.move(to: CGPoint(x: 0, y: rest))
            var x = 0.0
            while x <= w {
                water.addLine(to: CGPoint(x: x, y: rest + 6 * sin(x / w * 4 * .pi)))
                x += 4
            }
            var surface = water
            water.addLine(to: CGPoint(x: w, y: h))
            water.addLine(to: CGPoint(x: 0, y: h))
            water.closeSubpath()
            gc.fill(water, with: .color(Theme.oceanDeep))
            gc.stroke(surface, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            surface = Path()
            SeaArt.drawBoat(in: &gc, at: CGPoint(x: w * 0.45, y: rest + 2), angle: 0.08, scale: w / 230)
        }
    }
}
