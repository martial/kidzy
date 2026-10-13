import SwiftUI

/// A full-screen toy. Titles are for the parent area; kid screens show no text.
struct SketchEntry: Identifiable {
    let id: String
    let title: String
    let makeView: () -> AnyView
}

@MainActor
enum Sketches {
    static let all: [SketchEntry] = [
        SketchEntry(id: "sea", title: "La mer") { AnyView(SeaSketchView()) },
        SketchEntry(id: "paint", title: "Peinture") { AnyView(PaintSketchView()) },
        SketchEntry(id: "tiles", title: "Formes") { AnyView(TilesSketchView()) },
    ]

    static func entry(_ id: String) -> SketchEntry? { all.first { $0.id == id } }
}
