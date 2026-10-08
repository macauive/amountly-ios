import SwiftUI

struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var otp = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var requested = false
    @State private var complete = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(requested)
                if requested && !complete {
                    TextField("6-digit code", text: $otp).textContentType(.oneTimeCode).keyboardType(.numberPad)
                    SecureField("New password (12–128 characters)", text: $password).textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
                }
                if complete { Text("Password reset. Sign in with your new password.") }
                else {
                    Button(requested ? "Reset password" : "Request reset code") { Task { await submit() } }
                        .disabled(busy || email.isEmpty || (requested && (otp.count != 6 || !(12...128).contains(password.count) || password != confirmation)))
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Reset Password")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func submit() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            if requested { try await AuthService.shared.resetPassword(email: email, otp: otp, password: password); password = ""; confirmation = ""; otp = ""; complete = true }
            else { try await AuthService.shared.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines)); requested = true }
        } catch { self.error = "Could not complete the password reset. Check your details and try again." }
    }
}
