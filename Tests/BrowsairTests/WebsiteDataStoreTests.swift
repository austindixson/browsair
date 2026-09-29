import XCTest
@testable import Browsair

/// Pins the persistent website-data store location and the previously-silent error strings.
@MainActor
final class WebsiteDataStoreTests: XCTestCase {

    func testPersistentStoreURLIsUnderApplicationSupport() throws {
        let url = WebsiteDataStoreSupport.persistentStoreURL()
        let path = url.path
        XCTAssertTrue(path.contains("Browsair"), "store must live under a Browsair folder: \(path)")
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
