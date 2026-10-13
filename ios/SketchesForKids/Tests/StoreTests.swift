import StoreKit
import StoreKitTest
import XCTest
@testable import SketchesForKids

/// Drives the purchase through the local StoreKit configuration (Store.storekit).
@MainActor
final class StoreTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Store")
        session.disableDialogs = true
        session.clearTransactions()
        UserDefaults.standard.removeObject(forKey: Store.cacheKey)
    }

    func testFreeToysAndLockedOnes() async {
        let store = Store()
        XCTAssertTrue(store.isFree("sea"))
        XCTAssertTrue(store.isFree("animals"))
        XCTAssertFalse(store.isAvailable("parrot"))
        XCTAssertEqual(store.lockedToys.map(\.id), ["paint", "tiles", "guitar", "parrot"])
    }

    func testBuyingThePackUnlocks() async throws {
        let store = Store()
        await store.start()
        XCTAssertNotNil(store.product, "the local configuration lists the pack")
        XCTAssertFalse(store.isUnlocked)
        try await session.buyProduct(identifier: Store.packID)
        // the listener on Transaction.updates unlocks within a moment
        for _ in 0..<60 where !store.isUnlocked { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(store.isUnlocked)
        XCTAssertTrue(store.isAvailable("parrot"))
        await store.refresh()
        XCTAssertTrue(store.isUnlocked, "a finished purchase stays in the entitlements")
    }

    func testAnEarlierPurchaseIsFoundAtLaunch() async throws {
        try await session.buyProduct(identifier: Store.packID)
        let store = Store()
        await store.start()
        XCTAssertTrue(store.isUnlocked, "entitlements are read at launch, no restore needed")
    }
}
