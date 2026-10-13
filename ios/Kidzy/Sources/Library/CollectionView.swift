import SwiftUI

struct CollectionView: View {
    let collection: Collection
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky.ignoresSafeArea()
            Cloud().offset(x: -40, y: 170)
            GeometryReader { geo in
            let inner = TileMetrics.innerWidth(for: geo.size.width)
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(Theme.ink).offset(x: 5, y: 5)
                        RemoteImage(url: model.mediaURL(collection.posterUrl), maxPixel: 200)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.ink, lineWidth: 6))
                    }
                    .frame(width: 78, height: 78)
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(Color(hex: collection.color)).overlay(Circle().stroke(Theme.ink, lineWidth: 4)).frame(width: 26, height: 26).offset(x: 6, y: 4)
                    }
                    .rotationEffect(.degrees(-4))
                    .padding(.top, 28)
                    .accessibilityLabel("Collection \(collection.title)")
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(Array(model.currentItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                model.play(item)
                            } label: {
                                StickerTile(color: Color(hex: collection.color), tilt: index % 2 == 0 ? -2 : 2, radius: 24, innerRadius: 14) {
                                    RemoteImage(url: model.mediaURL(item.thumbUrl))
                                        .frame(width: inner, height: inner * 9 / 16)
                                }
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(item.title)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 36)
                    .padding(.bottom, 140)
                }
            }
            .scrollIndicators(.hidden)
            }
            VStack {
                Spacer()
                StickerButton(systemImage: "house.fill", label: "Retour à la bibliothèque") { model.backToLibrary() }
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            SecretCorner { model.openGate(from: .library) }
        }
        .onAppear { Orientation.set(.portrait) }
    }
}
