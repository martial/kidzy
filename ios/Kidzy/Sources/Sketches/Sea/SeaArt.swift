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

    static func drawSun(in gc: inout GraphicsContext, center: CGPoint, radius r: CGFloat) {
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + CGFloat(cos(a)) * (r + 12), y: center.y + CGFloat(sin(a)) * (r + 12)))
            ray.addLine(to: CGPoint(x: center.x + CGFloat(cos(a)) * (r + 26), y: center.y + CGFloat(sin(a)) * (r + 26)))
            gc.stroke(ray, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        gc.fill(disc, with: .color(Theme.lemon))
        gc.stroke(disc, with: .color(Theme.ink), lineWidth: 5)
        for dx in [-r * 0.32, r * 0.32] {
            gc.fill(Path(ellipseIn: CGRect(x: center.x + dx - 4.5, y: center.y - r * 0.2 - 4.5, width: 9, height: 9)), with: .color(Theme.ink))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: center.x - r * 0.4, y: center.y + r * 0.25))
        smile.addQuadCurve(to: CGPoint(x: center.x + r * 0.4, y: center.y + r * 0.25), control: CGPoint(x: center.x, y: center.y + r * 0.65))
        gc.stroke(smile, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
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
