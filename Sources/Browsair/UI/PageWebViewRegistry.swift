import WebKit

/// A bounded, LRU-evicting store of the live `WKWebView` for each tab.
///
/// `AISidebarView` used to keep a plain static `[ObjectIdentifier: WKWebView]` that only shrank
/// when a tab was closed explicitly. Tabs closed via the OS window button (which never calls
/// `closeTab`) leaked their web view forever — unbounded memory and a stale view handed back to a
/// recycled tab model. This registry evicts the least-recently-used entry past `capacity` and
/// drops every entry for a tab on close, and clears entirely when no tabs remain.
///
/// Not `@unchecked Sendable`: callers are already main-actor (`AISidebarView`, `PageSurfaceView`).
enum WebViewRegistryLimits {
    /// Default LRU bound. Nonisolated so it can serve as the `init` default argument.
    static let defaultCapacity = 64
}

@MainActor
final class PageWebViewRegistry {
    static let shared = PageWebViewRegistry()

    let capacity: Int
    private var entries: [ObjectIdentifier: WKWebView] = [:]
    /// Oldest-first access order; the front is evicted when `capacity` is exceeded.
    private var order: [ObjectIdentifier] = []

    init(capacity: Int = WebViewRegistryLimits.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    var count: Int { entries.count }

    /// Insert or refresh a web view for a tab, marking it most-recently-used and evicting
    /// least-recently-used entries beyond capacity.
    func set(_ webView: WKWebView, for tab: TabModel) {
        let key = ObjectIdentifier(tab)
        if entries[key] != nil { order.removeAll { $0 == key } }
        entries[key] = webView
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries[evicted] = nil
        }
    }

    /// Look up a tab's web view, refreshing its recency.
    func webView(for tab: TabModel) -> WKWebView? {
        let key = ObjectIdentifier(tab)
        guard let webView = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return webView
    }

    /// Drop every entry for a tab (called on close).
    func remove(tab: TabModel) {
        let key = ObjectIdentifier(tab)
        entries[key] = nil
        order.removeAll { $0 == key }
    }

    /// Drop all entries (called when the last tab closes).
    func removeAll() {
        entries.removeAll()
        order.removeAll()
    }
}
