import SwiftUI

/// Hosts a sketch full screen, locked like the player: four taps top-left leave.
struct SketchHost: View {
    let id: String
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky.ignoresSafeArea()
            if let entry = Sketches.entry(id) {
                entry.makeView().ignoresSafeArea()
            }
            SecretCorner { model.exitSketch() }
        }
        .onAppear {
            Orientation.set(.portrait)
            UIApplication.shared.isIdleTimerDisabled = true
            if Sketches.entry(id) == nil { model.exitSketch() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
