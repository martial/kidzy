import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky.ignoresSafeArea()
            Cloud().offset(x: -24, y: 60)
            Cloud().scaleEffect(0.75).offset(x: 300, y: 700)
            GeometryReader { geo in
            let inner = TileMetrics.innerWidth(for: geo.size.width)
            ScrollView {
                VStack(spacing: 0) {
                    if model.collections.isEmpty {
                        VStack(spacing: 12) {
                            SunMascot()
                            Text(model.lastError.isEmpty ? "Pas encore de vidéos" : "Serveur introuvable")
                                .font(Theme.rounded(22))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.top, 120)
                    } else {
                        LazyVGrid(columns: columns, spacing: 30) {
                            ForEach(Array(model.collections.enumerated()), id: \.element.id) { index, c in
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
        .onAppear { Orientation.set(.portrait) }
        .task { await model.refresh() }
    }
}
