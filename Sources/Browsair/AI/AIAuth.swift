import Foundation

enum AIProviderID: String, CaseIterable, Codable { case xai, openAI, anthropic
    var displayName: String { switch self { case .xai: "xAI / Grok"; case .openAI: "OpenAI"; case .anthropic: "Anthropic / Claude" } }
}

enum AIAuthStatus: Equatable { case apiKeyConfigured, apiKeyRequired, oauthUnavailable
    var label: String { switch self { case .apiKeyConfigured: "API key configured"; case .apiKeyRequired: "Official OAuth subscription detection is not available; add an API key"; case .oauthUnavailable: "Anthropic does not offer public third-party OAuth for Claude subscriptions" } }
}

enum AIProviderCatalog {
    static func configuration(for id: AIProviderID) -> AIProviderConfiguration {
        switch id {
        case .xai: return .xai
        case .openAI: return .openAI
        case .anthropic: return AIProviderConfiguration(kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!, model: "claude-sonnet-4-5", credentialKey: "anthropic-api-key")
        }
    }

    static func status(for id: AIProviderID, credentialStore: CredentialStore) -> AIAuthStatus {
        let config = configuration(for: id)
        if (try? credentialStore.value(for: config.credentialKey)) ?? "" != "" { return .apiKeyConfigured }
        return .apiKeyRequired
    }
}
