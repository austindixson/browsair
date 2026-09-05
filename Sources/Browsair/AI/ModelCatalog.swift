import Foundation

struct ModelCatalogResponse: Decodable {
    struct Model: Decodable { let id: String; let type: String? }
    let data: [Model]

    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    var chatModels: [String] {
        data.filter { model in
            guard let type = model.type?.lowercased() else { return true }
            return !["embedding", "rerank", "moderation", "image"].contains { type.contains($0) }
        }.map(\.id).filter { !$0.isEmpty }.sorted { lhs, rhs in
            let left = Self.versionKey(lhs), right = Self.versionKey(rhs)
            return left == right ? lhs < rhs : Self.isNewer(left, than: right)
        }
    }

    private static func isNewer(_ lhs: [Int], than rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : -1
            let r = index < rhs.count ? rhs[index] : -1
            if l != r { return l > r }
        }
        return false
    }

    private static func versionKey(_ id: String) -> [Int] {
        id.split(separator: "-").flatMap { part in part.split(separator: ".").map { Int($0) ?? -1 } }

    }
}

struct ModelCatalogService: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func models(configuration: AIProviderConfiguration, accessToken: String) async throws -> [String] {
        let url = configuration.baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return try ModelCatalogResponse(data: data).chatModels
    }
}
