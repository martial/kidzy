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
                .onAppear { model.start() }
                .onChange(of: phase) { _, new in
                    model.scenePhaseChanged(active: new == .active)
                }
        }
    }
}

/// Keeps the library portrait and the player landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.mask
    }
}

@MainActor
enum Orientation {
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
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
                SketchHost(id: id).id(id)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
