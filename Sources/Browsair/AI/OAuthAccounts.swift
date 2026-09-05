import Foundation

enum OAuthProvider: String, Codable, CaseIterable { case xai, openAI, anthropic
    var name: String { switch self { case .xai: "Grok"; case .openAI: "OpenAI"; case .anthropic: "Claude" } }
}

struct OAuthAccount: Codable, Equatable, Identifiable {
    let provider: OAuthProvider
    let id: String
    let label: String
    let expiresAt: Date?

    init(provider: OAuthProvider, id: String, label: String, expiresAt: Date? = nil) {
        self.provider = provider; self.id = id; self.label = label; self.expiresAt = expiresAt
    }

    var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
}

final class OAuthAccountRegistry: @unchecked Sendable {
    private let store: any CredentialStore
    private let accountsKey = "oauth-accounts"
    private let tokenPrefix = "oauth-token-"
    private let refreshPrefix = "oauth-refresh-"

    init(store: any CredentialStore) { self.store = store }

    func accounts(for provider: OAuthProvider) -> [OAuthAccount] {
        (try? loadAccounts().filter { $0.provider == provider }) ?? []
    }

    func availableAccounts(for provider: OAuthProvider) -> [OAuthAccount] {
        accounts(for: provider).filter { !$0.isExpired && (((try? store.value(for: tokenPrefix + $0.id)) ?? nil) != nil) }
    }

    func save(_ account: OAuthAccount, accessToken: String) throws {
        var accounts = try loadAccounts().filter { $0.id != account.id }
        accounts.append(account)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try store.save(String(decoding: try encoder.encode(accounts), as: UTF8.self), for: accountsKey)
        try store.save(accessToken, for: tokenPrefix + account.id)
    }

    func accessToken(for accountID: String) throws -> String? { try store.value(for: tokenPrefix + accountID) }
    func saveRefreshToken(_ token: String, for accountID: String) throws { try store.save(token, for: refreshPrefix + accountID) }
    func refreshToken(for accountID: String) throws -> String? { try store.value(for: refreshPrefix + accountID) }

    private func loadAccounts() throws -> [OAuthAccount] {
        guard let value = try store.value(for: accountsKey), let data = value.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([OAuthAccount].self, from: data)
    }
}
