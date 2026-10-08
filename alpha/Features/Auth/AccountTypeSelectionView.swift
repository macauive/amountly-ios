import SwiftUI

// New accounts match the web's solo-business setup. Existing personal and
// organization accounts retain their saved profile and permissions.
struct AccountTypeSelectionView: View {
    let email: String
    let userName: String
    @EnvironmentObject private var appState: AppState
    @State private var busy = false
    @State private var error: String?
    @State private var businessRecovery = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Set up your solo business").font(.largeTitle.bold())
                Text("Keep client invoices and expenses together in Amountly.")
                Label("Capture receipts and review expense drafts", systemImage: "receipt")
                Label("Create invoices for client work", systemImage: "doc.text")
                Label("Track billable work and business finances", systemImage: "clock")
                if let error { Text(error).foregroundStyle(.red) }
                Button("Set up my solo business") { Task { await setup() } }.buttonStyle(.borderedProminent).disabled(busy)
                if busy { ProgressView() }
                Spacer()
            }.padding()
                .fullScreenCover(isPresented: $businessRecovery) { OnboardingView(userName: userName) }
        }
    }
    private func setup() async {
        guard !busy else { return }; busy = true; error = nil; appState.beginSignIn()
        defer { busy = false; appState.endSignIn() }
        do {
            let user = try await AuthService.shared.createPersonalUser(name: userName, accountType: .freelancer)
            if user.accountType == .business && user.organizationId == nil { businessRecovery = true; return }
            var organization: Organization?
            if let id = user.organizationId { organization = try await AuthService.shared.getOrganization(id) }
            appState.login(user: user, organization: organization)
        } catch { self.error = "Could not finish setting up your account. Please try again." }
    }
}
