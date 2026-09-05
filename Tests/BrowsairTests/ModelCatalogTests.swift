import XCTest
@testable import Browsair

final class ModelCatalogTests: XCTestCase {
    func testDecodesAndSortsAvailableModels() throws {
        let data = Data(#"{"data":[{"id":"grok-3"},{"id":"grok-4"},{"id":"embedding-model","type":"embedding"}]}"#.utf8)
        let models = try ModelCatalogResponse(data: data).chatModels
        XCTAssertEqual(models, ["grok-4", "grok-3"])
    }

    func testRejectsMalformedModelResponses() {
        XCTAssertThrowsError(try ModelCatalogResponse(data: Data("{}".utf8)))
    }
}
