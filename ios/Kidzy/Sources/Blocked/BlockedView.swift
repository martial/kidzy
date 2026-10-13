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
                        HStack(spacing: 16) {
                            StickerButton(size: 64, systemImage: "paintbrush.pointed.fill", label: "Peindre") { model.openSketch("paint") }
                            StickerButton(size: 64, systemImage: "sailboat.fill", label: "Jouer avec la mer") { model.openSketch("sea") }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .onAppear { Orientation.set(.portrait) }
        .task {
            if let url = model.mediaURL("/api/finished-image") {
                image = await ImageStore.shared.image(for: url, maxPixel: 2400)
            }
        }
    }
}
