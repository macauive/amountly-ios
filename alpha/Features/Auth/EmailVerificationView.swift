//
//  EmailVerificationView.swift
//  alpha
//
//  Created by Claude Code on 12/18/24.
//

import SwiftUI
import Combine
import Auth

@MainActor
class EmailVerificationViewModel: ObservableObject {
    @Published var verificationCode = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSuccessConfirmation = false  // Show success message
    @Published var canProceed = false  // Enable continue button
    @Published var navigateToLogin = false  // Navigate to login after sign out

    let email: String
    private let authService = AuthService.shared

    init(email: String) {
        self.email = email
    }

    func verifyCode() async {
        guard !verificationCode.isEmpty else {
            errorMessage = "Please enter the verification code"
            return
        }

        guard verificationCode.count == 8 else {
            errorMessage = "Verification code must be 8 digits"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("📧 EmailVerificationViewModel: Verifying code for \(email)")
            let session = try await authService.verifyOTP(email: email, token: verificationCode)
            print("✅ EmailVerificationViewModel: Verification successful")
            print("🔐 EmailVerificationViewModel: User ID: \(session.user.id)")
            print("🔐 EmailVerificationViewModel: Email confirmed: \(session.user.emailConfirmedAt != nil)")

            // CRITICAL: Wait and confirm session is fully available before proceeding
            print("⏳ EmailVerificationViewModel: Confirming session availability...")
            var attempts = 0
            let maxAttempts = 5
            var sessionConfirmed = false

            while attempts < maxAttempts {
                if authService.isAuthenticated {
                    sessionConfirmed = true
                    print("✅ EmailVerificationViewModel: Session confirmed on attempt \(attempts + 1)")
                    break
                }

                attempts += 1
                print("⚠️ EmailVerificationViewModel: Attempt \(attempts)/\(maxAttempts) - Session not yet available, waiting...")
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }

            guard sessionConfirmed else {
                print("❌ EmailVerificationViewModel: Session not available after \(maxAttempts) attempts")
                errorMessage = "Authentication session could not be established. Please try logging in manually."
                isLoading = false
                return
            }

            // Double-check by trying to get current session
            guard let currentSession = authService.currentSession else {
                print("❌ EmailVerificationViewModel: Session check failed - currentSession is nil")
                errorMessage = "Authentication error. Please try logging in."
                isLoading = false
                return
            }

            print("✅ EmailVerificationViewModel: Session fully confirmed")
            print("🔐 EmailVerificationViewModel: Current session user: \(currentSession.user.id)")
            print("✅ EmailVerificationViewModel: Email verified successfully!")

            // Show success confirmation instead of immediately navigating
            showSuccessConfirmation = true
            canProceed = true
        } catch {
            print("❌ EmailVerificationViewModel: Verification failed: \(error)")
            if error.localizedDescription.contains("expired") {
                errorMessage = "Verification code expired. Please request a new code."
            } else if error.localizedDescription.contains("invalid") {
                errorMessage = "Invalid verification code. Please check and try again."
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    func proceedToLogin() async {
        print("➡️ EmailVerificationViewModel: User clicked Continue - signing out and proceeding to login")
        isLoading = true

        do {
            // Sign the user out to get a fresh authentication session
            try await authService.signOut()
            print("✅ EmailVerificationViewModel: User signed out successfully")

            // Navigate to login
            navigateToLogin = true
        } catch {
            print("❌ EmailVerificationViewModel: Sign out failed: \(error)")
            errorMessage = "Failed to sign out. Please try again."
        }

        isLoading = false
    }

    func resendCode() async {
        isLoading = true
        errorMessage = nil

        do {
            print("📧 EmailVerificationViewModel: Resending code to \(email)")
            try await authService.resendOTP(email: email)
            print("✅ EmailVerificationViewModel: Code resent successfully")
        } catch {
            print("❌ EmailVerificationViewModel: Resend failed: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct EmailVerificationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: EmailVerificationViewModel
    let userName: String

    init(email: String, userName: String) {
        _viewModel = StateObject(wrappedValue: EmailVerificationViewModel(email: email))
        self.userName = userName
    }

    var body: some View {
        ZStack {
            Color.alphaBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.accentColor)

                    Text("Check Your Email")
                        .font(.alphaDisplayLarge)
                        .foregroundColor(.alphaPrimaryText)

                    Text("We sent an 8-digit code to")
                        .font(.alphaBody)
                        .foregroundColor(.alphaSecondaryText)

                    Text(viewModel.email)
                        .font(.alphaBodySmall)
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                }
                .padding(.top, 60)

                // Verification Form or Success Message
                VStack(spacing: 20) {
                    if viewModel.showSuccessConfirmation {
                        // Success Confirmation
                        VStack(spacing: 20) {
                            // Success Icon
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.green)

                            // Success Message
                            VStack(spacing: 8) {
                                Text("Email Verified!")
                                    .font(.alphaTitle)
                                    .foregroundColor(.alphaPrimaryText)

                                Text("Your email has been successfully verified. Please log in with your password to continue.")
                                    .font(.alphaBody)
                                    .foregroundColor(.alphaSecondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)

                            // Continue Button
                            AlphaButton(
                                "Continue to Log In",
                                style: .primary,
                                size: .large,
                                isLoading: viewModel.isLoading,
                                isDisabled: !viewModel.canProceed
                            ) {
                                Task {
                                    await viewModel.proceedToLogin()
                                }
                            }
                            .padding(.top, 16)
                        }
                        .padding()
                    } else {
                        // OTP Entry Form
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Verification Code")
                                    .font(.alphaLabel)
                                    .foregroundColor(.alphaSecondaryText)

                                TextField("00000000", text: $viewModel.verificationCode)
                                    .textFieldStyle(.plain)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .padding()
                                    .background(Color.alphaCardBackground)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.alphaDivider, lineWidth: 1)
                                    )
                                    .disabled(viewModel.isLoading)
                            }

                            // Error Message
                            if let errorMessage = viewModel.errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.alphaError)
                                    Text(errorMessage)
                                        .font(.alphaBodySmall)
                                        .foregroundColor(.alphaError)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.alphaError.opacity(0.1))
                                .cornerRadius(8)
                            }

                            // Verify Button
                            AlphaButton(
                                "Verify Email",
                                style: .primary,
                                size: .large,
                                isLoading: viewModel.isLoading,
                                isDisabled: viewModel.verificationCode.count != 8
                            ) {
                                Task {
                                    await viewModel.verifyCode()
                                }
                            }
                            .padding(.top, 16)

                            // Resend Code
                            Button(action: {
                                Task {
                                    await viewModel.resendCode()
                                }
                            }) {
                                Text("Didn't receive a code? Resend")
                                    .font(.alphaBodySmall)
                                    .foregroundColor(.alphaPrimary)
                            }
                            .padding(.top, 8)
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .fullScreenCover(isPresented: $viewModel.navigateToLogin) {
            LoginView()
                .environmentObject(appState)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Preview

#Preview("Email Verification") {
    EmailVerificationView(email: "demo@example.com", userName: "John Doe")
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = false
            return state
        }())
}
