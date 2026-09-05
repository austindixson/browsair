import Foundation

enum PageCommand: Equatable {
    case load(String)
    case reload
    case back
    case forward
    case stop
}

@MainActor
final class TabModel: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var addressText: String = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    @Published var isStartPage = true
    @Published var pageCommand: PageCommand?
}
