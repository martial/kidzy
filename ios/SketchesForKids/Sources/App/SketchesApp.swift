import SwiftUI

/// « Sketches for kids! »: the toys alone. A picker of stickers, each toy full
/// screen with a home sticker, and a parent area behind a sum.
@main
struct SketchesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SketchesModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    model.start()
                    GuitarSamples.preload()
                }
        }
    }
}

/// Portrait only (see `OrientationLock`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

struct RootView: View {
    @Environment(SketchesModel.self) private var model

    var body: some View {
        ZStack {
            switch model.route {
            case .picker:
                PickerView()
            case .toy(let id):
                ToyHost(id: id, chrome: .backSticker) { model.exitToy() }.id(id)
            case .gate(let target):
                ParentGateView(target: target)
            case .unlock(let id):
                UnlockView(toyID: id)
            case .parent:
                ParentView()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

/// Pages the parent may open; every link out of the app sits behind the gate.
enum Links {
    static let privacy = URL(string: "https://martial.github.io/kidzy/sketches/privacy.html")!
    static let support = URL(string: "mailto:martial@screen-club.com?subject=Sketches%20for%20kids")!
}
