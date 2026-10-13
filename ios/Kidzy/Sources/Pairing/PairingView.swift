import SwiftUI

/// First launch: the server found by Bonjour and the parent PIN to pair.
struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var error = ""
    @State private var manual = ""
    @State private var showManual = false

    var body: some View {
        ZStack {
            if let ep = model.endpoint, !showManual {
                PinKeypad(title: "Code parent", subtitle: "pour relier cet iPhone à « \(ep.name) » (\(ep.host):\(ep.port))\n\(error)", onClose: { showManual = true }) { pin in
                    if let msg = await model.pair(pin: pin) {
                        error = msg
                        return false
                    }
                    return true
                }
            } else {
                VStack(spacing: 20) {
                    SunMascot()
                    Text(model.endpoint == nil ? "Je cherche le serveur vidéo sur le réseau de la maison…" : "Adresse du serveur")
                        .font(Theme.rounded(20))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    TextField("MacBook-Pro.local:8800", text: $manual)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(Theme.rounded(18, weight: .medium))
                        .padding(12)
                        .background(Theme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ink, lineWidth: 3))
                    Button {
                        Task {
                            error = await model.useManualEndpoint(manual) ?? ""
                            if error.isEmpty { showManual = false }
                        }
                    } label: {
                        Text("Se connecter").font(Theme.rounded(18)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Theme.field).clipShape(Capsule()).overlay(Capsule().stroke(Theme.ink, lineWidth: 3))
                    }
                    .buttonStyle(PressStyle())
                    if !error.isEmpty { Text(error).font(Theme.rounded(15, weight: .medium)).foregroundStyle(Theme.coral) }
                    Text("Le serveur s'installe sur le Mac de la maison ; son admin est à http://localhost:8800/admin/ sur le Mac.")
                        .font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.sky.ignoresSafeArea())
            }
        }
        .onAppear { Orientation.set(.portrait) }
    }
}

struct ConnectingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            SunMascot()
            Text(model.status).font(Theme.rounded(20)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if !model.lastError.isEmpty {
                Text(model.lastError).font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted)
                Button("Changer d'adresse") { model.route = .pairing }
                    .font(Theme.rounded(16)).foregroundStyle(Theme.ink)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sky.ignoresSafeArea())
        .onAppear { Orientation.set(.portrait) }
    }
}
