import SwiftUI

/// The parent page: hide toys, restore the purchase, the links and the mic line.
struct ParentView: View {
    @Environment(SketchesModel.self) private var model

    var body: some View {
        let store = model.store
        ParentScreen(title: String(localized: "parent.title"), onClose: { model.route = .picker }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "parent.toys")).font(Theme.rounded(17)).foregroundStyle(Theme.muted)
                ForEach(Toys.all) { entry in
                    Toggle(isOn: Binding(get: { !model.hidden.contains(entry.id) }, set: { model.setHidden(entry.id, !$0) })) {
                        HStack(spacing: 12) {
                            entry.sticker().frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.ink, lineWidth: 2.5))
                            Text(entry.title).font(Theme.rounded(18, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                    }
                    .tint(Theme.grass)
                }
            }
            Divider()
            Text(String(localized: store.isUnlocked ? "parent.unlocked" : "parent.locked"))
                .font(Theme.rounded(16, weight: .medium)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if !store.isUnlocked {
                Button(String(localized: "unlock.restore")) { Task { await store.restore() } }
                    .font(Theme.rounded(17, weight: .medium)).foregroundStyle(Theme.muted)
            }
            Divider()
            Link(String(localized: "unlock.privacy"), destination: Links.privacy)
                .font(Theme.rounded(17, weight: .medium)).foregroundStyle(Theme.ink)
            Link(String(localized: "parent.support"), destination: Links.support)
                .font(Theme.rounded(17, weight: .medium)).foregroundStyle(Theme.ink)
            Text(String(localized: "parent.mic"))
                .font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Text(String(localized: "parent.version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"))
                .font(Theme.rounded(13, weight: .medium)).foregroundStyle(Theme.muted)
        }
    }
}
