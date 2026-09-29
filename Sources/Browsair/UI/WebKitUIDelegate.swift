import AppKit
import WebKit

/// Pure decision for `WKUIDelegate.createWebViewWith`: what to do with a window-open request.
enum WindowOpenPolicy: Equatable {
    /// Open the request in a new Browsair tab (default).
    case newTab
    /// Drop the request.
    case ignore
}

/// Binds a web view to a tab's navigation coordinator. Implemented by `WebPageView.Coordinator`
/// so popup views built outside SwiftUI's `makeNSView` can still adopt their tab's delegate.
protocol PageWebViewBinding: AnyObject {
    @MainActor func bind(_ webView: WKWebView)
}

/// Builds popup `WKWebView`s and resolves their size from `windowFeatures`.
///
/// Previously `createWebViewWith` created a *model* tab but bound a `WKWebView?` that stayed nil
/// and returned it, so WebKit got no view and `windowFeatures` were ignored. This factory returns a
/// real, configured view (UI + navigation delegates) and clamps the requested size to sane bounds.
enum WebViewFactory {
    static let defaultPopupWidth: CGFloat = 900
    static let defaultPopupHeight: CGFloat = 700
    static let minPopupDimension: CGFloat = 320
    static let maxPopupDimension: CGFloat = 4096

    /// Clamp a requested popup size (from `WKWindowFeatures`) to usable bounds; nil/zero → default.
    static func resolvePopupSize(requested: CGSize?) -> CGSize {
        let fallback = CGSize(width: defaultPopupWidth, height: defaultPopupHeight)
        guard let requested, requested.width > 0, requested.height > 0 else { return fallback }
        func clamp(_ v: CGFloat) -> CGFloat {
            Swift.max(minPopupDimension, Swift.min(maxPopupDimension, v))
        }
        return CGSize(width: clamp(requested.width), height: clamp(requested.height))
    }

    /// A fresh WKWebView for a popup, with its delegates attached. On MainActor (AppKit view).
    @MainActor
    static func makePopupView(configuration: WKWebViewConfiguration,
                              uiDelegate: WKUIDelegate? = nil,
                              requestedSize: CGSize? = nil) -> WKWebView {
        let view = WKWebView(frame: CGRect(origin: .zero, size: resolvePopupSize(requested: requestedSize)),
                             configuration: configuration)
        view.uiDelegate = uiDelegate
        return view
    }
}

/// Browsair's `WKUIDelegate`.
///
/// Before this existed the interactive `WKWebView` had no UI delegate, so WebKit silently
/// ignored every `window.open` / `target="_blank"` request — which is exactly how Google,
/// GitHub and Apple "Sign in with…" consent windows were being dropped.
final class WebKitUIDelegate: NSObject, WKUIDelegate {
    weak var session: BrowserSession?

    init(session: BrowserSession?) {
        self.session = session
    }

    /// Decide how to present a window-open request. A popup (no `sourceWebView`) and a
    /// `target="_blank"` link both become a new tab.
    static func windowPolicy(for sourceWebView: WKWebView?, requiresUserInteraction: Bool) -> WindowOpenPolicy {
        .newTab
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard Self.windowPolicy(for: webView, requiresUserInteraction: navigationAction.shouldPerformDownload) == .newTab else {
            return nil
        }

        // Build a real, correctly-sized view up front and hand it back. WebKit loads
        // window.open(url) into whatever we return, so a bare window.open() with no URL
        // (location assigned later) also renders. Returning nil here used to drop it.
        let requestedSize = CGSize(width: windowFeatures.width?.doubleValue ?? 0,
                                   height: windowFeatures.height?.doubleValue ?? 0)
        var popup: WKWebView?
        MainActor.assumeIsolated {
            let view = WebViewFactory.makePopupView(configuration: configuration,
                                                    uiDelegate: self,
                                                    requestedSize: requestedSize)
            popup = view
            if let session, let target = navigationAction.request.url {
                let tab = session.openPopup(from: target)
                if let binding = session.pageBinding(for: tab) {
                    PageSurfaceView.bind(view, to: binding)
                }
            }
        }
        return popup
    }

    // Keep JS alert/confirm/prompt from being silently swallowed too.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.title ?? "Browsair"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.title ?? "Browsair"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
