import Foundation

protocol AIProviderClient: Sendable {
    func complete(configuration: AIProviderConfiguration, messages: [ChatMessage], apiKey: String) async throws -> String
}

struct OpenAICompatibleClient: AIProviderClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func complete(configuration: AIProviderConfiguration, messages: [ChatMessage], apiKey: String) async throws -> String {
        guard configuration.baseURL.scheme == "https" || configuration.baseURL.host == "localhost" else { throw URLError(.appTransportSecurityRequiresSecureConnection) }
        let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try AIRequest(messages: messages, model: configuration.model, stream: false).encoded()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (((object?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
    }
}
