import XCTest
@testable import Browsair

final class OAuthConnectTests: XCTestCase {
    func testSuperGrokUsesRegisteredOAuthClientAndCorrectEndpoints() {
        XCTAssertEqual(OAuthProvider.xai.metadata.clientID, "b1a00492-073a-47ea-816f-4c329264a828")
        XCTAssertEqual(OAuthProvider.xai.authorizationURL.absoluteString, "https://auth.x.ai/oauth2/authorize")
        XCTAssertEqual(OAuthProvider.xai.metadata.tokenURL.absoluteString, "https://auth.x.ai/oauth2/token")
    }

    func testAuthorizationRequestContainsPKCEAndStateParameters() throws {
        let request = try OAuthAuthorizationRequest(provider: .xai, clientID: "test-client", redirectURI: "browsair://oauth/callback")
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let names = Set(components?.queryItems?.map(\.name) ?? [])
        XCTAssertTrue(names.isSuperset(of: ["client_id", "redirect_uri", "response_type", "scope", "state", "code_challenge", "code_challenge_method", "nonce"]))
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertFalse(request.verifier.isEmpty)
        XCTAssertFalse(request.state.isEmpty)
    }
}
