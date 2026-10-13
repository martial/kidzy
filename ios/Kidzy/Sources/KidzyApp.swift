import SwiftUI

@main
struct KidzyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Kidzy")
            .font(.largeTitle.bold())
    }
}
