import SwiftUI

/// The sticker-album look of the mock-ups (docs/design).
enum Theme {
    static let sky = Color(hex: "BFE3FF")
    static let ink = Color(hex: "1F2A44")
    static let paper = Color.white
    static let lemon = Color(hex: "FFD23F")
    static let coral = Color(hex: "FF6B6B")
    static let bubblegum = Color(hex: "FF8FAB")
    static let grass = Color(hex: "5FD068")
    static let field = Color(hex: "F1F6FF")
    static let starOff = Color(hex: "DCE6F2")
    static let starOffStroke = Color(hex: "9FB0C8")
    static let night = Color(hex: "232B4E")
    static let muted = Color(hex: "4A5878")

    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The secret corner: 96 × 96 points at the top left.
    static let cornerSide: CGFloat = 96
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
