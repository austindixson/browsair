import XCTest
@testable import Browsair

final class PrivacyPolicyTests: XCTestCase {
    func testBlocksKnownAnalyticsAndAdvertisingHosts() {
        XCTAssertTrue(PrivacyPolicy.shared.shouldBlock(url: URL(string: "https://www.google-analytics.com/collect")!))
        XCTAssertTrue(PrivacyPolicy.shared.shouldBlock(url: URL(string: "https://ads.example.com/banner.js")!))
        XCTAssertTrue(PrivacyPolicy.shared.shouldBlock(url: URL(string: "https://pixel.facebook.com/tr")!))
    }

    func testAllowsFirstPartyAndNonHTTPURLs() {
        XCTAssertFalse(PrivacyPolicy.shared.shouldBlock(url: URL(string: "https://example.com/app.js")!, firstPartyHost: "example.com"))
        XCTAssertFalse(PrivacyPolicy.shared.shouldBlock(url: URL(string: "about:blank")!))
    }

    func testContentBlockerRulesAreValidJSON() throws {
        let data = try XCTUnwrap(PrivacyPolicy.shared.contentBlockerJSON.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(object is [[String: Any]])
    }

    func testContentBlockerRulesUseSubdomainWildcards() throws {
        let data = try XCTUnwrap(PrivacyPolicy.shared.contentBlockerJSON.data(using: .utf8))
        let rules = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let domains = rules.compactMap { rule -> [String]? in
            let trigger = rule["trigger"] as? [String: Any]
            return trigger?["if-domain"] as? [String]
        }.flatMap { $0 }
        XCTAssertTrue(domains.contains("*google-analytics.com"))
        XCTAssertFalse(domains.contains("*."))
    }
}
