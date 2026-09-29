import AppKit
import SwiftUI
import WebKit

struct PageSurfaceView: View {
    @ObservedObject var tab: TabModel
    @ObservedObject var session: BrowserSession

    /// Binds a freshly built web view to a tab by adopting the tab's navigation coordinator.
    /// Used for popup views built before SwiftUI's `makeNSView` runs, so they are not orphaned.
    static func bind(_ webView: WKWebView, to coordinator: PageWebViewBinding) {
        coordinator.bind(webView)
    }

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
        // Persistent store only for http(s) targets. `.default()` is the process-wide non-ephemeral
        // store, but it is only genuinely persistent when the process has a bundle identifier for
        // WebKit to key storage on. A `swift run` binary reports no identifier (audit F3), so its
        // `.default()` data is not durably keyed and login cookies do not survive quit; running the
        // app from a `.app` bundle with CFBundleIdentifier is what makes this persistent. See
        // `WebsiteDataStoreLocation` and `launchWarningIfNotPersistent`.
        let needsPersistentData = (tab.urlString.hasPrefix("http") || tab.urlString.isEmpty)
        configuration.websiteDataStore = needsPersistentData ? .default() : .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // WKUIDelegate turns window.open / target=_blank into a visible tab instead of dropping it.
        webView.uiDelegate = context.coordinator.uiDelegate
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        context.coordinator.agentBridge.webView = webView
        session.register(context.coordinator, for: tab)
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

    final class Coordinator: NSObject, WKNavigationDelegate, PageWebViewBinding {
        var tab: TabModel
        var session: BrowserSession
        weak var webView: WKWebView?
        let agentBridge = AgentBridge()
        lazy var uiDelegate = WebKitUIDelegate(session: session)
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
            ) { [weak self, weak webView] list, error in
                if let error {
                    // Previously the error was discarded with `_`, so a broken ruleset silently
                    // disabled privacy blocking with no way to notice.
                    PrivacyPolicy.shared.noteBuildError("content blocker failed to compile: \(error.localizedDescription)")
                    return
                }
                PrivacyPolicy.shared.noteBuildError(nil)
                guard let list, let controller = webView?.configuration.userContentController else { return }
                controller.removeAllContentRuleLists()
                controller.add(list)
                _ = self
            }
        }

        func bind(_ webView: WKWebView) {
            self.webView = webView
            webView.navigationDelegate = self
            webView.uiDelegate = uiDelegate
            agentBridge.webView = webView
            PageWebViewRegistry.shared.set(webView, for: tab)
            session.register(self, for: tab)
            installPrivacyRules(on: webView)
            loadCurrentURL()
        }

        func consumeInitialLoad() {
            if case .load(let url) = tab.pageCommand, url == tab.urlString {
                tab.pageCommand = nil
            }
            loadCurrentURL()
        }

        func applyPageCommand() {
            // Consume so the command can only ever be applied once, even if updateNSView re-enters.
            guard let command = session.consumePageCommand(for: tab) else { return }
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

        /// First-party-aware tracking block. The declarative ruleset can't express first-party
        /// exemption (and WebKit's regex rejects alternation), so we cancel third-party trackers
        /// here while letting first-party navigations and OAuth login hosts through.
        func webView(_ webView: WKWebView,
                     decide navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let firstParty = tab.urlString.isEmpty ? nil : URL(string: tab.urlString)?.host else {
                decisionHandler(.allow)
                return
            }
            if navigationAction.targetFrame == nil {
                // target=_blank / window.open → handled by WebKitUIDelegate as a new tab.
                decisionHandler(.allow)
                return
            }
            decisionHandler(PrivacyPolicy.shared.shouldBlock(url: url, firstPartyHost: firstParty) ? .cancel : .allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.isLoading = false
            tab.urlString = webView.url?.absoluteString ?? tab.urlString
            tab.addressText = tab.urlString
            tab.title = webView.title?.isEmpty == false ? webView.title! : tab.urlString
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            // Register the live web view so the AI sidebar can read the page on demand.
            PageWebViewRegistry.shared.set(webView, for: tab)
            captureSelection(in: webView)
        }

        private func captureSelection(in webView: WKWebView) {
            webView.evaluateJavaScript("window.getSelection ? String(window.getSelection()) : ''") { [weak self] result, _ in
                guard let self, let text = result as? String else { return }
                self.tab.selectedText = text
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            let message = PageSurfaceError.pageMessage(forProvisionalError: error)
            if !message.isEmpty { tab.errorMessage = message }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            let message = PageSurfaceError.pageMessage(forProvisionalError: error)
            if !message.isEmpty { tab.errorMessage = message }
        }

        /// A crashed or jetsammed WebContent process previously left a stale blank page.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            tab.isLoading = false
            tab.errorMessage = PageSurfaceError.contentProcessTerminatedMessage
        }
    }
}
