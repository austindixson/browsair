import Foundation

enum AIProviderKind: String, Codable, Equatable { case openAICompatible, anthropic }

struct AIProviderConfiguration: Equatable {
    let kind: AIProviderKind
    let baseURL: URL
    let model: String
    let credentialKey: String

    static let xai = AIProviderConfiguration(kind: .openAICompatible, baseURL: URL(string: "https://api.x.ai/v1")!, model: "grok-4.5", credentialKey: "xai-api-key")
    static let openAI = AIProviderConfiguration(kind: .openAICompatible, baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-4o-mini", credentialKey: "openai-api-key")
}

enum ChatRole: String, Codable { case system, user, assistant }
struct ChatMessage: Codable, Equatable { let role: ChatRole; let content: String }

struct AIRequest: Encodable {
    let messages: [ChatMessage]
    let model: String
    let stream: Bool

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

struct AIContextPolicy {
    static let maximumCharacters = 12_000

    static func make(selectedText: String?, inspectedText: String?, url: String?, title: String?) -> String {
        var parts: [String] = []
        if let url, !url.isEmpty { parts.append("URL: \(url)") }
        if let title, !title.isEmpty { parts.append("Title: \(title)") }
        if let selectedText, !selectedText.isEmpty { parts.append("Selected text:\n\(String(selectedText.prefix(4_000)))") }
        if let inspectedText, !inspectedText.isEmpty { parts.append("Page structure:\n\(String(sanitize(inspectedText).prefix(6_000)))") }
        return String(parts.joined(separator: "\n\n").prefix(maximumCharacters))
    }

    static func sanitize(_ value: String) -> String {
        var result = value
        let patterns = ["(?is)<script.*?</script>", "(?is)<style.*?</style>", "(?i)password\\s*[:=]\\s*[^\\s]+"]
        for pattern in patterns { result = result.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression) }
        return result
    }
}
