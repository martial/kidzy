import SwiftUI

/// Hosts a toy full screen, portrait, screen kept awake. Kidzy leaves by the
/// secret corner (four taps top-left); « Sketches for kids! » shows a home
/// sticker. A toy that wants to leave on its own calls `\.toyExit`.
struct ToyHost: View {
    enum Chrome {
        case secretCorner
        case backSticker
    }

    let id: String
    var chrome: Chrome = .secretCorner
    let onExit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky.ignoresSafeArea()
            if let entry = Toys.entry(id) {
                entry.makeView()
                    .ignoresSafeArea()
                    .environment(\.toyExit, onExit)
            }
        }
        // The way out sits over the toy, never inside it: whatever the toy does
        // with touches (drags, taps, a UIKit Metal view), the exit is hit first.
        .overlay(alignment: .topLeading) {
            exit.zIndex(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toy.\(id)")
        .onAppear {
            OrientationLock.set(.portrait)
            UIApplication.shared.isIdleTimerDisabled = true
            if Toys.entry(id) == nil { onExit() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var exit: some View {
        switch chrome {
        case .secretCorner:
            SecretCorner(onUnlock: onExit)
        case .backSticker:
            StickerButton(size: 56, systemImage: "house.fill", label: String(localized: "toy.back", defaultValue: "Back to the toys", table: "Toys"), action: onExit)
                .accessibilityIdentifier("toy.back")
                .padding(.leading, 16)
                .padding(.top, 12)
        }
    }
}

extension EnvironmentValues {
    /// Set by `ToyHost`: a toy calls it to leave by itself (idle for five minutes).
    @Entry var toyExit: () -> Void = {}
}
