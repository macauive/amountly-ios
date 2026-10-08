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

    func verifyCode(appState: AppState) async {
        guard !isLoading, verificationCode.count == 6, verificationCode.utf8.allSatisfy({ (48...57).contains($0) }) else { errorMessage = "Enter the 6-digit verification code."; return }
        isLoading = true; errorMessage = nil; appState.beginSignIn()
        defer { isLoading = false; appState.endSignIn() }
        do {
            _ = try await authService.verifyOTP(email: email, token: verificationCode)
            verificationCode = ""; showSuccessConfirmation = true; canProceed = true
        } catch { errorMessage = "Could not verify your email. Check the code or request a new one." }
    }
    func proceedToLogin() async { navigateToLogin = true }
    func resendCode() async {
        guard !isLoading else { return }; isLoading = true; errorMessage = nil; defer { isLoading = false }
        do { try await authService.resendOTP(email: email) }
        catch { errorMessage = "Could not request a code. Try again shortly." }
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

                    Text("We sent a 6-digit code to")
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

                                Text("Your email is verified. Continue to set up your solo business.")
                                    .font(.alphaBody)
                                    .foregroundColor(.alphaSecondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)

                            // Continue Button
                            AlphaButton(
                                "Continue to setup",
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
                                isDisabled: viewModel.verificationCode.count != 6
                            ) {
                                Task {
                                    await viewModel.verifyCode(appState: appState)
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
            AccountTypeSelectionView(email: viewModel.email, userName: userName)
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
