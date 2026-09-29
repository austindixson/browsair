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

    func testContentBlockerRulesUseHostUrlFilters() throws {
        let data = try XCTUnwrap(PrivacyPolicy.shared.contentBlockerJSON.data(using: .utf8))
        let rules = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let filters = rules.compactMap { rule -> String? in
            let trigger = rule["trigger"] as? [String: Any]
            return trigger?["url-filter"] as? String
        }
        // Resource filters match complete URLs, not bare hostnames.
        XCTAssertTrue(filters.contains(try XCTUnwrap(PrivacyPolicy.hostFilterRegex(for: "google-analytics.com"))), "got \(filters)")
        XCTAssertFalse(filters.contains(".*"), "tracker rules must not match every URL")
    }

    // MARK: - Per-site privacy allowlist

    func testBlockingIsOnByDefault() {
        let policy = PrivacyPolicy(defaults: nil)
        XCTAssertTrue(policy.blocksThirdPartyTrackers, "blocking is on by default")
        // Allowlisting a site keeps global blocking on; the exemption is per-site.
        policy.allowTracking(forSite: "news.site.com")
        XCTAssertTrue(policy.blocksThirdPartyTrackers)
    }

    func testAllowedSiteIsNotBlocked() {
        let policy = PrivacyPolicy(defaults: nil)
        policy.allowTracking(forSite: "news.site.com")
        let tracker = URL(string: "https://www.google-analytics.com/collect")!
        XCTAssertFalse(policy.shouldBlock(url: tracker, firstPartyHost: "news.site.com"),
                       "trackers must load on an allowlisted site")
    }

    func testUnlistedSiteStillBlocked() {
        let policy = PrivacyPolicy(defaults: nil)
        policy.allowTracking(forSite: "news.site.com")
        let tracker = URL(string: "https://www.google-analytics.com/collect")!
        XCTAssertTrue(policy.shouldBlock(url: tracker, firstPartyHost: "other.site.com"))
    }

    func testAllowlistCoversHostAndSubdomainsOnly() {
        let policy = PrivacyPolicy(defaults: nil)
        policy.allowTracking(forSite: "www.news.site.com")
        // The stored host itself is covered…
        XCTAssertTrue(policy.isTrackingAllowed(forHost: "www.news.site.com"))
        // …as are hosts beneath it…
        XCTAssertTrue(policy.isTrackingAllowed(forHost: "deep.www.news.site.com"))
        // …but sibling hosts under the same parent are not.
        XCTAssertFalse(policy.isTrackingAllowed(forHost: "other.site.com"))
        XCTAssertFalse(policy.isTrackingAllowed(forHost: "news.site.com"))
    }

    func testRevokeRestoresBlocking() {
        let policy = PrivacyPolicy(defaults: nil)
        policy.allowTracking(forSite: "news.site.com")
        policy.revokeTracking(forSite: "news.site.com")
        XCTAssertNil(policy.lastAllowedSite)
        let tracker = URL(string: "https://www.google-analytics.com/collect")!
        XCTAssertTrue(policy.shouldBlock(url: tracker, firstPartyHost: "news.site.com"))
    }

    func testAllowedSitesRoundTrip() {
        let policy = PrivacyPolicy(defaults: nil)
        policy.allowTracking(forSite: "a.com")
        policy.allowTracking(forSite: "b.org")
        XCTAssertEqual(policy.allowedSites.count, 2)
    }

    // MARK: - Beacon endpoints on shared domains

    /// `facebook.com/tr` is the beacon endpoint. It must be blocked even when the page we are
    /// on *is* facebook.com (first-party), because the endpoint is not a document. The rest of
    /// facebook.com must stay reachable — blocking the whole domain breaks first-party sign-in.
    func testFacebookBeaconEndpointBlockedEvenFirstParty() {
        let policy = PrivacyPolicy(defaults: nil)
        XCTAssertTrue(policy.shouldBlock(url: URL(string: "https://www.facebook.com/tr?id=1")!,
                                         firstPartyHost: "facebook.com"),
                      "the /tr beacon is not a first-party document")
        XCTAssertFalse(policy.shouldBlock(url: URL(string: "https://www.facebook.com/")!,
                                          firstPartyHost: "facebook.com"))
        XCTAssertFalse(policy.shouldBlock(url: URL(string: "https://www.facebook.com/login")!,
                                          firstPartyHost: "facebook.com"))
    }

    /// The declarative rules cover the tracker hosts; the endpoint rule cannot be expressed
    /// declaratively in this WebKit version, so it must NOT leak into the rules JSON.
    func testEndpointRuleStaysOutOfDeclarativeJSON() throws {
        let json = PrivacyPolicy(defaults: nil).contentBlockerJSON
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        for rule in rules {
            let filter = ((rule["trigger"] as? [String: Any])?["url-filter"] as? String) ?? ""
            XCTAssertFalse(filter.contains("facebook\\.com"),
                           "blocking all of facebook.com declaratively would break sign-in: \(filter)")
        }
    }

    // MARK: - Allowlist persistence (PR 2.3)

    /// A fresh instance reading the same suite must see what a previous instance stored —
    /// otherwise the "Allow trackers on this site" button only works until relaunch.
    func testAllowlistPersistsAcrossInstances() {
        let (suite, name) = Self.makeSuite()
        let first = PrivacyPolicy(defaults: suite)
        first.allowTracking(forSite: "news.site.com")

        let second = PrivacyPolicy(defaults: suite)
        XCTAssertTrue(second.isTrackingAllowed(forHost: "news.site.com"),
                      "allowlisted site must survive a relaunch")
        XCTAssertFalse(second.shouldBlock(url: URL(string: "https://www.google-analytics.com/collect")!,
                                          firstPartyHost: "news.site.com"))
        Self.tearDown(suite: suite, name: name)
    }

    func testRevokePersistsAcrossInstances() {
        let (suite, name) = Self.makeSuite()
        let first = PrivacyPolicy(defaults: suite)
        first.allowTracking(forSite: "news.site.com")
        first.revokeTracking(forSite: "news.site.com")

        let second = PrivacyPolicy(defaults: suite)
        XCTAssertFalse(second.isTrackingAllowed(forHost: "news.site.com"),
                       "revoked site must stay revoked after a relaunch")
        XCTAssertTrue(second.shouldBlock(url: URL(string: "https://www.google-analytics.com/collect")!,
                                         firstPartyHost: "news.site.com"))
        Self.tearDown(suite: suite, name: name)
    }

    /// An instance built with no suite keeps the default in-memory behaviour: the shared
    /// singleton must not leak allowlisted sites into an isolated test instance.
    func testIsolatedInstanceIgnoresSharedState() {
        PrivacyPolicy.shared.allowTracking(forSite: "leak.example.com")
        let isolated = PrivacyPolicy(defaults: nil)
        XCTAssertFalse(isolated.isTrackingAllowed(forHost: "leak.example.com"))
        PrivacyPolicy.shared.revokeTracking(forSite: "leak.example.com")
    }

    func testLoadedAllowlistIsLowercasedAndDeduped() {
        let (suite, name) = Self.makeSuite()
        suite.set(["News.Site.com", "news.site.com", "a.org"], forKey: PrivacyPolicy.allowlistDefaultsKey)
        let policy = PrivacyPolicy(defaults: suite)
        XCTAssertEqual(policy.allowedSites, Set(["news.site.com", "a.org"]))
        Self.tearDown(suite: suite, name: name)
    }

    /// Private helper: an isolated named suite that never touches the app's real defaults.
    private static func makeSuite() -> (UserDefaults, String) {
        let name = "BrowsairTests.PrivacyPolicy.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return (suite, name)
    }

    private static func tearDown(suite: UserDefaults, name: String) {
        suite.removePersistentDomain(forName: name)
    }
}
