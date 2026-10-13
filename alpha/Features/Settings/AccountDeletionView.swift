import SwiftUI

struct AccountDeletionView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirming = false
    @State private var busy = false
    @State private var requested = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Delete your Amountly account") {
                Text("Request deletion of your account and associated personal data. Export any records you need before continuing.")
                Text("Mac Digital will complete deletion within 30 days and confirm completion by email. Your account remains active while the request is pending. You do not need to contact support to submit the request.")
                Text("Records that must be retained for legal obligations and temporary backup copies may remain after deletion. Mac Digital will explain any applicable retention when processing your request.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Read the privacy policy", destination: AmountlyLinks.privacy)
            }
            Section {
                if requested {
                    Label("Deletion request recorded", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("account.deletion.success")
                    Text("Mac Digital will process your request within 30 days and email you when deletion is complete.")
                } else {
                    Button("Request account deletion", role: .destructive) { confirming = true }
                        .disabled(busy || !appState.isAuthenticated)
                        .accessibilityIdentifier("account.deletion.request")
                }
                if busy { ProgressView("Submitting request…") }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("account.deletion.error") }
            }
        }
        .navigationTitle("Delete Account")
        .alert("Request account deletion?", isPresented: $confirming) {
            Button("Request deletion", role: .destructive) { Task { await submit() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletion removes your account and associated personal data, subject to required retention. Export your records first. Mac Digital will process the request within 30 days.")
        }
        .onChange(of: appState.currentUser?.id) { _, _ in requested = false; error = nil }
    }

    @MainActor private func submit() async {
        guard !busy, !requested, appState.isAuthenticated, let userID = appState.currentUser?.id else { return }
        let generation = AmountlyPlatform.transport.generation
        busy = true; error = nil
        defer { busy = false }
        do {
            try await AccountDeletionService(transport: AmountlyPlatform.transport).request()
            guard appState.currentUser?.id == userID, AmountlyPlatform.transport.generation == generation else { return }
            requested = true
        } catch {
            guard appState.currentUser?.id == userID, AmountlyPlatform.transport.generation == generation else { return }
            self.error = (error as? PlatformError)?.localizedDescription ?? "Could not record your request. Try again."
        }
    }
}
