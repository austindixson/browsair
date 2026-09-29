import XCTest
@testable import Browsair

/// The AI sidebar previously called `AIContextPolicy.make(selectedText: nil, inspectedText: nil, …)`,
/// so the model got no page content despite a system prompt claiming otherwise. These tests pin the
/// seam that actually reads the page.
@MainActor
final class SidebarContextTests: XCTestCase {

    func testPageTextExtractorTruncatesAndIsBounded() {
        let long = String(repeating: "x", count: 50_000)
        let out = PageTextExtractor.sanitize(long)
        XCTAssertLessThanOrEqual(out.count, PageTextExtractor.maximumCharacters)
        XCTAssertTrue(out.allSatisfy { $0 == "x" })
    }

    func testPageTextExtractorStripsScriptAndStyle() {
        let html = "visible <script>secret()</script> text <style>password: hi</style> end"
        let out = PageTextExtractor.sanitize(html)
        XCTAssertTrue(out.contains("visible"))
        XCTAssertTrue(out.contains("end"))
        XCTAssertFalse(out.contains("secret"))
        XCTAssertFalse(out.lowercased().contains("password:"))
    }

    // The single scrubber must also redact a standalone secret that is NOT inside a
    // script/style tag — the one capability the removed duplicate scrubber provided.
    func testPageTextExtractorRedactsStandaloneSecret() {
        let text = "Welcome back. password=hunter2 your inbox is ready"
        let out = PageTextExtractor.sanitize(text)
        XCTAssertFalse(out.lowercased().contains("hunter2"), out)
        XCTAssertTrue(out.contains("Welcome back"), out)
        XCTAssertTrue(out.contains("[redacted]"), out)
    }

    func testSidebarContextIncludesPageTextWhenPresent() {
        // When page text is supplied, the context block must carry it.
        let context = AIContextPolicy.make(
            selectedText: nil,
            inspectedText: nil,
            pageText: "The inbox has three unread messages.",
            url: "https://mail.example.com",
            title: "Inbox")
        XCTAssertTrue(context.contains("The inbox has three unread messages."), context)
        XCTAssertTrue(context.contains("https://mail.example.com"))
    }

    func testSidebarContextStillWorksWithoutPageText() {
        let context = AIContextPolicy.make(
            selectedText: nil, inspectedText: nil, pageText: nil,
            url: "https://example.com", title: "Example")
        XCTAssertTrue(context.contains("https://example.com"))
        XCTAssertLessThanOrEqual(context.count, AIContextPolicy.maximumCharacters)
    }
}
