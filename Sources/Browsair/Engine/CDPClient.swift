import Foundation

enum CDPClientError: LocalizedError {
    case notConnected
    case encodingFailed
    case timeout(String)
    case server(CDPErrorBody)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "CDP socket is not connected"
        case .encodingFailed: return "Failed to encode CDP request"
        case .timeout(let method): return "CDP timeout waiting for \(method)"
        case .server(let err): return err.errorDescription
        case .unexpected(let msg): return msg
        }
    }
}

/// Minimal Chrome DevTools Protocol client over a WebSocket.
actor CDPClient {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<CDPResponse, Error>] = [:]
    private var receiveTask: Task<Void, Never>?
    private(set) var isConnected = false
    private var eventHandlers: [@Sendable (String, [String: Any]?, String?) -> Void] = []

    func connect(to url: URL) async throws {
        await disconnect()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.webSocket = task
        task.resume()
        isConnected = true
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        let leftover = pending
        pending.removeAll()
        for (_, cont) in leftover {
            cont.resume(throwing: CDPClientError.notConnected)
        }
    }

    func onEvent(_ handler: @escaping @Sendable (String, [String: Any]?, String?) -> Void) {
        eventHandlers.append(handler)
    }

    @discardableResult
    func send(
        _ method: String,
        params: [String: Any]? = nil,
        sessionId: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> [String: Any] {
        guard let webSocket, isConnected else { throw CDPClientError.notConnected }

        let id = nextID
        nextID += 1

        let request = CDPRequest(id: id, method: method, params: params, sessionId: sessionId)
        let data: Data
        do {
            data = try JSONEncoder().encode(request)
        } catch {
            throw CDPClientError.encodingFailed
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CDPClientError.encodingFailed
        }

        let response: CDPResponse = try await withCheckedThrowingContinuation { cont in
            pending[id] = cont

            Task {
                do {
                    try await webSocket.send(.string(text))
                } catch {
                    if let waiting = await self.takePending(id) {
                        waiting.resume(throwing: error)
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let waiting = await self.takePending(id) {
                    waiting.resume(throwing: CDPClientError.timeout(method))
                }
            }
        }

        if let error = response.error {
            throw CDPClientError.server(error)
        }
        return response.result?.dictionaryValue ?? [:]
    }

    private func takePending(_ id: Int) -> CheckedContinuation<CDPResponse, Error>? {
        pending.removeValue(forKey: id)
    }

    private func receiveLoop() async {
        guard let webSocket else { return }
        while !Task.isCancelled, isConnected {
            do {
                let message = try await webSocket.receive()
                let data: Data
                switch message {
                case .data(let d):
                    data = d
                case .string(let s):
                    guard let d = s.data(using: .utf8) else { continue }
                    data = d
                @unknown default:
                    continue
                }
                handleMessage(data)
            } catch {
                isConnected = false
                let leftover = pending
                pending.removeAll()
                for (_, cont) in leftover {
                    cont.resume(throwing: error)
                }
                break
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let response = try? JSONDecoder().decode(CDPResponse.self, from: data) else { return }

        if let id = response.id, let cont = pending.removeValue(forKey: id) {
            cont.resume(returning: response)
            return
        }

        if let method = response.method {
            let params = response.params?.dictionaryValue
            let sessionId = response.sessionId
            for handler in eventHandlers {
                handler(method, params, sessionId)
            }
        }
    }

    static func fetchDebuggerURL(port: Int) async throws -> URL {
        let url = URL(string: "http://127.0.0.1:\(port)/json/version")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let info = try JSONDecoder().decode(ObscuraVersionInfo.self, from: data)
        guard let ws = URL(string: info.webSocketDebuggerUrl) else {
            throw CDPClientError.unexpected("Bad webSocketDebuggerUrl: \(info.webSocketDebuggerUrl)")
        }
        return ws
    }
}
