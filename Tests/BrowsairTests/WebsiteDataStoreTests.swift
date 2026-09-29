import XCTest
@testable import Browsair

/// Pins the persistent website-data store location and the previously-silent error strings.
@MainActor
final class WebsiteDataStoreTests: XCTestCase {

    func testPersistentStoreURLIsKeyedOnBundleIdentifier() throws {
        // The store location is derived from the bundle id WebKit keys on. Under `swift test` the
        // host is `com.apple.dt.xctest.tool`, so that is what the path must reflect — proving the
        // path tracks the identity rather than a hardcoded "Application Support/Browsair" folder
        // that WebKit never reads (the old, vacuous assertion).
        let bundleID = try XCTUnwrap(WebsiteDataStoreLocation.resolvedBundleIdentifier(environment: [:]))
        let path = try XCTUnwrap(WebsiteDataStoreSupport.persistentStoreURL()).path
        XCTAssertTrue(path.contains(bundleID), "path must be keyed on the resolved bundle id \(bundleID): \(path)")
        XCTAssertTrue(path.hasSuffix("WebsiteData"), "store dir must be named WebsiteData: \(path)")
    }

    func testPersistentStoreURLIsStable() {
        // A churning path breaks cookie persistence across launches (and Keychain ACLs).
        XCTAssertEqual(WebsiteDataStoreSupport.persistentStoreURL(), WebsiteDataStoreSupport.persistentStoreURL())
    }

    func testProvisionalErrorDistinguishesUnreachableHost() {
        let notFound = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                               userInfo: [NSURLErrorFailingURLStringErrorKey: "https://nope.invalid"])
        let message = PageSurfaceError.pageMessage(forProvisionalError: notFound)
        let lower = message.lowercased()
        XCTAssertTrue(lower.contains("can't") || lower.contains("cannot") || lower.contains("unreachable"),
                      "user must see a real reason, not the previous empty string: \(message)")
    }

    func testProvisionalErrorDistinguishesBadCertificate() {
        let cert = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
                           userInfo: [NSURLErrorFailingURLStringErrorKey: "https://badssl.test"])
        let message = PageSurfaceError.pageMessage(forProvisionalError: cert)
        XCTAssertTrue(message.lowercased().contains("secure") || message.lowercased().contains("certificate"),
                      message)
    }

    func testContentProcessTerminatedMessageIsActionable() {
        let message = PageSurfaceError.contentProcessTerminatedMessage
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.lowercased().contains("reload") || message.lowercased().contains("crash"), message)
    }
}

/// Pins the *real* mechanics of cookie persistence (audit F3 / PR 1.3): the bundle identifier
/// WebKit keys persistent storage on, and the system paths it uses. The earlier tests here only
/// asserted that an "Application Support/Browsair/WebsiteData" path string was stable — a path
/// WebKit never actually reads — so they proved nothing about login sessions surviving relaunch.
/// These exercise the resolution logic that governs whether persistence is possible at all.
final class WebsiteDataStoreLocationTests: XCTestCase {

    // MARK: bundle identifier resolution

    func testResolvedBundleIdentifierUsesOverrideWhenPresent() {
        let id = WebsiteDataStoreLocation.resolvedBundleIdentifier(
            bundle: .main,
            environment: [WebsiteDataStoreLocation.bundleIDOverrideEnvironmentKey: "dev.ghost64.browsair"]
        )
        XCTAssertEqual(id, "dev.ghost64.browsair")
    }

    func testResolvedBundleIdentifierIgnoresBlankOverride() {
        // A blank/whitespace override must not masquerade as a valid identity.
        let id = WebsiteDataStoreLocation.resolvedBundleIdentifier(
            bundle: .main,
            environment: [WebsiteDataStoreLocation.bundleIDOverrideEnvironmentKey: "   "]
        )
        // Falls back to the real host bundle id (never "   ").
        XCTAssertNotEqual(id, "   ")
    }

    func testResolvedBundleIdentifierFallsBackToBundleWhenNoOverride() {
        let id = WebsiteDataStoreLocation.resolvedBundleIdentifier(bundle: .main, environment: [:])
        // The identity must come from the bundle itself, not fabricate one.
        XCTAssertEqual(id, Bundle.main.bundleIdentifier)
    }

    // MARK: persistence readiness

    func testNoIdentityMeansNoPersistence() {
        // The bare swift-build-binary case: no bundle id ⇒ cookies are lost on quit.
        XCTAssertFalse(WebsiteDataStoreLocation.hasPersistentIdentity(nil))
        XCTAssertFalse(WebsiteDataStoreLocation.hasPersistentIdentity(""))
        XCTAssertFalse(WebsiteDataStoreLocation.hasPersistentIdentity("   "))
    }

    func testRealIdentityMeansPersistence() {
        XCTAssertTrue(WebsiteDataStoreLocation.hasPersistentIdentity("dev.ghost64.browsair"))
    }

    // MARK: system paths

    func testCookieURLPointsAtHTTPStoragesBinaryCookies() {
        let url = WebsiteDataStoreLocation.cookieStorageURL(bundleID: "dev.ghost64.browsair")
        XCTAssertTrue(url.path.hasSuffix("Library/HTTPStorages/dev.ghost64.browsair.binarycookies"),
                      "cookies live under ~/Library/HTTPStorages/<bundle-id>.binarycookies, not Application Support: \(url.path)")
    }

    func testWebKitWebsiteDataURLPointsAtBundleScopedWebsiteData() {
        let url = WebsiteDataStoreLocation.webKitWebsiteDataURL(bundleID: "dev.ghost64.browsair")
        XCTAssertTrue(url.path.hasSuffix("Library/WebKit/dev.ghost64.browsair/WebsiteData"),
                      "LocalStorage/IndexedDB live under ~/Library/WebKit/<bundle-id>/WebsiteData: \(url.path)")
    }

    func testPathsAreKeyedByBundleIdentifier() {
        // A different bundle id must resolve to a different location — this is exactly why a
        // churning/absent identifier breaks persistence across launches.
        let a = WebsiteDataStoreLocation.cookieStorageURL(bundleID: "dev.ghost64.browsair")
        let b = WebsiteDataStoreLocation.cookieStorageURL(bundleID: "dev.ghost64.browsair.debug")
        XCTAssertNotEqual(a, b)
    }
}
