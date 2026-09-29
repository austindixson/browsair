import SwiftUI
import WebKit

struct AISidebarView: View {
    @ObservedObject var session: BrowserSession
    @State private var prompt = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSending = false
    @State private var error: String?
    private let service = AIService()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Ask Browsair", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button("Clear") { messages.removeAll() }
                    .disabled(messages.isEmpty)
            }.padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(message.role == .user ? "You" : "Browsair")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Text(message.content).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding()
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            HStack(alignment: .bottom) {
                TextField("Ask about this page…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }.padding()
        }.frame(minWidth: 300, idealWidth: 340)
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        messages.append(.init(role: .user, content: text))
        isSending = true
        error = nil
        Task {
            do {
                let tab = session.activeTab
                // Actually read the page so the model isn't promised context that was never supplied.
                let pageText = await PageTextExtractor.sanitize(Self.extractPageText(from: tab))
                let context = AIContextPolicy.make(selectedText: tab?.selectedText,
                                                   inspectedText: nil,
                                                   pageText: pageText.isEmpty ? nil : pageText,
                                                   url: tab?.urlString,
                                                   title: tab?.title)
                let last = messages.last?.content ?? text
                let requestMessages = [ChatMessage(role: .system, content: "You are a concise browser assistant. Use only the supplied page context.\n\(context)"),
                                       ChatMessage(role: .user, content: last)]
                let answer = try await service.complete(configuration: .xai, messages: requestMessages)
                messages.append(.init(role: .assistant, content: answer))
            } catch let requestError { self.error = requestError.localizedDescription }
            isSending = false
        }
    }

    /// Best-effort live page text for the active tab. Returns "" when there is no page surface
    /// (start page, no tab, or the web view isn't attached yet).
    private static func extractPageText(from tab: TabModel?) async -> String {
        guard let tab, let webView = PageWebViewRegistry.shared.webView(for: tab) else { return "" }
        do {
            let result = try await webView.evaluateJavaScript(
                "document.body ? document.body.innerText : ''") as? String
            return result ?? ""
        } catch {
            return ""
        }
    }
}
