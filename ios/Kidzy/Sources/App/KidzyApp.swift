import SwiftUI

@main
struct KidzyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    model.start()
                    GuitarSamples.preload()
                }
                .onChange(of: phase) { _, new in
                    model.scenePhaseChanged(active: new == .active)
                }
        }
    }
}

/// Keeps the library portrait and the player landscape (see `OrientationLock`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.route {
            case .connecting:
                ConnectingView()
            case .pairing:
                PairingView()
            case .library:
                LibraryView()
            case .collection(let collection):
                CollectionView(collection: collection)
            case .player(let item):
                PlayerScreen(item: item).id(item.id)
            case .blocked:
                BlockedView()
            case .gate(let origin):
                ParentGateView(origin: origin)
            case .parent:
                ParentAreaView()
            case .sketch(let id):
                ToyHost(id: id, chrome: .secretCorner) { model.exitSketch() }.id(id)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
