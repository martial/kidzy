import SwiftUI

/// A full-screen toy, shared by Kidzy and « Sketches for kids! ». Titles are
/// for parents; kid screens show no text.
struct ToyEntry: Identifiable {
    let id: String
    let title: String
    /// The tile's colour in a library or picker.
    let color: Color
    /// An SF Symbol for small stickers (the moon screen).
    let symbol: String
    /// The drawing inside the tile.
    let sticker: () -> AnyView
    let makeView: () -> AnyView
}

@MainActor
enum Toys {
    static let all: [ToyEntry] = [
        ToyEntry(id: "sea", title: "La mer", color: Theme.ocean, symbol: "sailboat.fill", sticker: { AnyView(SeaSticker()) }, makeView: { AnyView(SeaSketchView()) }),
        ToyEntry(id: "paint", title: "Peinture", color: Theme.coral, symbol: "paintbrush.pointed.fill", sticker: { AnyView(PaintSticker()) }, makeView: { AnyView(PaintSketchView()) }),
        ToyEntry(id: "tiles", title: "Formes", color: Theme.lemon, symbol: "square.grid.3x3.fill", sticker: { AnyView(TilesSticker()) }, makeView: { AnyView(TilesSketchView()) }),
        ToyEntry(id: "animals", title: "Animaux", color: Theme.grass, symbol: "pawprint.fill", sticker: { AnyView(AnimalsSticker()) }, makeView: { AnyView(AnimalsSketchView()) }),
        ToyEntry(id: "guitar", title: "Guitare", color: Color(hex: "FFA62B"), symbol: "guitars.fill", sticker: { AnyView(GuitarSticker()) }, makeView: { AnyView(GuitarSketchView()) }),
        ToyEntry(id: "parrot", title: "Perroquet", color: Color(hex: "9B5DE5"), symbol: "bird.fill", sticker: { AnyView(ParrotSticker()) }, makeView: { AnyView(ParrotSketchView()) }),
    ]

    static func entry(_ id: String) -> ToyEntry? { all.first { $0.id == id } }
}
