//
//  AppCoordinator.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import SwiftUI

struct AppCoordinator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoading {
                // Loading screen
                LoadingView()
            } else if appState.needsSoloSetup {
                AccountTypeSelectionView(email: appState.setupEmail, userName: appState.setupName)
            } else if appState.needsOrganizationSetup {
                OnboardingView(userName: appState.setupName)
            } else if appState.isAuthenticated {
                // Main app (will create this in Phase 3)
                MainTabView()
            } else {
                // Login screen (will create this in Phase 3)
                LoginView()
            }
        }
        .overlay(alignment: .top) {
            if let error = appState.error, !appState.isAuthenticated {
                RecoveryBanner(message: error) {
                    appState.clearError()
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.alphaBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Loading...")
                    .font(.alphaBody)
                    .foregroundColor(.alphaSecondaryText)
            }
        }
    }
}

private struct RecoveryBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.alphaBody)
                .foregroundColor(.alphaPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss", action: dismiss)
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.alphaCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

// Note: LoginView and MainTabView are now in their respective feature folders

// MARK: - Preview

#Preview("Loading") {
    AppCoordinator()
        .environmentObject({
            let state = AppState()
            state.isLoading = true
            return state
        }())
}

#Preview("Not Authenticated") {
    AppCoordinator()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = false
            return state
        }())
}

#Preview("Authenticated") {
    AppCoordinator()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = true
            state.currentUser = .preview
            state.organization = .preview
            return state
        }())
}
