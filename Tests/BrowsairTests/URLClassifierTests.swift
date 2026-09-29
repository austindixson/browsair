import XCTest
@testable import Browsair

/// Behavior for the address-bar/query classifier that replaces the old
/// `BrowserSession.normalizeURL` `contains(".")` heuristic.
@MainActor
final class URLClassifierTests: XCTestCase {
    private func classify(_ raw: String, current: String? = nil) -> URLQueryResult {
        URLQueryResult.classify(raw, current: current)
    }

    func testExplicitSchemesPassThrough() {
        for url in ["https://example.com", "http://example.com", "about:blank",
                    "file:///tmp/x.html", "data:text/html,hi"] {
            XCTAssertEqual(classify(url).scheme, .navigate)
            XCTAssertEqual(classify(url).value, url)
        }
    }

    func testBareDomainBecomesHTTPS() {
        let r = classify("example.com")
        XCTAssertEqual(r.scheme, .navigate)
        XCTAssertEqual(r.value, "https://example.com")
    }

    func testWwwPrefixIsPreserved() {
        XCTAssertEqual(classify("www.bbc.co.uk").value, "https://www.bbc.co.uk")
    }

    func testDomainWithPortAndPath() {
        XCTAssertEqual(classify("example.com:8443/path").value, "https://example.com:8443/path")
    }

    func testLocalhostUsesHTTP() {
        XCTAssertEqual(classify("localhost").value, "http://localhost")
        XCTAssertEqual(classify("localhost:3000").value, "http://localhost:3000")
        XCTAssertEqual(classify("http://localhost:5173/app").value, "http://localhost:5173/app")
    }

    func testBonjourLocalHostUsesHTTP() {
        XCTAssertEqual(classify("app.local").value, "http://app.local")
        XCTAssertEqual(classify("app.local:3000/x").value, "http://app.local:3000/x")
    }

    func testIPv4LiteralUsesHTTP() {
        XCTAssertEqual(classify("127.0.0.1:8080/login").value, "http://127.0.0.1:8080/login")
        XCTAssertEqual(classify("192.168.1.1").value, "http://192.168.1.1")
    }

    func testInvalidIPv4FallsBackToSearch() {
        XCTAssertEqual(classify("256.1.1.1").scheme, .search)
        XCTAssertEqual(classify("300.1.1.1").scheme, .search)
    }

    func testIPv6LiteralUsesHTTP() {
        XCTAssertEqual(classify("[::1]:8080").value, "http://[::1]:8080")
    }

    func testRelativePathResolvesAgainstCurrentPage() {
        let r = classify("/settings/profile", current: "https://github.com/dashboard")
        XCTAssertEqual(r.scheme, .navigate)
        XCTAssertEqual(r.value, "https://github.com/settings/profile")
    }

    func testQueryStringResolvesAgainstCurrentPage() {
        let r = classify("?q=hello", current: "https://duckduckgo.com/")
        XCTAssertEqual(r.scheme, .navigate)
        XCTAssertEqual(r.value, "https://duckduckgo.com/?q=hello")
    }

    func testFragmentResolvesAgainstCurrentPage() {
        let r = classify("#section", current: "https://example.com/page")
        XCTAssertEqual(r.scheme, .navigate)
        XCTAssertEqual(r.value, "https://example.com/page#section")
    }

    func testRelativeWithoutCurrentPageBecomesSearch() {
        XCTAssertEqual(classify("/no/current").scheme, .search)
    }

    func testPlainTextBecomesSearch() {
        let r = classify("privacy browser")
        XCTAssertEqual(r.scheme, .search)
        XCTAssertTrue(r.value.hasPrefix("https://duckduckgo.com/?q="))
        XCTAssertTrue(r.value.contains("privacy"))
    }

    func testMultiWordWithDotsStillSearches() {
        // Contains dots AND spaces — the old heuristic mis-searched only by luck;
        // a phrase with spaces must NEVER be treated as a host.
        XCTAssertEqual(classify("what is a kink").scheme, .search)
    }

    func testNonWebSchemeDelegatesToExternalHandler() {
        XCTAssertEqual(classify("mailto:a@b.com").scheme, .external)
        XCTAssertEqual(classify("tel:+15551234").scheme, .external)
    }

    func testRejectsBogusPortAsSearch() {
        XCTAssertEqual(classify("example.com:99999").scheme, .search)
    }

    func testLeadingDotIsNotAHost() {
        XCTAssertEqual(classify(".local").scheme, .search)
    }
}
