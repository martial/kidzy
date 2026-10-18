import SwiftUI

/// The way back from a toy in « Sketches for kids! »: a round white button with
/// a coral house, sitting on a soft blue lip (docs/design/sketches/Toy.dc.html).
struct HomeButton: View {
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Color(hex: "F04A43"))
                .frame(width: 58, height: 58)
        }
        .buttonStyle(HomeButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct HomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(Circle().fill(LinearGradient(colors: [.white, Color(hex: "F1F4FF")], startPoint: .top, endPoint: .bottom)))
            .contentShape(Circle())
            .offset(y: pressed ? 4 : 0)
            .background(Circle().fill(Color(hex: "C9D3EC")).offset(y: 6))
            .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.35).opacity(0.22), radius: 9, y: 12)
            .padding(.bottom, 6)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: pressed)
    }
}
