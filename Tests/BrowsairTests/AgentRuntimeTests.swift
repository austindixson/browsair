import XCTest
@testable import Browsair

@MainActor
final class AgentRuntimeTests: XCTestCase {
    func testGetStateAndNavigateUseTheSessionNotAnEngine() async throws {
        let session = BrowserSession()
        await session.start()
        let bridge = AgentBridge()

        let idle = await bridge.execute(.getState, session: session)
        guard case .ok(let startState) = idle else {
            return XCTFail("expected ok state, got \(idle)")
        }
        XCTAssertEqual(startState.url, "")
        XCTAssertFalse(startState.isLoading)

        let navigated = await bridge.execute(.navigate(url: "https://example.com"), session: session)
        guard case .ok(let state) = navigated else {
            return XCTFail("expected ok state, got \(navigated)")
        }
        XCTAssertEqual(state.url, "https://example.com")
        XCTAssertEqual(session.activeTab?.pageCommand, .load("https://example.com"))
    }

    func testReloadBackAndForwardDispatchToTheActiveTab() async {
        let session = BrowserSession()
        await session.start()
        let tab = session.activeTab!
        await session.navigate(tab: tab, to: "https://example.com")
        let bridge = AgentBridge()

        _ = await bridge.execute(.reload, session: session)
        XCTAssertEqual(tab.pageCommand, .reload)
        _ = await bridge.execute(.back, session: session)
        XCTAssertEqual(tab.pageCommand, .back)
        _ = await bridge.execute(.forward, session: session)
        XCTAssertEqual(tab.pageCommand, .forward)
    }

    func testInspectAndReadPageTextFailClosedWithoutAPageSurface() async throws {
        let session = BrowserSession()
        await session.start()
        let bridge = AgentBridge()
        let request = try InspectRequest.decode(json: #"{"command":"inspect","selector":"main"}"#)

        let inspect = await bridge.execute(.inspect(request: request), session: session)
        let text = await bridge.execute(.readPageText, session: session)
        guard case .error = inspect else { return XCTFail("inspect must fail without a WebView") }
        guard case .error = text else { return XCTFail("readPageText must fail without a WebView") }
    }

    func testUnknownCommandsStayRejectedByTheProtocol() {
        XCTAssertThrowsError(try AgentCommand.decode(json: #"{"command":"Runtime.evaluate"}"#))
        XCTAssertThrowsError(try AgentCommand.decode(json: #"{"command":"Page.captureScreenshot"}"#))
    }
}
