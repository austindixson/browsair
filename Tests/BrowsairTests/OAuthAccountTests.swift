import XCTest
@testable import Browsair

final class OAuthAccountTests: XCTestCase {
    func testRegistryDiscoversOnlyValidRegisteredOAuthAccounts() throws {
        let store = MemoryCredentialStore()
        let registry = OAuthAccountRegistry(store: store)
        try registry.save(OAuthAccount(provider: .xai, id: "grok-1", label: "me@example.com"), accessToken: "token")
        XCTAssertEqual(registry.accounts(for: .xai).map(\.label), ["me@example.com"])
        XCTAssertTrue(registry.accounts(for: .openAI).isEmpty)
    }

    func testSelectingAccountReturnsTokenOnlyInternally() throws {
        let store = MemoryCredentialStore()
        let registry = OAuthAccountRegistry(store: store)
        try registry.save(OAuthAccount(provider: .openAI, id: "chat-1", label: "OpenAI account"), accessToken: "secret")
        XCTAssertEqual(try registry.accessToken(for: "chat-1"), "secret")
    }

    func testExpiredAccountsAreNotAvailable() throws {
        let store = MemoryCredentialStore()
        let registry = OAuthAccountRegistry(store: store)
        let account = OAuthAccount(provider: .xai, id: "expired", label: "Expired", expiresAt: Date().addingTimeInterval(-1))
        try registry.save(account, accessToken: "token")
        XCTAssertTrue(registry.availableAccounts(for: .xai).isEmpty)
    }
}
