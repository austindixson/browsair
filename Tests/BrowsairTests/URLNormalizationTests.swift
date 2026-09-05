import XCTest
@testable import Browsair

@MainActor
final class URLNormalizationTests: XCTestCase {
    func testPreservesURLsAndAddsHTTPS() {
        XCTAssertEqual(BrowserSession.normalizeURL("https://example.com"), "https://example.com")
        XCTAssertEqual(BrowserSession.normalizeURL("example.com"), "https://example.com")
    }

    func testSearchesPlainText() {
        XCTAssertEqual(BrowserSession.normalizeURL("privacy browser"), "https://duckduckgo.com/?q=privacy%20browser")
    }
}
