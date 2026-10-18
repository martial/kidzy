import SwiftUI
import UIKit

/// The home: a white toy cabinet on a sunny wall, one coloured cubby per toy,
/// each toy a 3D toy that bobs; locked toys stay still with a lock badge and
/// lead to the gate. A small parent button top-right. No text.
struct PickerView: View {
    @Environment(SketchesModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let floor = min(84, h * 0.1)
            let top = min(110, max(84, h * 0.114))
            let toys = model.visibleToys
            let rows = max(1, (toys.count + 1) / 2)
            let gap: CGFloat = 13, padTop: CGFloat = 13, padBottom: CGFloat = 22
            let room: CGFloat = h - top - floor + 6 - padTop - padBottom - gap * CGFloat(rows - 1)
            let cubbyH: CGFloat = min(280, room / CGFloat(rows))
            let cabinetH: CGFloat = padTop + padBottom + cubbyH * CGFloat(rows) + gap * CGFloat(rows - 1)
            ZStack(alignment: .top) {
                SunnyWall()
                Garland()
                    .frame(width: w)
                // the floor and the cabinet's shadow on it
                VStack(spacing: 0) {
                    Spacer()
                    ZStack(alignment: .top) {
                        LinearGradient(colors: [Brand.tangerineLight, Brand.tangerine], startPoint: .top, endPoint: .bottom)
                        Rectangle().fill(.white.opacity(0.35)).frame(height: 3)
                        Ellipse()
                            .fill(RadialGradient(colors: [Color(red: 0.59, green: 0.27, blue: 0).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: w * 0.45))
                            .frame(width: w - 68, height: 26)
                            .offset(y: 2)
                    }
                    .frame(height: floor)
                }
                cabinet(toys: toys, cubbyH: cubbyH, gap: gap, padTop: padTop, padBottom: padBottom)
                    .frame(width: w - 28, height: cabinetH)
                    .position(x: w / 2, y: h - floor + 10 - cabinetH / 2)
                HStack {
                    Spacer()
                    RoundButton(systemImage: "person.fill", label: String(localized: "picker.parent"), lip: Brand.wallButtonLip) {
                        model.route = .gate(.parent)
                    }
                    .accessibilityIdentifier("picker.parent")
                    .padding(.trailing, 16)
                }
                .padding(.top, 18)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picker")
        .onAppear { OrientationLock.set(.portrait) }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await model.store.refresh() } }
        }
    }

    private func cabinet(toys: [ToyEntry], cubbyH: CGFloat, gap: CGFloat, padTop: CGFloat, padBottom: CGFloat) -> some View {
        let columns = [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)]
        return LazyVGrid(columns: columns, spacing: gap) {
            ForEach(Array(toys.enumerated()), id: \.element.id) { index, entry in
                let locked = !model.store.isAvailable(entry.id)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.tapped(entry)
                } label: {
                    Cubby(style: CubbyStyle.for(entry.id), locked: locked, delay: Double(index) * 0.4)
                        .frame(height: cubbyH)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(locked ? String(localized: "picker.locked \(String(localized: entry.title))") : String(localized: entry.title))
                .accessibilityIdentifier("toy.tile.\(entry.id)")
            }
            if toys.count % 2 == 1 {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Brand.cabinet)
                    .overlay(CubbyShade())
                    .frame(height: cubbyH)
                    .accessibilityHidden(true)
            }
        }
        .padding(EdgeInsets(top: padTop, leading: 13, bottom: padBottom, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(LinearGradient(colors: [.white, Brand.cabinet], startPoint: .top, endPoint: .bottom))
        )
        .background(RoundedRectangle(cornerRadius: 38, style: .continuous).fill(Brand.cabinetLip).offset(y: 9))
        .shadow(color: Color(red: 0.67, green: 0.37, blue: 0).opacity(0.3), radius: 17, y: 22)
    }
}

/// Each toy's cubby colour and its 3D toy's size in the cubby.
struct CubbyStyle {
    let top: Color
    let bottom: Color
    let image: String
    /// Height of the toy as a fraction of the cubby; a wide toy is limited by the width instead.
    let scale: Double

    static func `for`(_ id: String) -> CubbyStyle {
        switch id {
        case "sea": CubbyStyle(top: Color(hex: "8FD3FF"), bottom: Color(hex: "C6EAFF"), image: id, scale: 0.74)
        case "paint": CubbyStyle(top: Color(hex: "FFA2C0"), bottom: Color(hex: "FFCFDE"), image: id, scale: 0.66)
        case "tiles": CubbyStyle(top: Color(hex: "B6A2FF"), bottom: Color(hex: "DCD2FF"), image: id, scale: 0.72)
        case "animals": CubbyStyle(top: Color(hex: "8FDB7C"), bottom: Color(hex: "C3EEB6"), image: id, scale: 0.75)
        case "guitar": CubbyStyle(top: Color(hex: "79D9CC"), bottom: Color(hex: "B9EFE7"), image: id, scale: 0.79)
        case "parrot": CubbyStyle(top: Color(hex: "FFD45A"), bottom: Color(hex: "FFEAA4"), image: id, scale: 0.72)
        default: CubbyStyle(top: Color(hex: "8FD3FF"), bottom: Color(hex: "C6EAFF"), image: id, scale: 0.7)
        }
    }
}

/// The depth of a cubby: shade under the shelf above and along the sides.
struct CubbyShade: View {
    private let shade = Color(red: 0.24, green: 0.08, blue: 0.31)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [shade.opacity(0.26), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
            HStack {
                LinearGradient(colors: [shade.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 10)
                Spacer()
                LinearGradient(colors: [.clear, shade.opacity(0.14)], startPoint: .leading, endPoint: .trailing).frame(width: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// One compartment of the cabinet with its toy.
struct Cubby: View {
    let style: CubbyStyle
    let locked: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [style.top, style.bottom], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.215)
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 0.16, green: 0.04, blue: 0.24).opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: w * 0.32))
                    .frame(width: w * 0.64, height: 18)
                    .padding(.bottom, max(0, h * 0.088 - 9))
                if let image = Brand.toyImage(style.image) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: w * 0.84, maxHeight: h * style.scale)
                        .shadow(color: Color(red: 0.16, green: 0.04, blue: 0.24).opacity(0.18), radius: 3, y: 4)
                        .padding(.bottom, h * 0.118)
                        .offset(y: up ? -6 : 0)
                }
                CubbyShade()
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if locked { LockBadge().padding(10) }
            }
        }
        .task {
            guard !locked, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// The yellow lock on a toy that waits behind the purchase.
struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(Color(hex: "6B4300"))
            .frame(width: 40, height: 40)
            .background(Circle().fill(LinearGradient(colors: [Color(hex: "FFE27A"), Color(hex: "FFC21F")], startPoint: .top, endPoint: .bottom)))
            .background(Circle().fill(Color(hex: "D99A00")).offset(y: 4))
            .shadow(color: Color(red: 0.24, green: 0.12, blue: 0).opacity(0.2), radius: 5, y: 6)
            .accessibilityHidden(true)
    }
}
