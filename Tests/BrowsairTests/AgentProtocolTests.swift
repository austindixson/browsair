import XCTest
@testable import Browsair

final class AgentProtocolTests: XCTestCase {
    func testDecodesNavigationCommand() throws {
        let command = try AgentCommand.decode(json: #"{"command":"navigate","url":"https://example.com"}"#)
        XCTAssertEqual(command, .navigate(url: "https://example.com"))
        let inspect = try AgentCommand.decode(json: #"{"command":"inspect","selector":"main"}"#)
        if case .inspect(let request) = inspect { XCTAssertEqual(request.selector, "main") } else { XCTFail("Expected inspect") }
    }

    func testRejectsUnknownCommandAndInvalidURL() {
        XCTAssertThrowsError(try AgentCommand.decode(json: #"{"command":"shutdown"}"#))
        XCTAssertThrowsError(try AgentCommand.decode(json: #"{"command":"navigate","url":"file:///etc/passwd"}"#))
    }

    func testResponseEncodingIsStable() throws {
        let data = try AgentResponse.ok(.init(url: "https://example.com", title: "Example", isLoading: false)).encoded()
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true,"state":{"isLoading":false,"title":"Example","url":"https:\/\/example.com"}}"#)
    }

    func testPageTextResponseIncludesBoundedResult() throws {
        let data = try AgentResponse.pageText(
            state: .init(url: "https://example.com", title: "Example", isLoading: false),
            text: "Hello"
        ).encoded()
        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            #"{"ok":true,"result":{"text":"Hello"},"state":{"isLoading":false,"title":"Example","url":"https:\/\/example.com"}}"#
        )
    }
}
