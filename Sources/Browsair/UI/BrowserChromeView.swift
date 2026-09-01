import SwiftUI

struct BrowserChromeView: View {
    @ObservedObject var session: BrowserSession
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            toolbar
            Divider()
            content
        }
        .background(.background)
        .onAppear {
            Task { await session.start() }
        }
        .onDisappear {
            session.shutdown()
        }
        .alert(
            "Engine error",
            isPresented: Binding(
                get: { session.fatalError != nil },
                set: { if !$0 { session.fatalError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.fatalError ?? "")
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(session.tabs) { tab in
                        TabChip(
                            tab: tab,
                            isActive: tab.id == session.activeTabID,
                            onSelect: { session.selectTab(tab) },
                            onClose: { session.closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            Button {
                Task { await session.openTab(navigateTo: nil) }
            } label: {
                Image(systemName: "plus")
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .background(.ultraThinMaterial)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                navButton("chevron.left", enabled: session.activeTab?.canGoBack == true) {
                    Task { await session.goBack() }
                }
                navButton("chevron.right", enabled: session.activeTab?.canGoForward == true) {
                    Task { await session.goForward() }
                }
                navButton(
                    session.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                    enabled: session.activeTab?.isStartPage == false
                ) {
                    Task { await session.reload() }
                }
            }

            if let tab = session.activeTab {
                HStack(spacing: 8) {
                    Image(systemName: tab.isLoading ? "arrow.triangle.2.circlepath" : "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search or enter address", text: Binding(
                        get: { tab.addressText },
                        set: { tab.addressText = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .onSubmit {
                        Task { await session.submitAddressBar() }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            Text(session.engineStatus)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let tab = session.activeTab {
            PageSurfaceView(tab: tab, session: session)
        } else if !session.engineReady {
            VStack(spacing: 12) {
                ProgressView()
                Text(session.engineStatus)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    private func navButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}

private struct TabChip: View {
    @ObservedObject var tab: TabModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 120, maxWidth: 200)
        .background(isActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
    }
}
