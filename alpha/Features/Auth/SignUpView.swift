//
//  SignUpView.swift
//  alpha
//
//  Created by Claude Code on 12/18/24.
//

import SwiftUI
import Combine

@MainActor
class SignUpViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var signUpSuccess = false

    private let authService = AuthService.shared

    func signUp() async {
        // Validate inputs
        guard !name.isEmpty else {
            errorMessage = "Please enter your name"
            return
        }

        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Please enter a password"
            return
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }

        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("🔐 SignUpViewModel: Starting signup for \(email)")
            try await authService.signUp(email: email, password: password, name: name)
            print("✅ SignUpViewModel: Signup successful, proceeding to onboarding")
            signUpSuccess = true
        } catch {
            print("❌ SignUpViewModel: Signup failed with error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct SignUpView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SignUpViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.alphaBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(Color(uiColor: .label))

                        Text("Create Account")
                            .font(.alphaDisplayLarge)
                            .foregroundColor(.alphaPrimaryText)

                        Text("Start tracking your time")
                            .font(.alphaBody)
                            .foregroundColor(.alphaSecondaryText)
                    }
                    .padding(.top, 60)

                    // Sign Up Form
                    VStack(spacing: 20) {
                        // Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.alphaLabel)
                                .foregroundColor(.alphaSecondaryText)

                            AlphaTextField(
                                text: $viewModel.name,
                                placeholder: "John Doe",
                                textContentType: .name
                            )
                            .padding()
                            .background(Color.alphaCardBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.alphaDivider, lineWidth: 1)
                            )
                        }

                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.alphaLabel)
                                .foregroundColor(.alphaSecondaryText)

                            AlphaTextField(
                                text: $viewModel.email,
                                placeholder: "you@example.com",
                                keyboardType: .emailAddress,
                                autocapitalization: .none,
                                textContentType: .emailAddress,
                                disableAutocorrection: true
                            )
                            .padding()
                            .background(Color.alphaCardBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.alphaDivider, lineWidth: 1)
                            )
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.alphaLabel)
                                .foregroundColor(.alphaSecondaryText)

                            AlphaTextField(
                                text: $viewModel.password,
                                placeholder: "Minimum 6 characters",
                                textContentType: .newPassword,
                                isSecure: true
                            )
                            .padding()
                            .background(Color.alphaCardBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.alphaDivider, lineWidth: 1)
                            )
                        }

                        // Confirm Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.alphaLabel)
                                .foregroundColor(.alphaSecondaryText)

                            AlphaTextField(
                                text: $viewModel.confirmPassword,
                                placeholder: "Re-enter your password",
                                textContentType: .newPassword,
                                isSecure: true
                            )
                            .padding()
                            .background(Color.alphaCardBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.alphaDivider, lineWidth: 1)
                            )
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

                        // Sign Up Button
                        AlphaButton(
                            "Continue",
                            style: .primary,
                            size: .large,
                            isLoading: viewModel.isLoading,
                            isDisabled: !isFormValid
                        ) {
                            Task {
                                await viewModel.signUp()
                            }
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.alphaBodySmall)
                            .foregroundColor(.alphaSecondaryText)

                        Button(action: {
                            dismiss()
                        }) {
                            Text("Log In")
                                .font(.alphaBodySmall)
                                .fontWeight(.semibold)
                                .foregroundColor(.alphaInfo)
                        }
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.signUpSuccess) {
            AccountTypeSelectionView(email: viewModel.email, userName: viewModel.name)
                .environmentObject(appState)
        }
    }

    private var isFormValid: Bool {
        !viewModel.name.isEmpty &&
        !viewModel.email.isEmpty &&
        !viewModel.password.isEmpty &&
        viewModel.password.count >= 6 &&
        viewModel.password == viewModel.confirmPassword
    }
}

// MARK: - Preview

#Preview("Sign Up View") {
    SignUpView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = false
            return state
        }())
}
