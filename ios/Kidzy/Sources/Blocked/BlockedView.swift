import SwiftUI

/// Finished for today: the parent's picture (or the moon), nothing else.
/// Only the secret corner and the PIN lead out.
struct BlockedView: View {
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
            } else {
                MoonScene()
            }
            SecretCorner { model.openGate(from: .blocked) }
            if model.sketchesVisible {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(Toys.all.reversed()) { entry in
                                StickerButton(size: 48, systemImage: entry.symbol, label: String(localized: entry.title)) { model.openSketch(entry.id) }
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .onAppear { OrientationLock.set(.portrait) }
        .task {
            if let url = model.mediaURL("/api/finished-image") {
                image = await ImageStore.shared.image(for: url, maxPixel: 2400)
            }
        }
    }
}
