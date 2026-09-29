import XCTest
@testable import Browsair

/// Tab-switching was previously impossible beyond clicking a chip; these tests pin the
/// selection helpers the keyboard shortcuts depend on.
@MainActor
final class TabSelectionTests: XCTestCase {
    @MainActor
    private func makeSession(with urls: [String]) async -> BrowserSession {
        let session = BrowserSession()
        await session.start()
        // start() seeds one blank tab (index 0). Append the named tabs after it so
        // ⌘1…⌘9 index them 1-based.
        for url in urls { _ = session.openPopup(from: URL(string: url)) }
        return session
    }

    func testSelectTabByNumber() async {
        let session = await makeSession(with: ["https://a.com", "https://b.com", "https://c.com"])
        session.selectTab(number: 2)
        XCTAssertEqual(session.activeTab?.urlString, "https://a.com")
        session.selectTab(number: 3)
        XCTAssertEqual(session.activeTab?.urlString, "https://b.com")
        session.selectTab(number: 4)
        XCTAssertEqual(session.activeTab?.urlString, "https://c.com")
    }

    func testSelectTabNumberBeyondRangeIsIgnored() async {
        let session = await makeSession(with: ["https://a.com", "https://b.com"])
        session.selectTab(number: 2)
        session.selectTab(number: 99)
        XCTAssertEqual(session.activeTab?.urlString, "https://a.com", "out-of-range selection must not change tab")
    }

    func testSelectTabNumberZeroIsIgnored() async {
        let session = await makeSession(with: ["https://a.com", "https://b.com"])
        session.selectTab(number: 2)
        session.selectTab(number: 0)
        XCTAssertEqual(session.activeTab?.urlString, "https://a.com")
    }

    func testSelectNextAndPreviousWrap() async {
        let session = await makeSession(with: ["https://a.com", "https://b.com", "https://c.com"])
        session.selectTab(number: 2) // a.com
        session.selectNextTab()
        XCTAssertEqual(session.activeTab?.urlString, "https://b.com")
        session.selectNextTab()
        XCTAssertEqual(session.activeTab?.urlString, "https://c.com")
        session.selectNextTab() // wraps to blank tab
        XCTAssertEqual(session.activeTab?.urlString, "")
        session.selectPreviousTab() // wraps back to c.com
        XCTAssertEqual(session.activeTab?.urlString, "https://c.com")
    }

    func testLastTabShortcutSelectsFinalTab() async {
        let session = await makeSession(with: ["https://a.com", "https://b.com", "https://c.com"])
        session.selectLastTab()
        XCTAssertEqual(session.activeTab?.urlString, "https://c.com")
    }

    // MARK: - Idempotent page-command dispatch (audit F4: double navigation)

    func testConsumePageCommandReadsOnceThenClears() async {
        let session = BrowserSession()
        await session.start()
        let tab = session.activeTab!
        await session.navigate(tab: tab, to: "https://example.com")

        XCTAssertEqual(tab.pageCommand, .load("https://example.com"), "command present before consumption")
        XCTAssertEqual(session.consumePageCommand(for: tab), .load("https://example.com"), "first consume returns the command")
        XCTAssertNil(session.consumePageCommand(for: tab), "second consume must be nil — the command may only apply once")
        XCTAssertNil(tab.pageCommand, "consume clears the tab's pending command")
    }

    func testConsumePageCommandIsNilWhenNothingPending() async {
        let session = BrowserSession()
        await session.start()
        let tab = session.activeTab!
        XCTAssertNil(session.consumePageCommand(for: tab))
    }
}
