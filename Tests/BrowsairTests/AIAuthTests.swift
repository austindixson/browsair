import XCTest
@testable import Browsair

final class AIAuthTests: XCTestCase {
    func testProviderCatalogDoesNotPretendConsumerSubscriptionsAreAvailable() {
        XCTAssertEqual(AIProviderCatalog.status(for: .xai, credentialStore: MemoryCredentialStore()), .apiKeyRequired)
        XCTAssertEqual(AIProviderCatalog.status(for: .openAI, credentialStore: MemoryCredentialStore()), .apiKeyRequired)
        XCTAssertEqual(AIProviderCatalog.status(for: .anthropic, credentialStore: MemoryCredentialStore()), .apiKeyRequired)
    }

    func testConfiguredAPIKeyIsDetectedWithoutReturningTheSecret() throws {
        let store = MemoryCredentialStore()
        try store.save("secret", for: AIProviderConfiguration.xai.credentialKey)
        XCTAssertEqual(AIProviderCatalog.status(for: .xai, credentialStore: store), .apiKeyConfigured)
    }
}
