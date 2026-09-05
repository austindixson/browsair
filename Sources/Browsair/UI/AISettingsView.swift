import SwiftUI

struct AISettingsView: View {
    @State private var provider: AIProviderID = .xai
    @State private var model = AIProviderConfiguration.xai.model
    @State private var availableModels: [String] = [AIProviderConfiguration.xai.model]
    @State private var isLoadingModels = false
    @State private var apiKey = ""
    @State private var saved = false
    private let credentials = KeychainCredentialStore()
    private let oauthRegistry = OAuthAccountRegistry(store: KeychainCredentialStore())
    @State private var selectedOAuthAccountID: String?
    @State private var oauthAccounts: [OAuthAccount] = []
    @State private var oauthClientID = ""
    @State private var oauthMessage: String?
    private let oauthConnector = OAuthConnectCoordinator(registry: OAuthAccountRegistry(store: KeychainCredentialStore()))

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(AIProviderID.allCases, id: \.self) { id in Text(id.displayName).tag(id) }
            }
            Text(AIProviderCatalog.status(for: provider, credentialStore: credentials).label)
                .font(.caption).foregroundStyle(.secondary)
            OAuthAccountPicker(provider: OAuthProvider(rawValue: provider.rawValue)!, registry: oauthRegistry, accounts: oauthAccounts, selectedAccountID: $selectedOAuthAccountID)
            HStack {
                Button("Connect OAuth…") {
                    Task {
                        do {
                            let result = try await oauthConnector.connect(provider: OAuthProvider(rawValue: provider.rawValue)!, clientID: oauthClientID)
                            if case .connected(let accountID) = result {
                                selectedOAuthAccountID = accountID
                                refreshAccounts()
                                await loadModels(accountID: accountID)
                            }
                            oauthMessage = result == .openedOfficialLogin ? "Official login opened. Enter a client ID to complete OAuth setup." : "Authorization completed and account saved."
                        } catch { oauthMessage = error.localizedDescription }
                    }
                }
                TextField("OAuth client ID (optional)", text: $oauthClientID)
            }
            if let oauthMessage { Text(oauthMessage).font(.caption).foregroundStyle(.secondary) }
            Picker("Model", selection: $model) {
                ForEach(availableModels, id: \.self) { Text($0).tag($0) }
            }
            if isLoadingModels { ProgressView("Loading models…") }
            SecureField("API key", text: $apiKey)
            HStack {
                Button("Save key") { save() }
                if saved { Text("Saved in Keychain").foregroundStyle(.secondary) }
            }
            Text("Browsair checks only its own Keychain entries. It never reads browser cookies or scrapes provider websites. Consumer subscription OAuth is shown only when an official provider flow is available.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520, height: 430, alignment: .topLeading)
        .fixedSize()
        .onChange(of: provider) { _, newProvider in
            model = AIProviderCatalog.configuration(for: newProvider).model
            availableModels = [model]
            selectedOAuthAccountID = nil
            refreshAccounts()
        }
        .onAppear { refreshAccounts() }
        .onChange(of: selectedOAuthAccountID) { _, newID in
            guard let newID else { return }
            Task { await loadModels(accountID: newID) }
        }
    }

    private func refreshAccounts() {
        oauthAccounts = oauthRegistry.availableAccounts(for: OAuthProvider(rawValue: provider.rawValue)!)
    }

    private func loadModels(accountID: String) async {
        guard let token = try? oauthRegistry.accessToken(for: accountID), !token.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let configuration = AIProviderCatalog.configuration(for: provider)
            let discovered = try await ModelCatalogService().models(configuration: configuration, accessToken: token)
            if !discovered.isEmpty { availableModels = discovered; model = discovered.first! }
        } catch { oauthMessage = "Connected, but model discovery failed: \(error.localizedDescription)" }
    }

    private func save() {
        let key = AIProviderCatalog.configuration(for: provider).credentialKey
        do { try credentials.save(apiKey, for: key); apiKey = ""; saved = true } catch { saved = false }
    }
}
