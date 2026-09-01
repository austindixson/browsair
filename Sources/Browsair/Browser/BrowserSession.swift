import AppKit
import Foundation

@MainActor
final class BrowserSession: ObservableObject {
    @Published var tabs: [TabModel] = []
    @Published var activeTabID: TabModel.ID?
    @Published var engineStatus: String = "Starting Obscura…"
    @Published var engineReady = false
    @Published var fatalError: String?

    private let engine = EngineProcess()
    private let cdp = CDPClient()
    private var screenshotTask: Task<Void, Never>?
    private var port: Int = 0

    var activeTab: TabModel? {
        tabs.first { $0.id == activeTabID }
    }

    func start() async {
        do {
            port = try await engine.start()
            let ws = try await CDPClient.fetchDebuggerURL(port: port)
            try await cdp.connect(to: ws)
            await cdp.onEvent { [weak self] method, params, sessionId in
                Task { @MainActor in
                    self?.handleEvent(method: method, params: params, sessionId: sessionId)
                }
            }
            engineStatus = "Obscura ready · port \(port)"
            engineReady = true
            await openTab(navigateTo: nil)
            startScreenshotLoop()
        } catch {
            fatalError = error.localizedDescription
            engineStatus = "Engine failed"
            engineReady = false
        }
    }

    func shutdown() {
        screenshotTask?.cancel()
        screenshotTask = nil
        Task {
            await cdp.disconnect()
        }
        engine.stop()
    }

    // MARK: - Tabs

    @discardableResult
    func openTab(navigateTo url: String?) async -> TabModel {
        let tab = TabModel()
        tabs.append(tab)
        activeTabID = tab.id

        do {
            let created = try await cdp.send(
                "Target.createTarget",
                params: ["url": "about:blank"]
            )
            guard let targetId = created["targetId"] as? String else {
                throw CDPClientError.unexpected("createTarget missing targetId")
            }
            tab.targetId = targetId

            let attached = try await cdp.send(
                "Target.attachToTarget",
                params: [
                    "targetId": targetId,
                    "flatten": true,
                ]
            )
            let sessionId = (attached["sessionId"] as? String) ?? "\(targetId)-session"
            tab.sessionId = sessionId

            try await cdp.send("Page.enable", sessionId: sessionId)
            try await cdp.send("Runtime.enable", sessionId: sessionId)
            try await applyViewport(for: tab)

            if let url, !url.isEmpty {
                await navigate(tab: tab, to: url)
            }
        } catch {
            tab.errorMessage = error.localizedDescription
        }
        return tab
    }

    func closeTab(_ tab: TabModel) {
        if let targetId = tab.targetId {
            Task {
                try? await cdp.send("Target.closeTarget", params: ["targetId": targetId])
            }
        }
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
        tab.frameDirty = true
    }

    // MARK: - Navigation

    func submitAddressBar() async {
        guard let tab = activeTab else { return }
        let raw = tab.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let url = Self.normalizeURL(raw)
        await navigate(tab: tab, to: url)
    }

    func navigate(tab: TabModel, to url: String) async {
        guard let sessionId = tab.sessionId else { return }
        tab.isStartPage = false
        tab.isLoading = true
        tab.errorMessage = nil
        tab.urlString = url
        tab.addressText = url
        tab.frameDirty = true

        do {
            try await applyViewport(for: tab)
            _ = try await cdp.send(
                "Page.navigate",
                params: ["url": url],
                sessionId: sessionId,
                timeout: 60
            )
            try await Task.sleep(nanoseconds: 200_000_000)
            await refreshTitle(tab)
            await refreshHistory(tab)
            await captureFrame(tab)
        } catch {
            tab.errorMessage = error.localizedDescription
        }
        tab.isLoading = false
    }

