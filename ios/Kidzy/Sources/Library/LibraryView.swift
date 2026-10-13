import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky.ignoresSafeArea()
            Cloud().offset(x: -24, y: 60)
            Cloud().scaleEffect(0.75).offset(x: 300, y: 700)
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        StarsRow(lit: model.stars)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(height: 70)
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
                                            .aspectRatio(1, contentMode: .fill)
                                    }
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel("Collection \(c.title)")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 36)
                        .padding(.bottom, 140)
                    }
                }
            }
            .scrollIndicators(.hidden)
            VStack {
                Spacer()
                HStack {
                    SunMascot().offset(x: 10, y: 30)
                    Spacer()
                }
            }
            .allowsHitTesting(false)
            SecretCorner { model.openGate(from: .library) }
        }
        .onAppear { Orientation.set(.portrait) }
        .task { await model.refresh() }
    }
}
