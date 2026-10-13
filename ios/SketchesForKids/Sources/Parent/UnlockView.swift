import StoreKit
import SwiftUI

/// After the gate: the one purchase that unlocks every toy.
struct UnlockView: View {
    let toyID: String
    @Environment(SketchesModel.self) private var model
    @Environment(\.purchase) private var purchase
    @State private var busy = false

    var body: some View {
        let store = model.store
        ParentScreen(title: String(localized: "unlock.title"), onClose: { model.route = .picker }) {
            if let entry = Toys.entry(toyID) {
                StickerTile(color: entry.color, tilt: -3, radius: 32, innerRadius: 22) {
                    entry.sticker().frame(width: 150, height: 150)
                }
                .frame(width: 178, height: 178)
                .padding(.vertical, 8)
            }
            Text(store.lockedToys.map { String(localized: $0.title) }.joined(separator: " · "))
                .font(Theme.rounded(18, weight: .medium)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if let product = store.product {
                Text("\(product.displayPrice) · \(String(localized: "unlock.once"))")
                    .font(Theme.rounded(22)).foregroundStyle(Theme.ink)
                BigButton(title: String(localized: "unlock.button")) { Task { await buy(product) } }
                    .disabled(busy)
                    .opacity(busy ? 0.6 : 1)
            } else {
                Text(String(localized: store.lastError == nil ? "unlock.loading" : "unlock.unavailable"))
                    .font(Theme.rounded(16, weight: .medium)).foregroundStyle(Theme.muted)
            }
            if store.pending {
                Text(String(localized: "unlock.pending"))
                    .font(Theme.rounded(16, weight: .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            Button(String(localized: "unlock.restore")) { Task { await store.restore(); openIfUnlocked() } }
                .font(Theme.rounded(17, weight: .medium)).foregroundStyle(Theme.muted)
            Link(String(localized: "unlock.privacy"), destination: Links.privacy)
                .font(Theme.rounded(17, weight: .medium)).foregroundStyle(Theme.muted)
        }
        .onChange(of: store.isUnlocked) { _, _ in openIfUnlocked() }
    }

    private func buy(_ product: Product) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await purchase(product)
            await model.store.handle(purchase: result)
        } catch {
            return
        }
        openIfUnlocked()
    }

    private func openIfUnlocked() {
        if model.store.isUnlocked, model.route == .unlock(toyID) { model.route = .toy(toyID) }
    }
}
