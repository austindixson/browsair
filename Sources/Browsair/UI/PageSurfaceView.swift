import AppKit
import SwiftUI
import WebKit

struct PageSurfaceView: View {
    @ObservedObject var tab: TabModel
    @ObservedObject var session: BrowserSession

    var body: some View {
        Group {
            if tab.isStartPage {
                NewTabView(session: session, tab: tab)
            } else {
                WebPageView(tab: tab, session: session)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = tab.errorMessage {
                Text(error)
                    .padding(8)
                    .background(.red.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

private struct WebPageView: NSViewRepresentable {
    @ObservedObject var tab: TabModel
    @ObservedObject var session: BrowserSession

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab, session: session) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        context.coordinator.agentBridge.webView = webView
        context.coordinator.installPrivacyRules(on: webView)
        context.coordinator.consumeInitialLoad()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.tab = tab
        context.coordinator.session = session
        context.coordinator.webView = webView
        context.coordinator.agentBridge.webView = webView
        context.coordinator.applyPageCommand()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var tab: TabModel
        var session: BrowserSession
        weak var webView: WKWebView?
        let agentBridge = AgentBridge()
        private var lastLoadedURL = ""

        init(tab: TabModel, session: BrowserSession) {
            self.tab = tab
            self.session = session
        }

        func installPrivacyRules(on webView: WKWebView) {
            let rules = PrivacyPolicy.shared.contentBlockerJSON
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "browsair.privacy",
                encodedContentRuleList: rules
            ) { list, _ in
                guard let list else { return }
                webView.configuration.userContentController.add(list)
            }
        }

        func consumeInitialLoad() {
            if case .load(let url) = tab.pageCommand, url == tab.urlString {
                tab.pageCommand = nil
            }
            loadCurrentURL()
        }

        func applyPageCommand() {
            guard let command = tab.pageCommand else { return }
            tab.pageCommand = nil
            switch command {
            case .load(let urlString):
                lastLoadedURL = urlString
                if let url = URL(string: urlString) {
                    webView?.load(URLRequest(url: url))
                }
            case .reload:
                webView?.reload()
            case .back:
                webView?.goBack()
            case .forward:
                webView?.goForward()
            case .stop:
                webView?.stopLoading()
            }
        }

        func loadCurrentURL() {
            guard !tab.isStartPage,
                  let url = URL(string: tab.urlString),
                  url.scheme == "http" || url.scheme == "https",
                  tab.urlString != lastLoadedURL else { return }
            lastLoadedURL = tab.urlString
            webView?.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            tab.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.isLoading = false
            tab.urlString = webView.url?.absoluteString ?? tab.urlString
            tab.addressText = tab.urlString
            tab.title = webView.title?.isEmpty == false ? webView.title! : tab.urlString
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            tab.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            tab.errorMessage = error.localizedDescription
        }
    }
}
