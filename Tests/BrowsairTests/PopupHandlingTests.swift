import XCTest
import WebKit
@testable import Browsair

/// The interactive WKWebView previously implemented no WKUIDelegate, so `window.open`
/// popup requests (Google/GitHub/Apple "Sign in with…" consent windows) were silently
/// dropped. These tests pin the pure presentation decision and the session wiring.
@MainActor
final class PopupHandlingTests: XCTestCase {

    func testDefaultWindowPolicyOpensPopupAsTab() {
        // window.open → .newTab; target=_blank links arrive here too.
        XCTAssertEqual(WebKitUIDelegate.windowPolicy(for: nil, requiresUserInteraction: true), .newTab)
    }

    func testTargetBlankWithoutUserInteractionStillOpens() {
        // WKNavigation can mark _blank without user interaction; still honor it.
        XCTAssertEqual(WebKitUIDelegate.windowPolicy(for: nil, requiresUserInteraction: false), .newTab)
    }

    func testPanelPolicyIsHandledNotDropped() {
        // A source web view (target=_blank link) still becomes a new tab.
        XCTAssertEqual(WebKitUIDelegate.windowPolicy(for: WKWebView(), requiresUserInteraction: true), .newTab)
    }

    func testOpenPopupFromURLActivatesANewTab() async {
        let session = BrowserSession()
        await session.start()
        let before = session.tabs.count

        session.openPopup(from: URL(string: "https://accounts.google.com/o/oauth2/auth?x=1"))

        XCTAssertEqual(session.tabs.count, before + 1, "popup must open a new tab")
        let tab = session.activeTab
        XCTAssertEqual(tab?.urlString, "https://accounts.google.com/o/oauth2/auth?x=1")
        XCTAssertEqual(tab?.pageCommand, .load("https://accounts.google.com/o/oauth2/auth?x=1"))
        XCTAssertEqual(session.activeTabID, tab?.id, "popup tab must become active so the user sees it")
    }

    func testOpenPopupWithoutURLNavigatesCurrentTab() async {
        let session = BrowserSession()
        await session.start()
        // No source URL: fall back to the current tab rather than dropping the request.
        session.openPopup(from: nil, fallback: "https://example.com")
        XCTAssertEqual(session.activeTab?.urlString, "https://example.com")
    }

    func testBareWindowOpenOpensABlankPopupTab() async {
        // window.open() with no URL (location set later) must still get a visible tab.
        let session = BrowserSession()
        await session.start()
        let before = session.tabs.count
        session.openPopup(from: nil)
        XCTAssertEqual(session.tabs.count, before + 1, "bare window.open must open a blank popup tab")
    }

    // MARK: - Popup size (audit F2: windowFeatures were ignored)

    func testPopupSizeHonorsRequestedDimensions() {
        let size = WebViewFactory.resolvePopupSize(requested: CGSize(width: 640, height: 480))
        XCTAssertEqual(size.width, 640, accuracy: 0.5)
        XCTAssertEqual(size.height, 480, accuracy: 0.5)
    }

    func testPopupSizeFallsBackWhenUnset() {
        // windowFeatures with no explicit size (nil / zero) → default popup size.
        let size = WebViewFactory.resolvePopupSize(requested: nil)
        XCTAssertEqual(size.width, WebViewFactory.defaultPopupWidth, accuracy: 0.5)
        XCTAssertEqual(size.height, WebViewFactory.defaultPopupHeight, accuracy: 0.5)
    }

    func testPopupSizeClampsAbsurdValues() {
        let big = WebViewFactory.resolvePopupSize(requested: CGSize(width: 999999, height: -5))
        XCTAssertLessThanOrEqual(big.width, WebViewFactory.maxPopupDimension)
        XCTAssertGreaterThan(big.height, 0)

        let tiny = WebViewFactory.resolvePopupSize(requested: CGSize(width: 1, height: 1))
        XCTAssertGreaterThanOrEqual(tiny.width, WebViewFactory.minPopupDimension)
        XCTAssertGreaterThanOrEqual(tiny.height, WebViewFactory.minPopupDimension)
    }

    // MARK: - Factory produces a usable, configured view (audit F2: view was returned as nil)

    func testMakePopupViewReturnsConfiguredWebView() {
        let view = WebViewFactory.makePopupView(configuration: WKWebViewConfiguration())
        // The core fix (F2): a real, non-zero view exists to hand back to WebKit (was nil).
        XCTAssertGreaterThan(view.frame.width, 0, "popup view must have a real, non-zero frame")
        XCTAssertGreaterThan(view.frame.height, 0, "popup view must have a real, non-zero frame")
    }
}
