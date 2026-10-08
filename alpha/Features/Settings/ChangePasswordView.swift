import SwiftUI

struct ChangePasswordView: View {
    @State private var current = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            SecureField("Current password", text: $current).textContentType(.password)
            SecureField("New password (12–128 characters)", text: $password).textContentType(.newPassword)
            SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword)
            Text("Changing your password revokes your other Amountly sessions.").font(.caption)
            if let message { Text(message) }
            Button("Change password") { Task { await change() } }
                .disabled(busy || current.isEmpty || !(12...128).contains(password.utf16.count) || password != confirmation)
            if busy { ProgressView() }
        }.navigationTitle("Change Password")
    }
    private func change() async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do {
            try await SupabaseClientManager.shared.client.auth.changePassword(current: current, new: password)
            current = ""; password = ""; confirmation = ""; message = "Password changed. Other sessions have been revoked."
        } catch { message = "Could not change your password. Check your current password and try again." }
    }
}
