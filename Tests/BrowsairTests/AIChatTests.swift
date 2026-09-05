import XCTest
@testable import Browsair

final class AIChatTests: XCTestCase {
    func testXAIConfigurationUsesDocumentedDefaults() {
        let config = AIProviderConfiguration.xai
        XCTAssertEqual(config.baseURL.absoluteString, "https://api.x.ai/v1")
        XCTAssertEqual(config.model, "grok-4.5")
        XCTAssertEqual(config.kind, .openAICompatible)
    }

    func testContextPolicyBoundsAndExcludesSensitiveContent() {
        let context = AIContextPolicy.make(selectedText: String(repeating: "a", count: 20_000), inspectedText: "<script>secret</script> visible", url: "https://example.com", title: "Example")
        XCTAssertLessThanOrEqual(context.count, AIContextPolicy.maximumCharacters)
        XCTAssertFalse(context.contains("secret"))
        XCTAssertTrue(context.contains("visible"))
        XCTAssertTrue(context.contains("https://example.com"))
    }

    func testOpenAICompatibleRequestEncoding() throws {
        let request = AIRequest(messages: [.init(role: .user, content: "Hello")], model: "grok-4.5", stream: true)
        let data = try request.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "grok-4.5")
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertNotNil(object["messages"])
    }
}
