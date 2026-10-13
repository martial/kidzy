import UIKit

/// The orientations allowed right now. Each app's `AppDelegate` returns `mask`
/// from `supportedInterfaceOrientationsFor`; screens call `set` on appear.
@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ mask: UIInterfaceOrientationMask) {
        Self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
