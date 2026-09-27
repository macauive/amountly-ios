//
//  LoginView.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import SwiftUI
import Combine
import Auth

@MainActor
class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var navigateToOnboarding = false
    @Published var userName = ""

    private let authService = AuthService.shared

    func login(appState: AppState) async {
        // Validate inputs
        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Please enter your password"
            return
        }

        isLoading = true
        appState.beginSignIn()
        defer { appState.endSignIn(); isLoading = false }
        errorMessage = nil

        do {
            print("🔐 LoginViewModel: Starting login")

            // Step 1: Sign in with password to get authenticated JWT
            try await authService.signInWithPassword(email: email, password: password)
            print("✅ LoginViewModel: Password authentication successful")

            // Step 2: Check if user exists in database
            let userInfo = try await authService.getUserInfo()

            if let user = userInfo {
                // User exists - complete login based on account type
                print("✅ LoginViewModel: User exists with account type: \(user.accountType.displayName)")

                if let orgId = user.organizationId {
                    // Business account - fetch organization and login
                    print("🏢 LoginViewModel: Fetching organization: \(orgId)")
                    let org = try await authService.getOrganization(orgId)
                    appState.login(user: user, organization: org)
                    print("✅ LoginViewModel: Business login complete")
                } else {
                    // Personal/Freelancer account - login without organization
                    print("👤 LoginViewModel: Personal/Freelancer login - no organization needed")
                    appState.login(user: user, organization: nil)
                    print("✅ LoginViewModel: Personal login complete")
                }
            } else {
                // New user - get pending account type and create user record
                print("🆕 LoginViewModel: New user - checking pending account type")
                let accountTypeString = UserDefaults.standard.string(forKey: "pendingAccountType") ?? "business"
                guard let accountType = AccountType(rawValue: accountTypeString) else {
                    errorMessage = "Invalid account type"
                    return
                }

                if accountType.requiresOrganization {
                    // Business account - navigate to onboarding to create organization
                    print("🏢 LoginViewModel: Business account - navigating to organization setup")
                    if let session = authService.currentSession {
                        userName = session.user.userMetadata["name"]?.description ?? email.components(separatedBy: "@").first ?? "User"
                    }
                    navigateToOnboarding = true
                } else {
                    // Personal/Freelancer - create user without organization
                    print("👤 LoginViewModel: Creating \(accountType.displayName) user")
                    let name = authService.currentSession?.user.userMetadata["name"]?.description ?? email.components(separatedBy: "@").first ?? "User"
                    let newUser = try await authService.createPersonalUser(name: name, accountType: accountType)

                    // Clear the pending account type
                    UserDefaults.standard.removeObject(forKey: "pendingAccountType")

                    appState.login(user: newUser, organization: nil)
                    print("✅ LoginViewModel: Personal user created and logged in")
                }
            }
        } catch {
            print("Authentication operation failed; retry or sign in again.")
            errorMessage = (error as? RecordError)?.localizedDescription ?? "Could not sign in. Check your credentials and connection, then try again."
        }

        isLoading = false
        print("🔐 LoginViewModel: Login complete, isLoading: \(isLoading)")
    }
}

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = LoginViewModel()
    @State private var showSignUp = false

    var body: some View {
        ZStack {
            Color.alphaBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 12) {
                        Image("AmountlyLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .accessibilityHidden(true)

                        Text("Amountly")
                            .font(.alphaDisplayLarge)
                            .foregroundColor(.alphaPrimaryText)

                        Text("Simple accounting workspace")
                            .font(.alphaBody)
                            .foregroundColor(.alphaSecondaryText)
                    }
                    .padding(.top, 60)

                    // Login Form
                    VStack(spacing: 20) {
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
                                placeholder: "Enter your password",
                                textContentType: .password,
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

                        AlphaButton(
                            "Log In",
                            style: .primary,
                            size: .large,
                            isLoading: viewModel.isLoading,
                            isDisabled: viewModel.email.isEmpty || viewModel.password.isEmpty
                        ) {
                            Task {
                                await viewModel.login(appState: appState)
                            }
                        }
                        .padding(.top, 16)

                        // Forgot Password
                        Button(action: {
                            // TODO: Implement forgot password
                        }) {
                            Text("Forgot Password?")
                                .font(.alphaBodySmall)
                                .foregroundColor(.alphaInfo)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    // Sign Up Link
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(.alphaBodySmall)
                            .foregroundColor(.alphaSecondaryText)

                        Button(action: {
                            showSignUp = true
                        }) {
                            Text("Sign Up")
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
        .sheet(isPresented: $showSignUp) {
            SignUpView()
                .environmentObject(appState)
                .withAppTheme()
        }
        .fullScreenCover(isPresented: $viewModel.navigateToOnboarding) {
            OnboardingView(userName: viewModel.userName)
                .environmentObject(appState)
                .withAppTheme()
        }
    }
}

// MARK: - Preview

#Preview("Login View") {
    LoginView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = false
            return state
        }())
}

#Preview("Login View - With Error") {
    LoginView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = false
            return state
        }())
        .onAppear {
            // Simulate error state
        }
}
