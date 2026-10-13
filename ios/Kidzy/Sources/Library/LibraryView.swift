import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    enum Cell: Identifiable {
        case collection(Collection)
        case sketch(ToyEntry)
        var id: String {
            switch self {
            case .collection(let c): return "c:" + c.id
            case .sketch(let s): return "s:" + s.id
            }
        }
    }

    private var cells: [Cell] {
        var out = model.collections.map(Cell.collection)
        if model.sketchesVisible { out += Toys.all.map(Cell.sketch) }
        return out
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky.ignoresSafeArea()
            if model.seaBackground {
                SeaSketchView(mode: .background).allowsHitTesting(false)
            }
            Cloud().offset(x: -24, y: 60)
            Cloud().scaleEffect(0.75).offset(x: 300, y: 700)
            GeometryReader { geo in
            let inner = TileMetrics.innerWidth(for: geo.size.width)
            ScrollView {
                VStack(spacing: 0) {
                    if cells.isEmpty {
                        VStack(spacing: 12) {
                            SunMascot()
                            Text(model.lastError.isEmpty ? "Pas encore de vidéos" : "Serveur introuvable")
                                .font(Theme.rounded(22))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.top, 120)
                    } else {
                        LazyVGrid(columns: columns, spacing: 30) {
                            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                                switch cell {
                                case .collection(let c):
                                    Button {
                                        Task { await model.open(c) }
                                    } label: {
                                        StickerTile(color: Color(hex: c.color), tilt: index % 2 == 0 ? -2 : 2) {
                                            RemoteImage(url: model.mediaURL(c.posterUrl))
                                                .frame(width: inner, height: inner)
                                        }
                                    }
                                    .buttonStyle(PressStyle())
                                    .accessibilityLabel("Collection \(c.title)")
                                case .sketch(let entry):
                                    Button {
                                        model.openSketch(entry.id)
                                    } label: {
                                        StickerTile(color: entry.color, tilt: index % 2 == 0 ? -2 : 2) {
                                            entry.sticker()
                                                .frame(width: inner, height: inner)
                                        }
                                    }
                                    .buttonStyle(PressStyle())
                                    .accessibilityLabel("Jouet : \(entry.title)")
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 60)
                        HStack {
                            SunMascot().padding(.leading, 10)
                            Spacer()
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                    }
                }
            }
            .scrollIndicators(.hidden)
            }
            SecretCorner { model.openGate(from: .library) }
        }
        .onAppear { OrientationLock.set(.portrait) }
        .task { await model.refresh() }
    }
}
