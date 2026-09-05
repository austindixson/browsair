import Foundation
import WebKit

@MainActor
final class AgentBridge {
    weak var webView: WKWebView?

    init(webView: WKWebView? = nil) {
        self.webView = webView
    }

    func execute(_ command: AgentCommand, session: BrowserSession) async -> AgentResponse {
        switch command {
        case .getState:
            return .ok(Self.state(from: session))
        case .navigate(let url):
            guard let tab = session.activeTab else { return .error("no tab") }
            await session.navigate(tab: tab, to: url)
            return .ok(Self.state(from: session))
        case .reload:
            await session.reload()
            return .ok(Self.state(from: session))
        case .back:
            await session.goBack()
            return .ok(Self.state(from: session))
        case .forward:
            await session.goForward()
            return .ok(Self.state(from: session))
        case .readPageText:
            return await readPageText(session: session)
        case .inspect(let request):
            do {
                let snapshot = try await inspect(request)
                return .inspect(state: Self.state(from: session), snapshot: snapshot)
            } catch {
                return .error("inspect failed")
            }
        }
    }

    func inspect(_ request: InspectRequest) async throws -> InspectSnapshot {
        guard let webView else { throw AgentProtocolError.invalidInspect }
        let script = try InspectScript.make(request: request)
        let value = try await webView.evaluateJavaScript(script)
        guard let object = value as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else { throw AgentProtocolError.invalidInspect }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try InspectSnapshot.decode(json: String(decoding: data, as: UTF8.self))
    }

    private func readPageText(session: BrowserSession) async -> AgentResponse {
        guard let webView else { return .error("no page") }
        do {
            let value = try await webView.evaluateJavaScript(
                "(document.body && document.body.innerText || '').slice(0, 20000)"
            )
            let text = value as? String ?? ""
            return .pageText(state: Self.state(from: session), text: text)
        } catch {
            return .error("readPageText failed")
        }
    }

    private static func state(from session: BrowserSession) -> AgentState {
        let tab = session.activeTab
        return AgentState(url: tab?.urlString ?? "", title: tab?.title ?? "", isLoading: tab?.isLoading ?? false)
    }
}
