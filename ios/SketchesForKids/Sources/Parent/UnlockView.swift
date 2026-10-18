import StoreKit
import SwiftUI

/// After the gate: the one purchase that unlocks every toy. The four toys it
/// opens, three promises, the App Store price, restore and privacy.
struct UnlockView: View {
    let toyID: String
    @Environment(SketchesModel.self) private var model
    @Environment(\.purchase) private var purchase
    @State private var busy = false

    var body: some View {
        let store = model.store
        GrownUpScreen(onClose: { model.route = .picker }) {
            ScrollView {
                VStack(spacing: 18) {
                    GrownUpCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 22, trailing: 14)) {
                        VStack(alignment: .leading, spacing: 14) {
                            ToyFan(ids: store.lockedToys.map(\.id))
                                .frame(height: 232)
                            VStack(alignment: .leading, spacing: 12) {
                                Text(String(localized: "unlock.title"))
                                    .font(Brand.font(31, .heavy, relativeTo: .largeTitle))
                                    .foregroundStyle(Brand.ink)
                                    .accessibilityAddTraits(.isHeader)
                                Text(String(localized: "unlock.body"))
                                    .font(Brand.font(17, .semibold))
                                    .foregroundStyle(Brand.inkSoft)
                                VStack(alignment: .leading, spacing: 8) {
                                    Tick(text: String(localized: "unlock.once"))
                                    Tick(text: String(localized: "unlock.family"))
                                    Tick(text: String(localized: "unlock.noads"))
                                }
                                .padding(.vertical, 2)
                                if let product = store.product {
                                    CoralButton(title: String(localized: "unlock.button \(product.displayPrice)")) {
                                        Task { await buy(product) }
                                    }
                                    .disabled(busy)
                                    .opacity(busy ? 0.6 : 1)
                                    .accessibilityIdentifier("unlock.buy")
                                } else {
                                    Text(String(localized: store.lastError == nil ? "unlock.loading" : "unlock.unavailable"))
                                        .font(Brand.font(16, .semibold))
                                        .foregroundStyle(Brand.inkSoft)
                                        .frame(maxWidth: .infinity, minHeight: 62)
                                }
                                if store.pending {
                                    Text(String(localized: "unlock.pending"))
                                        .font(Brand.font(16, .semibold))
                                        .foregroundStyle(Brand.inkSoft)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }
                                HStack(spacing: 26) {
                                    Button(String(localized: "unlock.restore")) {
                                        Task { await store.restore(); openIfUnlocked() }
                                    }
                                    Link(String(localized: "unlock.privacy"), destination: Links.privacy)
                                }
                                .font(Brand.font(16, .bold))
                                .foregroundStyle(Brand.link)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    Text(String(localized: "unlock.apple"))
                        .font(Brand.font(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Brand.nightText)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("unlock")
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

/// The locked toys fanned on a sunny panel, bobbing.
struct ToyFan: View {
    let ids: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    /// x, y (fractions of the panel), height (fraction), rotation, front-to-back order.
    private static let layout: [String: (CGFloat, CGFloat, CGFloat, Double, Double)] = [
        "tiles": (0.36, 0.36, 0.53, -6, 0),
        "guitar": (0.60, 0.45, 0.74, 7, 1),
        "paint": (0.20, 0.71, 0.48, -8, 2),
        "parrot": (0.79, 0.62, 0.63, 5, 3),
    ]

    var body: some View {
        GeometryReader { g in
            ZStack {
                ZStack {
                    LinearGradient(colors: [Brand.sun, Color(hex: "FFE07A")], startPoint: .top, endPoint: .bottom)
                    DotPattern(color: .white.opacity(0.35), spacing: 28, radius: 2.4)
                    LinearGradient(colors: [Color(red: 0.47, green: 0.24, blue: 0).opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                ForEach(ids.indices, id: \.self) { i in
                    let id = ids[i]
                    if let spot = Self.layout[id], let image = Brand.toyImage(id) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: g.size.height * spot.2)
                            .rotationEffect(.degrees(spot.3))
                            .shadow(color: Color(red: 0.47, green: 0.24, blue: 0).opacity(0.25), radius: 6, y: 8)
                            .position(x: g.size.width * spot.0, y: g.size.height * spot.1)
                            .offset(y: up ? (i % 2 == 0 ? -5 : 4) : 0)
                            .zIndex(spot.4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// A green tick and a short promise.
struct Tick: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Brand.leaf))
            Text(text)
                .font(Brand.font(17, .semibold))
                .foregroundStyle(Brand.ink)
        }
    }
}
