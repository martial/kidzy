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
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if FrameTicker.on { FrameTicker() }
        }
        #endif
    }
}

#if DEBUG
/// `KIDZY_STORE_MEDIA=1` (ios/Tools/StoreMedia.py): a 3-point corner that changes by one
/// grey level every frame, hidden under the screen's rounded corner and cropped out of the
/// preview. The simulator's recorder shortens the time a screen stands still, which puts
/// the picture out of step with the sound; this keeps a frame coming.
struct FrameTicker: View {
    static let on = ProcessInfo.processInfo.environment["KIDZY_STORE_MEDIA"] == "1"

    var body: some View {
        TimelineView(.animation) { ctx in
            let odd = Int(ctx.date.timeIntervalSinceReferenceDate * 60) % 2 == 1
            Color(white: 1, opacity: odd ? 0.004 : 0.008)
                .frame(width: 3, height: 3)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

/// Pages the parent may open; every link out of the app sits behind the gate.
enum Links {
    static let privacy = URL(string: "https://martial.github.io/kidzy/sketches/privacy.html")!
    static let support = URL(string: "mailto:martial@screen-club.com?subject=Sketches%20for%20kids")!
}
