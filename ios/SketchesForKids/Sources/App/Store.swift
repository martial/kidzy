import Foundation
import StoreKit

/// The one purchase, « All toys »: a non-consumable that unlocks every toy
/// outside `freeToys`. StoreKit 2; the state is cached so the picker never waits.
@MainActor
@Observable
final class Store {
    static let packID = "com.screenclub.sketchesforkids.alltoys"
    static let freeToys: Set<String> = ["sea", "animals"]
    static let cacheKey = "sketches.unlocked"

    private(set) var product: Product?
    private(set) var isUnlocked: Bool
    /// Ask to Buy: a parent has not answered yet.
    private(set) var pending = false
    private(set) var lastError: String?
    private var listener: Task<Void, Never>?
    private var forced = false
    private static let testUnlockKey = "sketches.test-unlock"

    init() {
        isUnlocked = UserDefaults.standard.bool(forKey: Self.cacheKey)
        #if DEBUG || BETA
        if ProcessInfo.processInfo.environment["KIDZY_UNLOCK"] == "1" || Self.testUnlockStored {
            isUnlocked = true
            forced = true
        }
        #endif
    }

    func isFree(_ id: String) -> Bool { Self.freeToys.contains(id) }

    #if DEBUG || BETA
    /// A debug build on a phone, and a TestFlight-only build (`BETA=1 archive-upload.sh`), start
    /// with every toy open (the purchase cannot be bought before the Paid Apps Agreement); the
    /// simulator and the tests start locked. The parents page switch overrides both.
    private static var testUnlockStored: Bool {
        if let stored = UserDefaults.standard.object(forKey: testUnlockKey) as? Bool { return stored }
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Debug and beta builds only: every toy open without the App Store, for trying the app
    /// before the purchase can be bought. Never compiled into a build submitted for review.
    var testUnlock: Bool {
        get { forced }
        set {
            forced = newValue
            UserDefaults.standard.set(newValue, forKey: Self.testUnlockKey)
            isUnlocked = newValue || UserDefaults.standard.bool(forKey: Self.cacheKey)
            if !newValue { Task { await refresh() } }
        }
    }
    #endif
    func isAvailable(_ id: String) -> Bool { isUnlocked || isFree(id) }
    var lockedToys: [ToyEntry] { Toys.all.filter { !isFree($0.id) } }

    func start() async {
        if listener == nil {
            // Unfinished and Ask-to-Buy transactions arrive here, from launch on.
            listener = Task { [weak self] in
                for await result in Transaction.updates {
                    await self?.apply(result)
                }
            }
        }
        await refresh()
        product = try? await Product.products(for: [Self.packID]).first
    }

    /// What the App Store says the user owns.
    func refresh() async {
        guard !forced else { return }
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.packID, t.revocationDate == nil { unlocked = true }
        }
        set(unlocked)
    }

    /// The outcome of the purchase sheet.
    func handle(purchase result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            await apply(verification)
        case .pending:
            pending = true
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    private func apply(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let t) = result else { return }
        if t.productID == Self.packID {
            pending = false
            set(t.revocationDate == nil)
        }
        await t.finish()
    }

    /// Only from the Restore button: it may ask for the App Store password.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    private func set(_ unlocked: Bool) {
        isUnlocked = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.cacheKey)
    }
}
