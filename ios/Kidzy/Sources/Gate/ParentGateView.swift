import SwiftUI

/// The keypad after the secret taps. The PIN is checked by the server.
struct ParentGateView: View {
    let origin: AppModel.GateOrigin
    @Environment(AppModel.self) private var model

    var body: some View {
        PinKeypad(title: "Code parent", onClose: { model.closeGate(origin) }) { pin in
            await model.unlock(pin: pin)
        }
        .onAppear { Orientation.set(.portrait) }
    }
}

/// A shared keypad: dots, digits, close and delete. Submits at 4, 5 and 6 digits.
struct PinKeypad: View {
    let title: String
    var subtitle: String = ""
    let onClose: () -> Void
    let submit: (String) async -> Bool
    @State private var entry = PinEntry()
    @State private var shaking = false
    @State private var busy = false

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["x", "0", "<"]]

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Circle().fill(Theme.sky.opacity(0.18)).frame(width: 240).offset(x: -140, y: -330)
            Circle().fill(Theme.sky.opacity(0.18)).frame(width: 280).offset(x: 150, y: 320)
            VStack(spacing: 22) {
                Text(title).font(Theme.rounded(30)).foregroundStyle(Theme.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.rounded(16, weight: .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                HStack(spacing: 14) {
                    ForEach(0..<max(4, entry.count), id: \.self) { i in
                        Circle()
                            .strokeBorder(Theme.ink, lineWidth: 3)
                            .background(Circle().fill(i < entry.count ? Theme.ink : .clear))
                            .frame(width: 20, height: 20)
                    }
                }
                .offset(x: shaking ? -10 : 0)
                .accessibilityLabel("\(entry.count) chiffres saisis")
                VStack(spacing: 12) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { key in
                                keyButton(key)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.sky, lineWidth: 6))
            .padding(.horizontal, 30)
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.ink).offset(x: 4, y: 4)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(key == "x" || key == "<" ? Theme.paper : Theme.field)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.ink, lineWidth: 4))
                switch key {
                case "x": Image(systemName: "xmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                case "<": Image(systemName: "delete.left").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                default: Text(key).font(Theme.rounded(30)).foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .accessibilityLabel(key == "x" ? "Fermer" : key == "<" ? "Effacer" : key)
    }

    private func press(_ key: String) {
        switch key {
        case "x":
            onClose()
        case "<":
            entry.deleteLast()
        default:
            guard let c = key.first, entry.append(c) else { return }
            let pin = entry.digits
            busy = true
            Task {
                let ok = await submit(pin)
                busy = false
                if !ok {
                    withAnimation(.default.repeatCount(5, autoreverses: true).speed(4)) { shaking = true }
                    try? await Task.sleep(for: .seconds(0.4))
                    shaking = false
                    if entry.isFull { entry.clear() }
                }
            }
        }
    }
}
