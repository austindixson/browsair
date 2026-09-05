import SwiftUI

struct OAuthAccountPicker: View {
    let provider: OAuthProvider
    let registry: OAuthAccountRegistry
    let accounts: [OAuthAccount]
    @Binding var selectedAccountID: String?

    var body: some View {
        Picker("Signed-in account", selection: $selectedAccountID) {
            Text("Use API key").tag(String?.none)
            ForEach(accounts) { account in
                Text(account.label).tag(Optional(account.id))
            }
        }
    }
}
