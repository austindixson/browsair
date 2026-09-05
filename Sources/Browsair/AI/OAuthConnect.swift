import Foundation
import Network
import AppKit
import CryptoKit

enum OAuthConnectResult: Equatable { case connected(accountID: String), openedOfficialLogin }

enum OAuthConnectError: LocalizedError {
    case missingClientID, callbackFailed, stateMismatch, tokenExchangeFailed
    var errorDescription: String? {
        switch self {
        case .missingClientID: return "This provider has no configured OAuth client."
        case .callbackFailed: return "OAuth authorization did not return a valid callback."
        case .stateMismatch: return "OAuth state validation failed. Please try again."
        case .tokenExchangeFailed: return "The provider rejected the OAuth token exchange."
        }
    }
}

struct OAuthProviderMetadata {
    let provider: OAuthProvider
    let displayName: String
    let authorizationURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: String
}

extension OAuthProvider {
    var metadata: OAuthProviderMetadata {
        switch self {
        case .xai:
            return .init(provider: self, displayName: "Grok / SuperGrok", authorizationURL: URL(string: "https://auth.x.ai/oauth2/authorize")!, tokenURL: URL(string: "https://auth.x.ai/oauth2/token")!, clientID: "b1a00492-073a-47ea-816f-4c329264a828", scopes: "openid profile email offline_access grok-cli:access api:access")
        case .openAI:
            return .init(provider: self, displayName: "OpenAI", authorizationURL: URL(string: "https://auth.openai.com/oauth/authorize")!, tokenURL: URL(string: "https://auth.openai.com/oauth/token")!, clientID: "", scopes: "openid profile offline_access")
        case .anthropic:
            return .init(provider: self, displayName: "Claude", authorizationURL: URL(string: "https://claude.ai/oauth/authorize")!, tokenURL: URL(string: "https://claude.ai/oauth/token")!, clientID: "", scopes: "openid profile offline_access")
        }
    }
    var displayName: String { metadata.displayName }
    var authorizationURL: URL { metadata.authorizationURL }
}

struct OAuthAuthorizationRequest {
    let url: URL
    let verifier: String
    let state: String

    init(provider: OAuthProvider, clientID: String, redirectURI: String) throws {
        guard !clientID.isEmpty else { throw OAuthConnectError.missingClientID }
        let verifier = Self.randomString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let state = Self.randomString(length: 32)
        var components = URLComponents(url: provider.authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: provider.metadata.scopes),
            .init(name: "state", value: state), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "nonce", value: Self.randomString(length: 32))
        ]
        guard let url = components?.url else { throw OAuthConnectError.callbackFailed }
        self.url = url; self.verifier = verifier; self.state = state
    }

    init(provider: OAuthProvider, clientID: String, redirectURI: String, state: String, codeChallenge: String) throws {
        guard !clientID.isEmpty else { throw OAuthConnectError.missingClientID }
        var components = URLComponents(url: provider.authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: provider.metadata.scopes),
            .init(name: "state", value: state), .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw OAuthConnectError.callbackFailed }
        self.url = url; self.verifier = codeChallenge; self.state = state
    }

    private static func randomString(length: Int) -> String {
        (0..<length).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! }.reduce(into: "", { $0.append($1) })
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let idToken: String?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", idToken = "id_token" }
}

private final class LoopbackOAuthServer: @unchecked Sendable {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private(set) var redirectURI = ""

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed = state { self?.finish(error: OAuthConnectError.callbackFailed) }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
                self.listener = listener
                listener.start(queue: .main)
                // The port is available after the listener enters the ready state.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard let port = listener.port?.rawValue else { self.finish(error: OAuthConnectError.callbackFailed); return }
                    self.redirectURI = "http://127.0.0.1:\(port)/callback"
                    continuation.resume(returning: URL(string: self.redirectURI)!)
                    self.continuation = nil
                }
            } catch { continuation.resume(throwing: error); self.continuation = nil }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation }
    }

    func stop() { listener?.cancel(); listener = nil }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.components(separatedBy: "\r\n").first,
                  let path = line.split(separator: " ").dropFirst().first,
                  let url = URL(string: "http://localhost\(path)") else { return }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<html><body>You may return to Browsair.</body></html>"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            self.finish(url: url)
        }
    }

    private func finish(url: URL) { listener?.cancel(); listener = nil; continuation?.resume(returning: url); continuation = nil }
    private func finish(error: Error) { listener?.cancel(); listener = nil; continuation?.resume(throwing: error); continuation = nil }
}

@MainActor
final class OAuthConnectCoordinator {
    private let registry: OAuthAccountRegistry
    private var callbackServer: LoopbackOAuthServer?
    init(registry: OAuthAccountRegistry) { self.registry = registry }

    @discardableResult
    func connect(provider: OAuthProvider, clientID: String = "", redirectURI: String = "") async throws -> OAuthConnectResult {
        let effectiveClientID = clientID.isEmpty ? provider.metadata.clientID : clientID
        guard !effectiveClientID.isEmpty else { throw OAuthConnectError.missingClientID }
        let server = LoopbackOAuthServer()
        callbackServer = server
        let callback = try await server.start()
        let request = try OAuthAuthorizationRequest(provider: provider, clientID: effectiveClientID, redirectURI: callback.absoluteString)
        guard NSWorkspace.shared.open(request.url) else { throw OAuthConnectError.callbackFailed }
        let callbackURL = try await server.waitForCallback()
        defer { callbackServer = nil; server.stop() }
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard components?.queryItems?.first(where: { $0.name == "state" })?.value == request.state,
              let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else { throw OAuthConnectError.stateMismatch }
        let token = try await exchange(code: code, provider: provider, clientID: effectiveClientID, redirectURI: callback.absoluteString, verifier: request.verifier)
        let accountID = token.idToken.flatMap(Self.subject(from:)) ?? UUID().uuidString
        let account = OAuthAccount(provider: provider, id: accountID, label: "Signed-in \(provider.displayName)", expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) })
        try registry.save(account, accessToken: token.accessToken)
        if let refreshToken = token.refreshToken { try registry.saveRefreshToken(refreshToken, for: accountID) }
        return .connected(accountID: accountID)
    }

    private func exchange(code: String, provider: OAuthProvider, clientID: String, redirectURI: String, verifier: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: provider.metadata.tokenURL); request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents(); components.queryItems = [.init(name: "grant_type", value: "authorization_code"), .init(name: "client_id", value: clientID), .init(name: "code", value: code), .init(name: "redirect_uri", value: redirectURI), .init(name: "code_verifier", value: verifier)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw OAuthConnectError.tokenExchangeFailed }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private static func subject(from token: String) -> String? {
        let parts = token.split(separator: "."); guard parts.count > 1 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["sub"] as? String ?? object["email"] as? String
    }
}
