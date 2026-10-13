import SwiftUI

/// The parent pages' frame: ink background, a paper card, a close sticker.
struct ParentScreen<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Circle().fill(Theme.sky.opacity(0.18)).frame(width: 240).offset(x: -140, y: -330)
            Circle().fill(Theme.sky.opacity(0.18)).frame(width: 280).offset(x: 150, y: 320)
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text(title).font(Theme.rounded(28)).foregroundStyle(Theme.ink)
                        Spacer()
                        StickerButton(size: 44, systemImage: "xmark", label: String(localized: "gate.close"), action: onClose)
                    }
                    content
                }
                .padding(22)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.sky, lineWidth: 6))
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
        }
        .onAppear { OrientationLock.set(.portrait) }
    }
}

/// A big sticker-style button for the parent pages.
struct BigButton: View {
    let title: String
    var color: Color = Theme.lemon
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.ink).offset(x: 5, y: 5)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(color)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.ink, lineWidth: 4))
                Text(title).font(Theme.rounded(22)).foregroundStyle(Theme.ink).padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
        }
        .buttonStyle(PressStyle())
    }
}
