//
//  alphaApp.swift
//  alpha
//
//  Created by Iver Macaulay on 11/25/25.
//

import SwiftUI

@main
struct alphaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if ReleaseReadinessPreview.enabled {
                    SettingsView().task { appState.login(user: ReleaseReadinessPreview.user, organization: nil) }
                } else {
                    AppCoordinator().task { await appState.checkAuthStatus() }
                }
#else
                AppCoordinator().task { await appState.checkAuthStatus() }
#endif
            }
                .environmentObject(appState)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
                .overlay {
                    if appState.privacyShield {
                        ZStack {
                            Color.alphaBackground.ignoresSafeArea()
                            VStack(spacing: 16) {
                                if let message = appState.sessionCheckError {
                                    Text(message)
                                    Button("Retry session check") { Task { await appState.resumePrivateUI() } }
                                    Button("Sign out") { Task { try? await AuthService.shared.signOut(); appState.logout() } }
                                } else { ProgressView("Checking your session…") }
                            }.padding()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
#if DEBUG
                    if ProcessInfo.processInfo.environment["AMOUNTLY_XCTEST"] == "1" || ReleaseReadinessPreview.enabled { return }
#endif
                    if phase == .background { appState.suspendPrivateUI() }
                    else if phase == .active { Task { await appState.resumePrivateUI() } }
                }
        }
    }
}
