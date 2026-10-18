import SwiftUI

/// The parental gate: « What is seven plus five? » in words, typed on a chunky
/// keypad. A wrong answer shakes and asks a new question; the close button goes back.
struct ParentGateView: View {
    let target: SketchesModel.GateTarget
    @Environment(SketchesModel.self) private var model
    @State private var question = GateQuestion.random()
    @State private var typed = ""
    @State private var shake = 0.0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "<"]

    var body: some View {
        GrownUpScreen(onClose: { model.route = .picker }) {
            ScrollView {
                ZStack(alignment: .top) {
                    if let parrot = Brand.toyImage("parrot") {
                        Image(uiImage: parrot)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150)
                            .rotationEffect(.degrees(-6))
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 10)
                            .accessibilityHidden(true)
                    }
                    card.padding(.top, 104)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("gate")
    }

    private var card: some View {
        GrownUpCard(padding: EdgeInsets(top: 26, leading: 22, bottom: 24, trailing: 22)) {
            VStack(spacing: 14) {
                Text(String(localized: "gate.title"))
                    .font(Brand.font(30, .heavy, relativeTo: .largeTitle))
                    .foregroundStyle(Brand.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(questionText)
                    .font(Brand.font(22, .bold, relativeTo: .title3))
                    .foregroundStyle(Brand.ink)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    digitBox(0)
                    digitBox(1)
                }
                .modifier(Shake(amount: shake))
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(typed.isEmpty ? String(localized: "gate.empty") : typed)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(keys.indices, id: \.self) { i in
                        key(keys[i])
                    }
                }
                Text(String(localized: "gate.hint"))
                    .font(Brand.font(15, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Brand.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The question with its two numbers coloured, in the interface language.
    private var questionText: AttributedString {
        let locale = GateQuestion.interfaceLocale
        let first = GateQuestion.words(question.a, locale: locale)
        let second = GateQuestion.words(question.b, locale: locale)
        var text = AttributedString(localized: "gate.question \(first) \(second)")
        if let r = text.range(of: first) { text[r].foregroundColor = Color(hex: "E2453C") }
        if let r = text.range(of: second, options: .backwards) { text[r].foregroundColor = Color(hex: "2F7FE0") }
        return text
    }

    private func digitBox(_ index: Int) -> some View {
        let chars = Array(typed)
        let value = index < chars.count ? String(chars[index]) : ""
        let active = index == chars.count
        return Text(value)
            .font(Brand.font(40, .heavy))
            .foregroundStyle(Brand.ink)
            .frame(width: 64, height: 72)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.key))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(active ? Brand.tangerine : Brand.keyLip, lineWidth: 3))
    }

    @ViewBuilder
    private func key(_ k: String) -> some View {
        if k.isEmpty {
            Color.clear.frame(height: 62)
        } else {
            Button {
                press(k)
            } label: {
                Group {
                    if k == "<" {
                        Image(systemName: "delete.left").font(.system(size: 24, weight: .bold))
                    } else {
                        Text(k).font(Brand.font(28, .bold))
                    }
                }
                .foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity, minHeight: 62)
            }
            .buttonStyle(LipStyle(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), fill: AnyShapeStyle(Brand.key), lip: Brand.keyLip))
            .accessibilityLabel(k == "<" ? String(localized: "gate.delete") : k)
        }
    }

    private func press(_ k: String) {
        if k == "<" {
            if !typed.isEmpty { typed.removeLast() }
            return
        }
        guard typed.count < 2 else { return }
        typed += k
        switch question.check(typed) {
        case true?:
            model.gatePassed(target)
        case false?:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            Task {
                try? await Task.sleep(for: .seconds(0.45))
                typed = ""
                question = GateQuestion.random()
            }
        case nil:
            break
        }
    }
}

/// A horizontal shake, driven by an animatable counter.
struct Shake: GeometryEffect {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 6), y: 0))
    }
}
