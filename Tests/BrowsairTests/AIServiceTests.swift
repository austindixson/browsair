import XCTest
@testable import Browsair

final class AIServiceTests: XCTestCase {
    func testServiceFailsClearlyWhenKeyIsMissing() async {
        let service = AIService(client: StubAIClient(), credentials: MemoryCredentialStore())
        do {
            _ = try await service.complete(configuration: .xai, messages: [])
            XCTFail("Expected missing key")
        } catch let error as AIServiceError {
            XCTAssertEqual(error.errorDescription, "No API key configured for this AI provider.")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testServiceUsesKeychainCredentialWithoutExposingItInMessages() async throws {
        let store = MemoryCredentialStore()
        try store.save("secret", for: AIProviderConfiguration.xai.credentialKey)
        let client = StubAIClient()
        let service = AIService(client: client, credentials: store)
        _ = try await service.complete(configuration: .xai, messages: [.init(role: .user, content: "Hi")])
        XCTAssertEqual(client.lastKey, "secret")
        XCTAssertFalse(client.lastMessages.map(\.content).joined().contains("secret"))
    }
}

final class StubAIClient: AIProviderClient, @unchecked Sendable {
    var lastKey = ""
    var lastMessages: [ChatMessage] = []
    func complete(configuration: AIProviderConfiguration, messages: [ChatMessage], apiKey: String) async throws -> String {
        lastKey = apiKey; lastMessages = messages; return "ok"
    }
}
