import XCTest
@testable import Browsair

final class InspectTests: XCTestCase {
    func testDecodesInspectOptionsWithClampedLimits() throws {
        let request = try InspectRequest.decode(json: #"{"command":"inspect","selector":"main","maxDepth":99,"maxNodes":9999,"includeText":true}"#)
        XCTAssertEqual(request.selector, "main")
        XCTAssertEqual(request.maxDepth, InspectRequest.maximumDepth)
        XCTAssertEqual(request.maxNodes, InspectRequest.maximumNodes)
        XCTAssertTrue(request.includeText)
    }

    func testRejectsUnsafeSelectorAndOversizedInput() {
        XCTAssertThrowsError(try InspectRequest.decode(json: #"{"command":"inspect","selector":"main; alert(1)"}"#))
        XCTAssertThrowsError(try InspectRequest.decode(json: String(repeating: "x", count: 20_001)))
    }

    func testDecodesBoundedStructuredSnapshot() throws {
        let json = #"{"url":"https://example.com","title":"Example","nodes":[{"tag":"main","id":"content","classes":["hero"],"text":"Hello","children":[]}],"truncated":false}"#
        let snapshot = try InspectSnapshot.decode(json: json)
        XCTAssertEqual(snapshot.nodes.first?.tag, "main")
        XCTAssertEqual(snapshot.nodes.first?.text, "Hello")
        XCTAssertFalse(snapshot.truncated)
    }

    func testInspectScriptEscapesSelectorAndIncludesBounds() throws {
        let script = try InspectScript.make(request: .init(selector: "main", maxDepth: 3, maxNodes: 12, includeText: true))
        XCTAssertTrue(script.contains("querySelector"))
        XCTAssertTrue(script.contains("12"))
        XCTAssertTrue(script.contains("3"))
        XCTAssertFalse(script.contains("innerHTML"))
    }
}
