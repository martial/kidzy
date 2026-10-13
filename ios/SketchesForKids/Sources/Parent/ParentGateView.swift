import SwiftUI

/// The parental gate: a sum of two digits, one of Apple's own examples. A
/// wrong answer shakes and draws a new sum; the close sticker goes back.
struct ParentGateView: View {
    let target: SketchesModel.GateTarget
    @Environment(SketchesModel.self) private var model
    @State private var a = Int.random(in: 2...9)
    @State private var b = Int.random(in: 2...9)
    @State private var answer = ""
    @State private var shaking = false

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["x", "0", "<"]]

    var body: some View {
        ParentScreen(title: String(localized: "gate.title"), onClose: { model.route = .picker }) {
            Text(String(localized: "gate.question \(a) \(b)"))
                .font(Theme.rounded(24)).foregroundStyle(Theme.ink)
            Text(answer.isEmpty ? " " : answer)
                .font(Theme.rounded(40)).foregroundStyle(Theme.ink)
                .frame(width: 120, height: 64)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.ink, lineWidth: 4))
                .offset(x: shaking ? -10 : 0)
            Text(String(localized: "gate.hint"))
                .font(Theme.rounded(15, weight: .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            VStack(spacing: 12) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { key in keyButton(key) }
                    }
                }
            }
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
            .frame(height: 58)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(key == "x" ? String(localized: "gate.close") : key == "<" ? String(localized: "gate.delete") : key)
    }

    private func press(_ key: String) {
        switch key {
        case "x":
            model.route = .picker
        case "<":
            if !answer.isEmpty { answer.removeLast() }
        default:
            answer += key
            let sum = a + b
            if Int(answer) == sum {
                model.gatePassed(target)
            } else if answer.count >= String(sum).count {
                withAnimation(.default.repeatCount(5, autoreverses: true).speed(4)) { shaking = true }
                Task {
                    try? await Task.sleep(for: .seconds(0.4))
                    shaking = false
                    answer = ""
                    a = Int.random(in: 2...9)
                    b = Int.random(in: 2...9)
                }
            }
        }
    }
}
