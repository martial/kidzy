import XCTest
@testable import KidzyCore

final class ModelsTests: XCTestCase {
    func testItemRoundTripsThroughJSON() throws {
        let item = Item(id: "a1", collectionID: "c1", title: "Épisode 1", duration: 61.5, thumbURL: "/t", videoURL: "/v")
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(Item.self, from: data)
        XCTAssertEqual(item, back)
    }
}
