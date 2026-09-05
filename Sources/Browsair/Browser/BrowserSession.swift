import Foundation

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
        if activeTabID == tab.id {
            activeTabID = tabs.last?.id
        }
        if tabs.isEmpty {
            Task { await openTab(navigateTo: nil) }
        }
    }

    func selectTab(_ tab: TabModel) {
        activeTabID = tab.id
    }

    // MARK: - Navigation

    func submitAddressBar() async {
        guard let tab = activeTab else { return }
        let raw = tab.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        await navigate(tab: tab, to: Self.normalizeURL(raw))
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

    static func normalizeURL(_ raw: String) -> String {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("about:") {
            return raw
        }
        if raw.contains(" ") || !raw.contains(".") {
            let q = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            return "https://duckduckgo.com/?q=\(q)"
        }
        return "https://\(raw)"
    }
}
