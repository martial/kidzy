import SwiftUI

/// The home: one sticker per toy, a lock on the ones behind the purchase, the
/// sun, and a small parent sticker that leads to the gate. No text.
struct PickerView: View {
    @Environment(SketchesModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        GeometryReader { geo in
            let columns = max(2, Int(geo.size.width / 200))
            let gap = 20.0, margin = 24.0
            let tile = (geo.size.width - margin * 2 - gap * Double(columns - 1)) / Double(columns)
            let inner = tile - 28
            ZStack(alignment: .topTrailing) {
                Theme.sky.ignoresSafeArea()
                Cloud().offset(x: -24, y: 60)
                Cloud().scaleEffect(0.75).offset(x: geo.size.width - 90, y: geo.size.height - 150)
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: 30) {
                            ForEach(Array(model.visibleToys.enumerated()), id: \.element.id) { index, entry in
                                let locked = !model.store.isAvailable(entry.id)
                                Button {
                                    model.tapped(entry)
                                } label: {
                                    StickerTile(color: entry.color, tilt: index % 2 == 0 ? -2 : 2) {
                                        entry.sticker().frame(width: inner, height: inner)
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if locked { LockBadge().offset(x: 8, y: 8) }
                                    }
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel(locked ? String(localized: "picker.locked \(String(localized: entry.title))") : String(localized: entry.title))
                            }
                        }
                        .padding(.horizontal, margin)
                        .padding(.top, 72)
                        HStack {
                            SunMascot().padding(.leading, 10)
                            Spacer()
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                }
                StickerButton(size: 44, systemImage: "person.fill", label: String(localized: "picker.parent")) {
                    model.route = .gate(.parent)
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picker")
        .onAppear { OrientationLock.set(.portrait) }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await model.store.refresh() } }
        }
    }
}

/// The lemon lock on a toy that waits behind the purchase; it covers the tile's colour dot.
struct LockBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.lemon).overlay(Circle().stroke(Theme.ink, lineWidth: 4))
            Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}
