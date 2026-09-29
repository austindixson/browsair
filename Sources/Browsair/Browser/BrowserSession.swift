import AppKit

@MainActor
final class BrowserSession: ObservableObject {
    @Published var tabs: [TabModel] = []
    @Published var activeTabID: TabModel.ID?
    @Published var engineStatus: String = "WebKit"
    @Published var engineReady = false
    @Published var fatalError: String?
    @Published var isAISidebarVisible = false

    var activeTab: TabModel? {
        tabs.first { $0.id == activeTabID }
    }

    func start() async {
        engineStatus = "WebKit"
        engineReady = true
        if tabs.isEmpty {
            await openTab(navigateTo: nil)
        }
    }

    func shutdown() {}

    // MARK: - Tabs

    @discardableResult
    func openTab(navigateTo url: String?) async -> TabModel {
        let tab = TabModel()
        tabs.append(tab)
        activeTabID = tab.id
        if let url, !url.isEmpty {
            await navigate(tab: tab, to: url)
        }
        return tab
    }

    func closeTab(_ tab: TabModel) {
        tabs.removeAll { $0.id == tab.id }
        PageWebViewRegistry.shared.remove(tab: tab)
        pageBindings[ObjectIdentifier(tab)] = nil
        if activeTabID == tab.id {
            activeTabID = tabs.last?.id
        }
        if tabs.isEmpty {
            PageWebViewRegistry.shared.removeAll()
            pageBindings.removeAll()
            Task { await openTab(navigateTo: nil) }
        }
    }

    func selectTab(_ tab: TabModel) {
        activeTabID = tab.id
    }

    // MARK: - Tab switching (keyboard shortcuts)

    /// Select the Nth tab (1-based, for ⌘1…⌘9). Out-of-range is ignored.
    func selectTab(number: Int) {
        guard number >= 1, number <= tabs.count else { return }
        activeTabID = tabs[number - 1].id
    }

    func selectLastTab() {
        guard let last = tabs.last else { return }
        activeTabID = last.id
    }

    func selectNextTab() {
        guard !tabs.isEmpty else { return }
        let idx = tabs.firstIndex { $0.id == activeTabID } ?? 0
        activeTabID = tabs[(idx + 1) % tabs.count].id
    }

    func selectPreviousTab() {
        guard !tabs.isEmpty else { return }
        let idx = tabs.firstIndex { $0.id == activeTabID } ?? 0
        activeTabID = tabs[(idx - 1 + tabs.count) % tabs.count].id
    }

    /// Whether tab-switching shortcuts can move focus off the (single) tab.
    var canSwitchTabs: Bool { tabs.count > 1 }

    // MARK: - Popups (window.open / target=_blank)

    /// Present a popup request as a new, active tab so the user can actually see and complete
    /// the flow (OAuth consent windows). Falls back to the current tab if there is no source URL.
    /// Appends/activates synchronously; the page load itself is driven by the tab's view.
    @discardableResult
    func openPopup(from url: URL?, fallback: String? = nil) -> TabModel {
        if url == nil, let fallback, !fallback.isEmpty, let current = activeTab {
            // No source URL: reuse the current tab rather than dropping the request.
            current.isStartPage = false
            current.isLoading = true
            current.urlString = fallback
            current.addressText = fallback
            current.pageCommand = .load(fallback)
            return current
        }
        let tab = TabModel()
        tabs.append(tab)
        activeTabID = tab.id
        if let target = url?.absoluteString, !target.isEmpty {
            tab.isStartPage = false
            tab.isLoading = true
            tab.urlString = target
            tab.addressText = target
            tab.pageCommand = .load(target)
        }
        return tab
    }

    // MARK: - Navigation

    func submitAddressBar() async {
        guard let tab = activeTab else { return }
        let raw = tab.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let result = URLQueryResult.classify(raw, current: tab.isStartPage ? nil : tab.urlString)
        switch result.scheme {
        case .navigate, .search:
            await navigate(tab: tab, to: result.value)
        case .external:
            if let url = result.url { NSWorkspace.shared.open(url) }
            tab.addressText = tab.isStartPage ? "" : tab.urlString
        case .empty:
            break
        }
    }

    func navigate(tab: TabModel, to url: String) async {
        tab.isStartPage = false
        tab.isLoading = true
        tab.errorMessage = nil
        tab.urlString = url
        tab.addressText = url
        tab.pageCommand = .load(url)
    }

    func reload() async {
        guard let tab = activeTab, !tab.isStartPage else { return }
        tab.isLoading = true
        tab.pageCommand = .reload
    }

    func goBack() async {
        activeTab?.pageCommand = .back
    }

    func goForward() async {
        activeTab?.pageCommand = .forward
    }

    /// Atomically read and clear a tab's pending page command. `applyPageCommand()` uses this so
    /// a command is applied at most once — previously a re-entrant `updateNSView` (triggered by the
    /// `@Published` writes in `didFinish`) could re-dispatch the same `.load`, double-loading pages.
    @discardableResult
    func consumePageCommand(for tab: TabModel) -> PageCommand? {
        defer { tab.pageCommand = nil }
        return tab.pageCommand
    }

    // MARK: - Page binding registry

    /// The navigation coordinator that owns the web view for a tab, registered when SwiftUI
    /// builds the page surface. Lets the popup factory hand a live view to its tab's delegate.
    private var pageBindings: [ObjectIdentifier: PageWebViewBinding] = [:]

    func register(_ binding: PageWebViewBinding, for tab: TabModel) {
        pageBindings[ObjectIdentifier(tab)] = binding
    }

    func pageBinding(for tab: TabModel) -> PageWebViewBinding? {
        pageBindings[ObjectIdentifier(tab)]
    }

    static func normalizeURL(_ raw: String) -> String {
        URLQueryResult.classify(raw).value
    }
}
