import Foundation

struct AIService: Sendable {
    let client: any AIProviderClient
    let credentials: any CredentialStore

    init(client: any AIProviderClient = OpenAICompatibleClient(), credentials: any CredentialStore = KeychainCredentialStore()) {
        self.client = client
        self.credentials = credentials
    }

    func complete(configuration: AIProviderConfiguration, messages: [ChatMessage]) async throws -> String {
        guard let key = try credentials.value(for: configuration.credentialKey), !key.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        return try await client.complete(configuration: configuration, messages: messages, apiKey: key)
    }
}

enum AIServiceError: LocalizedError {
    case missingAPIKey
    var errorDescription: String? {
        switch self { case .missingAPIKey: return "No API key configured for this AI provider." }
    }
}

final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func save(_ value: String, for key: String) throws { values[key] = value }
    func value(for key: String) throws -> String? { values[key] }
    func delete(_ key: String) throws { values.removeValue(forKey: key) }
}
