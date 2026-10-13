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
            switch chrome {
            case .secretCorner:
                SecretCorner(onUnlock: onExit)
            case .backSticker:
                StickerButton(size: 52, systemImage: "house.fill", label: "Retour", action: onExit)
                    .padding(16)
            }
        }
        .onAppear {
            OrientationLock.set(.portrait)
            UIApplication.shared.isIdleTimerDisabled = true
            if Toys.entry(id) == nil { onExit() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension EnvironmentValues {
    /// Set by `ToyHost`: a toy calls it to leave by itself (idle for five minutes).
    @Entry var toyExit: () -> Void = {}
}
