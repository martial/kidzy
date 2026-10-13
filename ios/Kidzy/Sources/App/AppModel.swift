import Foundation
import Observation

/// The app's state: where the server is, what the kid sees, what the parent set.
@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case connecting
        case pairing
        case library
        case collection(Collection)
        case player(Item)
        case blocked
        case gate(GateOrigin)
        case parent
    }

    enum GateOrigin: Equatable {
        case library
        case blocked
    }

    var route: Route = .connecting
    var endpoint: ServerEndpoint?
    var token: String?
    var found: [ServerEndpoint] = []
    var collections: [Collection] = []
    var currentCollection: Collection?
    var currentItems: [Item] = []
    var rules = Rules()
    var watchedToday = 0
    var verdict: Verdict?
    var parentToken: String?
    var status = ""
    var lastError = ""
    var libraryVersion = -1

    private let browser = ServerBrowser()
    private var refreshTask: Task<Void, Never>?

    private static let endpointKey = "kidzy.endpoint"
    private static let tokenKey = "kidzy.device-token"

    var client: KidzyClient? {
        endpoint.map { KidzyClient(endpoint: $0, token: token) }
    }

    var isBlocked: Bool {
        TimeLimitRules.block(now: Date(), watchedToday: watchedToday, rules: rules) != nil
    }

    var stars: Int { TimeLimitRules.stars(watchedToday: watchedToday, rules: rules) }

    // MARK: - lifecycle

    func start() {
        if let data = UserDefaults.standard.data(forKey: Self.endpointKey), let ep = try? JSONDecoder().decode(ServerEndpoint.self, from: data), ep.isUsable {
            endpoint = ep
        } else {
            UserDefaults.standard.removeObject(forKey: Self.endpointKey)
        }
        token = Keychain.get(Self.tokenKey)
        browser.onFound = { [weak self] ep in
            guard let self else { return }
            if !found.contains(where: { $0.host == ep.host && $0.port == ep.port }) { found.append(ep) }
            let replace = endpoint == nil || !(endpoint?.isUsable ?? false) || token == nil || (endpoint?.host != ep.host && route == .connecting)
            if replace, ep.isUsable {
                endpoint = ep
                saveEndpoint()
                if token != nil { Task { await connect() } }
            }
            if token == nil, route == .connecting { route = .pairing }
        }
        browser.start()
        if endpoint != nil, token != nil {
            Task { await connect() }
        } else {
            status = "Je cherche le serveur de la maison…"
            Task {
                try? await Task.sleep(for: .seconds(4))
                if route == .connecting { route = .pairing }
            }
        }
    }

    func scenePhaseChanged(active: Bool) {
        guard active else {
            if case .player = route { exitPlayer() }
            return
        }
        if token != nil, endpoint != nil { Task { await refresh() } }
    }

    private func saveEndpoint() {
        if let endpoint, let data = try? JSONEncoder().encode(endpoint) {
            UserDefaults.standard.set(data, forKey: Self.endpointKey)
        }
    }

    // MARK: - connection and pairing

    func connect() async {
        guard let client else { return }
        status = "Connexion à \(endpoint?.name ?? "Kidzy")…"
        do {
            _ = try await client.identity()
            await refresh()
            route = isBlocked ? .blocked : .library
            lastError = ""
            startRefreshLoop()
        } catch KidzyClient.Failure.http(401, _) {
            token = nil
            Keychain.delete(Self.tokenKey)
            route = .pairing
        } catch {
            status = "Serveur introuvable"
            lastError = describe(error)
            if route == .connecting {
                try? await Task.sleep(for: .seconds(3))
                if route == .connecting { await connect() }
            }
        }
    }

    /// Pairs with the PIN; returns a message on failure.
    func pair(pin: String) async -> String? {
        guard let endpoint else { return "Aucun serveur trouvé" }
        let name = await UIDeviceName.current()
        do {
            let r = try await KidzyClient(endpoint: endpoint).pair(pin: pin, deviceName: name)
            token = r.token
            Keychain.set(Self.tokenKey, r.token)
            self.endpoint = ServerEndpoint(host: endpoint.host, port: endpoint.port, name: r.name)
            saveEndpoint()
            await connect()
            return nil
        } catch {
            return describe(error)
        }
    }

    func useManualEndpoint(_ text: String) async -> String? {
        guard let ep = ServerEndpoint.parse(text) else { return "Adresse invalide" }
        do {
            let id = try await KidzyClient(endpoint: ep).identity()
            endpoint = ServerEndpoint(host: ep.host, port: ep.port, name: id.name)
            saveEndpoint()
            if token != nil { await connect() } else { route = .pairing }
            return nil
        } catch {
            return describe(error)
        }
    }

    func unpair() {
        token = nil
        Keychain.delete(Self.tokenKey)
        parentToken = nil
        route = .pairing
    }

    // MARK: - library

    func refresh() async {
        guard let client else { return }
        do {
            let r = try await client.collections()
            collections = r.collections
            libraryVersion = r.libraryVersion
            apply(try await client.limits())
            lastError = ""
        } catch {
            lastError = describe(error)
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard let self else { return }
                switch route {
                case .library, .collection, .blocked:
                    await refresh()
                    if case .blocked = route, !isBlocked { route = .library }
                    if case .library = route, isBlocked { route = .blocked }
                default:
                    break
                }
            }
        }
    }

    func apply(_ v: Verdict) {
        verdict = v
        rules = v.rules
        watchedToday = v.watchedSeconds
    }

    func open(_ collection: Collection) async {
        guard let client else { return }
        do {
            let d = try await client.collection(id: collection.id)
            currentCollection = d.collection
            currentItems = d.items
            route = .collection(d.collection)
        } catch {
            lastError = describe(error)
        }
    }

    func backToLibrary() {
        currentCollection = nil
        currentItems = []
        route = isBlocked ? .blocked : .library
    }

    // MARK: - playback

    func play(_ item: Item) {
        guard !isBlocked else {
            route = .blocked
            return
        }
        route = .player(item)
    }

    func next(after item: Item) -> Item? {
        AutoplayQueue(items: currentItems).next(after: item)
    }

    /// Called every second while a video plays.
    func tickPlaying() {
        watchedToday += 1
        if isBlocked { route = .blocked }
    }

    func report(_ event: TimelineReporter.Event) async {
        guard let client, let v = try? await client.timeline(event) else { return }
        apply(v)
        if !v.allowed, case .player = route { route = .blocked }
    }

    func exitPlayer() {
        if let c = currentCollection { route = isBlocked ? .blocked : .collection(c) } else { backToLibrary() }
    }

    func mediaURL(_ path: String) -> URL? { client?.mediaURL(path) }

    // MARK: - parent

    func openGate(from origin: GateOrigin) { route = .gate(origin) }

    func closeGate(_ origin: GateOrigin) {
        route = origin == .blocked ? .blocked : .library
    }

    func unlock(pin: String) async -> Bool {
        guard let client else { return false }
        guard let s = try? await client.unlock(pin: pin) else { return false }
        parentToken = s.token
        route = .parent
        return true
    }

    func closeParent() {
        parentToken = nil
        Task { await refresh() }
        route = isBlocked ? .blocked : .library
    }

    func describe(_ error: Error) -> String {
        if let f = error as? KidzyClient.Failure {
            switch f {
            case .badURL: return "Adresse du serveur inutilisable (\(endpoint?.host ?? "?"))"
            case .http(_, let m): return m
            case .decoding: return "Réponse illisible"
            }
        }
        return (error as NSError).localizedDescription
    }
}

enum UIDeviceName {
    @MainActor static func current() async -> String {
        #if canImport(UIKit)
        return UIKit.UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
