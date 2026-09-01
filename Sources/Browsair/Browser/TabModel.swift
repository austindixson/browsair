import AppKit
import Foundation

@MainActor
final class TabModel: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var addressText: String = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var frameImage: NSImage?
    @Published var errorMessage: String?
    @Published var isStartPage = true

    var targetId: String?
    var sessionId: String?
    var viewportWidth: Int = 1280
    var viewportHeight: Int = 800
    var deviceScaleFactor: Double = 2.0

    private var lastFrameHash: Int = 0
    var frameDirty = true

    func noteFrame(_ data: Data) {
        let hash = data.hashValue
        frameDirty = hash != lastFrameHash
        lastFrameHash = hash
        if let image = NSImage(data: data) {
            frameImage = image
        }
    }
}
