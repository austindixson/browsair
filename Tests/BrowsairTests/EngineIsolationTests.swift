import XCTest
@testable import Browsair

@MainActor
final class EngineIsolationTests: XCTestCase {
    func testStartDoesNotRequireObscura() async {
        let session = BrowserSession()
        await session.start()

        XCTAssertTrue(session.engineReady)
        XCTAssertNil(session.fatalError)
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertTrue(session.activeTab?.isStartPage == true)
        XCTAssertFalse(session.engineStatus.lowercased().contains("obscura"))
    }

    func testOpenTabDoesNotCreateEngineTargets() async {
        let session = BrowserSession()
        let tab = await session.openTab(navigateTo: nil)

        XCTAssertTrue(tab.isStartPage)
        XCTAssertNil(tab.errorMessage)
        XCTAssertNil(tab.pageCommand)
    }

    func testNavigateQueuesASurfaceLoadWithoutCDP() async {
        let session = BrowserSession()
        let tab = await session.openTab(navigateTo: nil)

        await session.navigate(tab: tab, to: "https://example.com")

        XCTAssertEqual(tab.urlString, "https://example.com")
        XCTAssertEqual(tab.addressText, "https://example.com")
        XCTAssertFalse(tab.isStartPage)
        XCTAssertTrue(tab.isLoading)
        XCTAssertEqual(tab.pageCommand, .load("https://example.com"))
        XCTAssertNil(tab.errorMessage)
    }

    func testReloadAndHistoryQueueSurfaceCommands() async {
        let session = BrowserSession()
        let tab = await session.openTab(navigateTo: "https://example.com")

        await session.reload()
        XCTAssertEqual(tab.pageCommand, .reload)

        await session.goBack()
        XCTAssertEqual(tab.pageCommand, .back)

        await session.goForward()
        XCTAssertEqual(tab.pageCommand, .forward)
    }

    func testInteractiveSourcesDoNotTalkToObscuraOrScreenshotTransport() throws {
        let files = [
            "Browser/BrowserSession.swift",
            "Browser/TabModel.swift",
            "UI/PageSurfaceView.swift",
            "UI/BrowserChromeView.swift",
        ]
        for relative in files {
            let source = try Self.readSource(relative)
            XCTAssertFalse(source.contains("EngineProcess"), relative)
            XCTAssertFalse(source.contains("CDPClient"), relative)
            XCTAssertFalse(source.contains("captureScreenshot"), relative)
            XCTAssertFalse(source.contains("Input.dispatchMouseEvent"), relative)
            XCTAssertFalse(source.contains("Input.dispatchKeyEvent"), relative)
            XCTAssertFalse(source.contains("frameImage"), relative)
            XCTAssertFalse(source.contains("noteFrame"), relative)
            XCTAssertFalse(source.contains("targetId"), relative)
        }
    }

    func testPageSurfaceInstallsPrivacyRulesAndKeepsWebKitInteractive() throws {
        let source = try Self.readSource("UI/PageSurfaceView.swift")
        XCTAssertTrue(source.contains("WKWebView"))
        XCTAssertTrue(source.contains("PrivacyPolicy"))
        XCTAssertTrue(source.contains("WKContentRuleList"))
        XCTAssertFalse(source.contains("captureScreenshot"))
    }

    private static func readSource(_ relative: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Browsair").appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
