import XCTest
import WebKit
@testable import Browsair

/// Resource-host matching and third-party scoping for the declarative blocker.
final class ContentBlockerRulesTests: XCTestCase {
    private var rules: [[String: Any]] {
        guard let data = PrivacyPolicy.shared.contentBlockerJSON.data(using: .utf8),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return rules
    }

    func testRuleSetIsNotEmptyAndValidJSON() throws {
        XCTAssertFalse(rules.isEmpty, "expected a non-empty ruleset")
    }

    func testEveryRuleIsThirdPartyOnly() {
        for rule in rules {
            let trigger = rule["trigger"] as? [String: Any]
            let loadType = trigger?["load-type"] as? [String]
            XCTAssertEqual(loadType, ["third-party"],
                           "rule must be third-party-scoped so first-party documents are never blocked: \(rule)")
        }
    }

    func testRulesDoNotRestrictThePageToTrackerDomains() {
        for rule in rules {
            let trigger = rule["trigger"] as? [String: Any]
            XCTAssertNil(trigger?["if-domain"])
            XCTAssertNil(trigger?["unless-domain"])
        }
    }

    func testBlockedHostsAppearInUrlFilters() {
        // A real tracker host must actually be encoded in a url-filter, not just an if-domain.
        let filters = rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        XCTAssertTrue(filters.contains { $0.contains("google-analytics\\.com") },
                      "google-analytics.com must have a real url-filter, got: \(filters)")
    }

    func testLoginHostsAreNeverBlocked() {
        let loginHosts = ["google.com", "microsoftonline.com", "github.com", "appleid.apple.com"]
        for host in loginHosts {
            XCTAssertFalse(PrivacyPolicy.shared.isBlockedAsRule(host: host),
                           "login host \(host) must not have a block rule")
        }
    }

    func testActionIsBlock() {
        for rule in rules {
            XCTAssertEqual((rule["action"] as? [String: Any])?["type"] as? String, "block")
        }
    }

    func testBuildErrorSurfaceIsNilByDefault() {
        XCTAssertNil(PrivacyPolicy.shared.lastBuildError)
    }

    func testHostFilterMatchesTrackerURLsOnly() throws {
        let filter = try XCTUnwrap(PrivacyPolicy.hostFilterRegex(for: "google-analytics.com"))
        let regex = try NSRegularExpression(pattern: filter)
        let matching = [
            "https://google-analytics.com/collect",
            "http://www.google-analytics.com/collect",
            "https://deep.www.google-analytics.com:8443/collect",
        ]
        let nonmatching = [
            "https://google-analytics.com.evil.test/collect",
            "https://notgoogle-analytics.com/collect",
            "https://example.com/google-analytics.com/collect",
            "https://example.com/?url=https://google-analytics.com/collect",
            "https://google-analytics.com@example.com/collect",
            "https://accounts.google.com/login",
        ]
        for url in matching {
            XCTAssertNotNil(regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), url)
        }
        for url in nonmatching {
            XCTAssertNil(regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), url)
        }
    }

    func testHostFilterRejectsInvalidHosts() {
        for host in ["", "ad[nxs].com", "a|b.com", "foo(bar.com", "a/b.com", "a..com", "-a.com"] {
            XCTAssertNil(PrivacyPolicy.hostFilterRegex(for: host), host)
        }
    }

    /// Rule compilation cannot be asserted from the SwiftPM test runner, so it is not asserted
    /// here. `WKContentRuleListStore` only invokes its completion handler when the caller has
    /// real bundle identity (a `.app` bundle); the SwiftPM xctest runner has none, so the
    /// callback never fires. A test using `expectation(description:)` + `waitForExpectations`
    /// would therefore report success while running no assertion at all.
    ///
    /// Verified out-of-band instead: run the app (`swift run Browsair`), which compiles the
    /// shipped JSON and persists it at
    /// `~/Library/WebKit/dev.ghost64.browsair/ContentRuleLists/ContentRuleList-browsair.privacy`.
    /// If the ruleset is ever changed, delete that file first — WebKit reuses a compiled list
    /// by identifier and will not pick up edits otherwise.
    func DISABLED_testGeneratedRulesCompileInWebKit() throws {
        throw XCTSkip("WebKit rule-list callbacks do not fire in the SwiftPM test runner")
    }
}
