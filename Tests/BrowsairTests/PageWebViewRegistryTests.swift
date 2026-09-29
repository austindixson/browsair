import XCTest
import WebKit
@testable import Browsair

/// The sidebar used a static `[ObjectIdentifier: WKWebView]` cache that never shrank on OS-window
/// close, leaking web views. These tests pin the bounded, evicting replacement.
@MainActor
final class PageWebViewRegistryTests: XCTestCase {
    func testSetAndRetrieve() {
        let registry = PageWebViewRegistry(capacity: 4)
        let tab = TabModel()
        let webView = WKWebView()
        registry.set(webView, for: tab)
        XCTAssertTrue(registry.webView(for: tab) === webView)
    }

    func testMissingTabReturnsNil() {
        let registry = PageWebViewRegistry(capacity: 4)
        let tab = TabModel()
        XCTAssertNil(registry.webView(for: tab))
    }

    func testEvictsLeastRecentlyUsedBeyondCapacity() {
        let registry = PageWebViewRegistry(capacity: 2)
        let a = TabModel()
        let b = TabModel()
        let c = TabModel()
        registry.set(WKWebView(), for: a)
        registry.set(WKWebView(), for: b)
        // Touching A makes B the least-recently-used, so inserting C evicts B.
        _ = registry.webView(for: a)
        registry.set(WKWebView(), for: c)

        XCTAssertNotNil(registry.webView(for: a), "A was recently used → retained")
        XCTAssertNil(registry.webView(for: b), "B was least-recently-used → evicted")
        XCTAssertNotNil(registry.webView(for: c))
        XCTAssertEqual(registry.count, 2, "count never exceeds capacity")
    }

    func testRemoveDropsEntry() {
        let registry = PageWebViewRegistry(capacity: 4)
        let tab = TabModel()
        registry.set(WKWebView(), for: tab)
        registry.remove(tab: tab)
        XCTAssertNil(registry.webView(for: tab))
        XCTAssertEqual(registry.count, 0)
    }

    func testRemoveAllClearsEverything() {
        let registry = PageWebViewRegistry(capacity: 4)
        let a = TabModel()
        let b = TabModel()
        registry.set(WKWebView(), for: a)
        registry.set(WKWebView(), for: b)
        registry.removeAll()
        XCTAssertEqual(registry.count, 0)
    }

    func testSessionClosesLastTabClearsRegistry() async {
        let session = BrowserSession()
        await session.start()
        // start() seeds one blank tab; closing it opens a new one, so the registry (mirroring
        // live tabs) is never left with an orphan entry once tabs are empty.
        let tab = session.activeTab!
        PageWebViewRegistry.shared.set(WKWebView(), for: tab)
        session.closeTab(tab)
        // After closing the only tab, a fresh one is created; the closed tab's entry is gone.
        XCTAssertNil(PageWebViewRegistry.shared.webView(for: tab),
                     "closing a tab must drop its web-view entry")
        PageWebViewRegistry.shared.removeAll()
    }
}