    func reload() async {
        guard let tab = activeTab, let sessionId = tab.sessionId else { return }
        tab.isLoading = true
        defer { tab.isLoading = false }
        do {
            _ = try await cdp.send("Page.reload", params: ["ignoreCache": false], sessionId: sessionId)
            tab.frameDirty = true
            try await Task.sleep(nanoseconds: 200_000_000)
            await refreshTitle(tab)
            await captureFrame(tab)
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }

    func goBack() async {
        guard let tab = activeTab else { return }
        await navigateHistory(tab: tab, delta: -1)
    }

    func goForward() async {
        guard let tab = activeTab else { return }
        await navigateHistory(tab: tab, delta: 1)
    }

    private func navigateHistory(tab: TabModel, delta: Int) async {
        guard let sessionId = tab.sessionId else { return }
        do {
            let history = try await cdp.send("Page.getNavigationHistory", sessionId: sessionId)
            let currentIndex = history["currentIndex"] as? Int ?? 0
            let entries = history["entries"] as? [[String: Any]] ?? []
            let next = currentIndex + delta
            guard next >= 0, next < entries.count, let idValue = entries[next]["id"] else { return }
            tab.isLoading = true
            defer { tab.isLoading = false }
            _ = try await cdp.send(
                "Page.navigateToHistoryEntry",
                params: ["entryId": idValue],
                sessionId: sessionId
            )
            try await Task.sleep(nanoseconds: 200_000_000)
            await refreshTitle(tab)
            await refreshHistory(tab)
            tab.frameDirty = true
            await captureFrame(tab)
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Viewport / frames / input

    func updateViewport(width: CGFloat, height: CGFloat, scale: CGFloat) {
        guard let tab = activeTab else { return }
        let w = max(Int(width.rounded()), 320)
        let h = max(Int(height.rounded()), 240)
        let s = Double(max(scale, 1))
        if tab.viewportWidth == w, tab.viewportHeight == h, abs(tab.deviceScaleFactor - s) < 0.01 {
            return
        }
        tab.viewportWidth = w
        tab.viewportHeight = h
        tab.deviceScaleFactor = s
        tab.frameDirty = true
        Task { try? await applyViewport(for: tab) }
    }

    func applyViewport(for tab: TabModel) async throws {
        guard let sessionId = tab.sessionId else { return }
        _ = try await cdp.send(
            "Emulation.setDeviceMetricsOverride",
            params: [
                "width": tab.viewportWidth,
                "height": tab.viewportHeight,
                "deviceScaleFactor": tab.deviceScaleFactor,
                "mobile": false,
            ],
            sessionId: sessionId
        )
    }

    func handleClick(at point: CGPoint, clickCount: Int = 1) {
        guard let tab = activeTab, let sessionId = tab.sessionId else { return }
        let x = Double(point.x)
        let y = Double(point.y)
        Task {
            _ = try? await cdp.send(
                "Input.dispatchMouseEvent",
                params: [
                    "type": "mousePressed",
                    "x": x,
                    "y": y,
                    "button": "left",
                    "clickCount": clickCount,
                ],
                sessionId: sessionId
            )
            _ = try? await cdp.send(
                "Input.dispatchMouseEvent",
                params: [
                    "type": "mouseReleased",
                    "x": x,
                    "y": y,
                    "button": "left",
                    "clickCount": clickCount,
                ],
                sessionId: sessionId
            )
            tab.frameDirty = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            await refreshTitle(tab)
            await refreshHistory(tab)
        }
    }

    func handleScroll(deltaY: CGFloat, at point: CGPoint) {
        guard let tab = activeTab, let sessionId = tab.sessionId else { return }
        Task {
            _ = try? await cdp.send(
                "Input.dispatchMouseEvent",
                params: [
                    "type": "mouseWheel",
                    "x": Double(point.x),
                    "y": Double(point.y),
                    "deltaX": 0,
                    "deltaY": Double(deltaY),
                ],
                sessionId: sessionId
            )
            tab.frameDirty = true
        }
    }

    func handleKey(characters: String, key: String, code: String, modifiers: Int = 0, isDown: Bool) {
        guard let tab = activeTab, let sessionId = tab.sessionId else { return }
        Task {
            var params: [String: Any] = [
                "type": isDown ? "keyDown" : "keyUp",
                "key": key,
                "code": code,
                "modifiers": modifiers,
            ]
            if isDown, !characters.isEmpty {
                params["text"] = characters
                params["unmodifiedText"] = characters
                params["type"] = characters.count == 1 ? "keyDown" : "keyDown"
            }
            _ = try? await cdp.send("Input.dispatchKeyEvent", params: params, sessionId: sessionId)
            if isDown, !characters.isEmpty {
                _ = try? await cdp.send(
                    "Input.dispatchKeyEvent",
                    params: [
                        "type": "char",
                        "text": characters,
                        "unmodifiedText": characters,
                        "key": key,
                        "code": code,
                        "modifiers": modifiers,
                    ],
                    sessionId: sessionId
                )
            }
            tab.frameDirty = true
        }
    }

    // MARK: - Internals

    private func startScreenshotLoop() {
        screenshotTask?.cancel()
        screenshotTask = Task { [weak self] in
            var idle = false
            while !Task.isCancelled {
                guard let self else { return }
                let delay: UInt64 = idle ? 800_000_000 : 200_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard let tab = self.activeTab, !tab.isStartPage, tab.sessionId != nil else {
                    idle = true
                    continue
                }
                await self.captureFrame(tab)
                idle = !tab.frameDirty
            }
        }
    }

    private func captureFrame(_ tab: TabModel) async {
        guard let sessionId = tab.sessionId else { return }
        do {
            let result = try await cdp.send(
                "Page.captureScreenshot",
                params: [
                    "format": "jpeg",
                    "quality": 70,
                    "fromSurface": true,
                ],
                sessionId: sessionId,
                timeout: 10
            )
            guard let b64 = result["data"] as? String,
                  let data = Data(base64Encoded: b64)
            else { return }
            tab.noteFrame(data)
        } catch {
            // Soft-fail; keep UI alive
        }
    }

    private func refreshTitle(_ tab: TabModel) async {
        guard let sessionId = tab.sessionId else { return }
        do {
            let result = try await cdp.send(
                "Runtime.evaluate",
                params: [
                    "expression": "document.title || location.href",
                    "returnByValue": true,
                ],
                sessionId: sessionId
            )
            if let value = (result["result"] as? [String: Any])?["value"] as? String, !value.isEmpty {
                tab.title = value
            }
            let urlResult = try await cdp.send(
                "Runtime.evaluate",
                params: [
                    "expression": "location.href",
                    "returnByValue": true,
                ],
                sessionId: sessionId
            )
            if let href = (urlResult["result"] as? [String: Any])?["value"] as? String {
                tab.urlString = href
                if !tab.addressText.contains(" ") {
                    tab.addressText = href
                }
            }
        } catch {}
    }

    private func refreshHistory(_ tab: TabModel) async {
        guard let sessionId = tab.sessionId else { return }
        do {
            let history = try await cdp.send("Page.getNavigationHistory", sessionId: sessionId)
            let currentIndex = history["currentIndex"] as? Int ?? 0
            let entries = history["entries"] as? [Any] ?? []
            tab.canGoBack = currentIndex > 0
            tab.canGoForward = currentIndex + 1 < entries.count
        } catch {
            tab.canGoBack = false
            tab.canGoForward = false
        }
    }

    private func handleEvent(method: String, params: [String: Any]?, sessionId: String?) {
        guard let tab = tabs.first(where: { $0.sessionId == sessionId }) ?? activeTab else { return }
        switch method {
        case "Page.frameNavigated":
            tab.frameDirty = true
            tab.isLoading = true
            if let frame = params?["frame"] as? [String: Any], let url = frame["url"] as? String {
                tab.urlString = url
                tab.addressText = url
                tab.isStartPage = false
            }
        case "Page.loadEventFired", "Page.domContentEventFired":
            tab.isLoading = false
            tab.frameDirty = true
            Task {
                await refreshTitle(tab)
                await refreshHistory(tab)
            }
        case "Page.lifecycleEvent":
            if let name = params?["name"] as? String, name == "load" || name == "networkIdle" {
                tab.isLoading = false
                tab.frameDirty = true
            }
        default:
            break
        }
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
