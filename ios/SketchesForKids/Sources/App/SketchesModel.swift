import Foundation
import Observation

/// What is on screen, which toys the parent hid, and the store.
@MainActor
@Observable
final class SketchesModel {
    enum GateTarget: Equatable {
        case parent
        case unlock(String)
    }

    enum Route: Equatable {
        case picker
        case toy(String)
        case gate(GateTarget)
        case unlock(String)
        case parent
    }

    var route: Route = .picker
    let store = Store()
    private static let hiddenKey = "sketches.hidden-toys"
    private(set) var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: SketchesModel.hiddenKey) ?? [])

    var visibleToys: [ToyEntry] { Toys.all.filter { !hidden.contains($0.id) } }

    func start() {
        #if DEBUG
        if let show = ProcessInfo.processInfo.environment["KIDZY_SHOW"] {
            if show.hasPrefix("sketch:") {
                route = .toy(String(show.dropFirst("sketch:".count)))
            } else if show == "gate" {
                route = .gate(.parent)
            } else if show.hasPrefix("unlock") {
                route = .unlock(show.hasPrefix("unlock:") ? String(show.dropFirst("unlock:".count)) : "parrot")
            } else if show == "parent" {
                route = .parent
            }
        }
        #endif
        Task { await store.start() }
    }

    /// A free or unlocked toy opens; a locked one goes through the gate first.
    func tapped(_ entry: ToyEntry) {
        route = store.isAvailable(entry.id) ? .toy(entry.id) : .gate(.unlock(entry.id))
    }

    func gatePassed(_ target: GateTarget) {
        switch target {
        case .parent: route = .parent
        case .unlock(let id): route = .unlock(id)
        }
    }

    func exitToy() { route = .picker }

    func setHidden(_ id: String, _ isHidden: Bool) {
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
        UserDefaults.standard.set(Array(hidden).sorted(), forKey: Self.hiddenKey)
    }
}
