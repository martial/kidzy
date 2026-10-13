import SwiftUI

/// What the parent can change from the phone: limits, visible collections,
/// the PIN, the server. Everything else is on the Mac's admin.
struct ParentAreaView: View {
    @Environment(AppModel.self) private var model
    @State private var settings: Settings?
    @State private var daily = false
    @State private var minutes = 45
    @State private var bedtime = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var visible: [String: Bool] = [:]
    @State private var error = ""
    @State private var newPin = ""
    @State private var currentPin = ""
    @State private var pinNotice = ""
    @State private var serverText = ""
    @State private var online: Bool?

    private var address: String { "\(model.endpoint?.host ?? "?"):\(String(model.endpoint?.port ?? 8800))" }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.sky.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Espace parent").font(Theme.rounded(28)).foregroundStyle(Theme.ink)
                        Spacer()
                        StickerButton(size: 44, systemImage: "xmark", label: "Fermer") { save(); model.closeParent() }
                    }
                    .padding(.top, 14)
                    if !error.isEmpty { Text(error).font(Theme.rounded(15, weight: .medium)).foregroundStyle(Theme.coral) }

                    card("Serveur") {
                        HStack(spacing: 10) {
                            Circle().fill(online == true ? Theme.grass : online == false ? Theme.coral : Theme.starOff).overlay(Circle().stroke(Theme.ink, lineWidth: 2)).frame(width: 12, height: 12)
                            Text(verbatim: "\(model.endpoint?.name ?? "Kidzy"), \(online == true ? "en ligne" : online == false ? "injoignable" : "…")").font(Theme.rounded(16, weight: .medium))
                        }
                        Text(verbatim: "\(address) · \(settings?.collections.reduce(0) { $0 + $1.itemCount } ?? 0) vidéos")
                            .font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted)
                        HStack {
                            TextField("Autre adresse (hôte:port)", text: $serverText)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                .font(Theme.rounded(15, weight: .medium)).padding(8)
                                .background(Theme.field).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ink, lineWidth: 2))
                            smallButton("Changer") {
                                Task { error = await model.useManualEndpoint(serverText) ?? "" }
                            }
                        }
                        smallButton("Dissocier cet iPhone") { model.unpair() }
                    }

                    card("Temps d'écran") {
                        Text(verbatim: "Aujourd'hui : \(minutesText(settings?.watchedToday ?? model.watchedToday))\(daily ? " sur \(minutes) min" : "")").font(Theme.rounded(16, weight: .medium))
                        if daily {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 10).fill(Theme.field)
                                    RoundedRectangle(cornerRadius: 10).fill(Theme.lemon)
                                        .frame(width: geo.size.width * min(1, Double(settings?.watchedToday ?? model.watchedToday) / Double(max(1, minutes * 60))))
                                }
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 3))
                            }
                            .frame(height: 18)
                        }
                        Toggle(isOn: $daily) { Text("Limite par jour").font(Theme.rounded(16, weight: .medium)) }.tint(Theme.grass)
                        if daily {
                            Stepper(value: $minutes, in: 5...600, step: 5) { Text(verbatim: "\(minutes) min par jour").font(Theme.rounded(16, weight: .medium)) }
                        }
                        Toggle(isOn: $bedtime) { Text("Coucher").font(Theme.rounded(16, weight: .medium)) }.tint(Theme.grass)
                        if bedtime {
                            HStack {
                                DatePicker("de", selection: $start, displayedComponents: .hourAndMinute).font(Theme.rounded(16, weight: .medium))
                                DatePicker("à", selection: $end, displayedComponents: .hourAndMinute).font(Theme.rounded(16, weight: .medium))
                            }
                        }
                    }

                    card("Collections visibles") {
                        ForEach(settings?.collections ?? []) { c in
                            Toggle(isOn: Binding(get: { visible[c.id] ?? c.visible }, set: { visible[c.id] = $0 })) {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(hex: c.color)).overlay(Circle().stroke(Theme.ink, lineWidth: 2)).frame(width: 14, height: 14)
                                    Text(verbatim: "\(c.title) · \(c.itemCount) vidéo\(c.itemCount > 1 ? "s" : "")").font(Theme.rounded(16, weight: .medium))
                                }
                            }
                            .tint(Theme.grass)
                        }
                    }

                    card("Jouets") {
                        Toggle(isOn: Binding(get: { model.sketchesVisible }, set: { model.sketchesVisible = $0 })) {
                            Text("La mer (jeu d'inclinaison)").font(Theme.rounded(16, weight: .medium))
                        }
                        .tint(Theme.grass)
                        Toggle(isOn: Binding(get: { model.seaBackground }, set: { model.seaBackground = $0 })) {
                            Text("La mer derrière les tuiles (essai)").font(Theme.rounded(16, weight: .medium))
                        }
                        .tint(Theme.grass)
                        Text("Les jouets ne comptent pas dans le temps d'écran et restent ouverts après la limite.").font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted)
                    }

                    card("Code parent") {
                        HStack {
                            SecureField("Code actuel", text: $currentPin).keyboardType(.numberPad)
                            SecureField("Nouveau code", text: $newPin).keyboardType(.numberPad)
                            smallButton("Changer") { changePin() }
                        }
                        .font(Theme.rounded(16, weight: .medium))
                        if !pinNotice.isEmpty { Text(pinNotice).font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted) }
                    }

                    Text(verbatim: "Tout le reste (vidéos, collections, image de fin) se règle sur le Mac : http://\(address)/admin/")
                        .font(Theme.rounded(14, weight: .medium)).foregroundStyle(Theme.muted)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear { Orientation.set(.portrait) }
        .task { await load() }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.rounded(18))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.ink, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.ink).offset(x: 5, y: 5))
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.rounded(15)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Theme.field).clipShape(Capsule()).overlay(Capsule().stroke(Theme.ink, lineWidth: 3))
        }
        .buttonStyle(PressStyle())
    }

    private func minutesText(_ seconds: Int) -> String { "\(seconds / 60) min" }

    private func load() async {
        guard let client = model.client, let token = model.parentToken else { return }
        online = (try? await client.identity()) != nil
        do {
            let s = try await client.settings(parentToken: token)
            settings = s
            daily = s.limits.dailySeconds > 0
            if daily { minutes = max(5, s.limits.dailySeconds / 60) }
            bedtime = s.limits.bedtime != nil
            start = time(s.limits.bedtime?.start ?? "19:30")
            end = time(s.limits.bedtime?.end ?? "07:00")
            visible = Dictionary(uniqueKeysWithValues: s.collections.map { ($0.id, $0.visible) })
        } catch {
            self.error = model.describe(error)
        }
    }

    private func save() {
        guard let client = model.client, let token = model.parentToken else { return }
        let rules = Rules(dailySeconds: daily ? minutes * 60 : 0, bedtime: bedtime ? Bedtime(start: hhmm(start), end: hhmm(end)) : nil)
        let cols = visible.map { (id: $0.key, visible: $0.value) }
        Task {
            if let s = try? await client.updateSettings(parentToken: token, limits: rules, collections: cols) {
                model.rules = s.limits
            }
        }
    }

    private func changePin() {
        guard let base = model.endpoint?.baseURL, let token = model.parentToken, let deviceToken = model.token else { return }
        var req = URLRequest(url: base.appendingPathComponent("/api/settings/pin"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        req.setValue(token, forHTTPHeaderField: "X-Parent-Token")
        req.httpBody = try? JSONEncoder().encode(["pin": newPin, "current": currentPin])
        Task {
            if let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse {
                if http.statusCode == 200 {
                    pinNotice = "Code changé."
                    newPin = ""
                    currentPin = ""
                } else {
                    pinNotice = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "Échec"
                }
            }
        }
    }

    private func time(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = parts.first ?? 19
        c.minute = parts.count > 1 ? parts[1] : 30
        return Calendar.current.date(from: c) ?? Date()
    }

    private func hhmm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
