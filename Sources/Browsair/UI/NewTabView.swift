import SwiftUI

struct NewTabView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var tab: TabModel

    private let suggestions = [
        ("Example", "https://example.com"),
        ("Wikipedia", "https://wikipedia.org"),
        ("DuckDuckGo", "https://duckduckgo.com"),
        ("Obscura", "https://obscura.sh"),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "safari")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text("Browsair")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text("Mac-native browser · powered by Obscura")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search or enter address", text: $tab.addressText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await session.submitAddressBar() }
                    }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 520)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(suggestions, id: \.1) { item in
                    Button {
                        tab.addressText = item.1
                        Task { await session.navigate(tab: tab, to: item.1) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.title2)
                            Text(item.0)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 520)

            Spacer()
            Text(session.engineStatus)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .padding(32)
    }
}
