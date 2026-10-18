import SwiftUI

/// The parents page: a switch per toy, the purchase, restore, the links, the mic line.
struct ParentView: View {
    @Environment(SketchesModel.self) private var model
    @State private var showLicenses = false

    var body: some View {
        let store = model.store
        GrownUpScreen(title: String(localized: "parent.title"), onClose: { model.route = .picker }) {
            ScrollView {
                VStack(spacing: 18) {
                    GrownUpCard(padding: EdgeInsets(top: 14, leading: 18, bottom: 10, trailing: 18)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "parent.toys"))
                                .font(Brand.font(14, .bold, relativeTo: .footnote))
                                .foregroundStyle(Brand.inkSoft)
                            ForEach(Toys.all) { entry in
                                Toggle(isOn: Binding(get: { !model.hidden.contains(entry.id) }, set: { model.setHidden(entry.id, !$0) })) {
                                    HStack(spacing: 12) {
                                        ToyThumb(id: entry.id)
                                        Text(entry.title)
                                            .font(Brand.font(18, .bold))
                                            .foregroundStyle(Brand.ink)
                                    }
                                }
                                .tint(Brand.leaf)
                                .frame(minHeight: 50)
                            }
                        }
                    }
                    if store.isUnlocked {
                        GrownUpCard {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Brand.leaf))
                                Text(String(localized: "parent.unlocked"))
                                    .font(Brand.font(18, .bold))
                                    .foregroundStyle(Brand.ink)
                            }
                        }
                    } else {
                        Button {
                            model.route = .unlock(store.lockedToys.first?.id ?? "parrot")
                        } label: {
                            GrownUpCard(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        if let guitar = Brand.toyImage("guitar") {
                                            Image(uiImage: guitar).resizable().scaledToFit().frame(height: 50).rotationEffect(.degrees(-10)).offset(x: -10)
                                        }
                                        if let parrot = Brand.toyImage("parrot") {
                                            Image(uiImage: parrot).resizable().scaledToFit().frame(height: 44).offset(x: 10, y: 4)
                                        }
                                    }
                                    .frame(width: 64, height: 52)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(String(localized: "parent.unlock.title"))
                                            .font(Brand.font(19, .heavy))
                                            .foregroundStyle(Brand.ink)
                                        Text(String(localized: "parent.unlock.sub"))
                                            .font(Brand.font(15, .semibold))
                                            .foregroundStyle(Brand.inkSoft)
                                    }
                                    Spacer(minLength: 4)
                                    if let product = store.product {
                                        Text(product.displayPrice)
                                            .font(Brand.font(16, .heavy))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Brand.coral))
                                            .background(Capsule().fill(Brand.coralLip).offset(y: 3))
                                    }
                                }
                            }
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("parent.unlock")
                    }
                    #if DEBUG
                    GrownUpCard {
                        Toggle(isOn: Binding(get: { store.testUnlock }, set: { store.testUnlock = $0 })) {
                            Text(verbatim: "Debug: all toys open (test builds only)")
                                .font(Brand.font(16, .bold))
                                .foregroundStyle(Brand.ink)
                        }
                        .tint(Brand.tangerine)
                    }
                    #endif
                    GrownUpCard(padding: EdgeInsets(top: 6, leading: 18, bottom: 14, trailing: 18)) {
                        VStack(alignment: .leading, spacing: 0) {
                            if !store.isUnlocked {
                                row(String(localized: "unlock.restore")) { Task { await store.restore() } }
                                Divider().overlay(Brand.divider)
                            }
                            Link(destination: Links.privacy) { rowLabel(String(localized: "parent.privacy")) }
                            Divider().overlay(Brand.divider)
                            Link(destination: Links.support) { rowLabel(String(localized: "parent.support")) }
                            Divider().overlay(Brand.divider)
                            row(String(localized: "parent.licenses")) { showLicenses = true }
                            Text(String(localized: "parent.mic") + " " + String(localized: "parent.version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"))
                                .font(Brand.font(14, .semibold, relativeTo: .footnote))
                                .foregroundStyle(Brand.inkSoft)
                                .padding(.top, 8)
                        }
                    }
                    if let logo = UIImage(named: "logo") {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 190)
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
                            .padding(.top, 8)
                            .accessibilityLabel("Sketches for kids!")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("parent")
        .sheet(isPresented: $showLicenses) { LicensesView() }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title) }
    }

    private func rowLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Brand.font(18, .bold))
                .foregroundStyle(Brand.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.inkSoft)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// A toy's 3D image on a small square of its cubby colour.
struct ToyThumb: View {
    let id: String

    var body: some View {
        let style = CubbyStyle.for(id)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [style.top.opacity(0.8), style.bottom], startPoint: .top, endPoint: .bottom))
            if let image = Brand.toyImage(id) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 36, maxHeight: 36).padding(.bottom, 3)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

/// The open-source works the app ships, with their licences (`Licenses.txt`, from
/// `ios/scripts/make-licenses.sh`).
struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss
    private let text: String = {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .navigationTitle(String(localized: "parent.licenses"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "gate.close"))
                }
            }
        }
    }
}
