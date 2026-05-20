//
//  AppState.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import Foundation
import SwiftUI
import Combine
import Auth

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var organization: Organization?
    @Published var isLoading = false
    @Published var error: String?

    private let authService = AuthService.shared
    private var authStateTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var restoreGeneration = UUID()

    // MARK: - Initialization

    init() {
        // Observe auth state changes
        authStateTask = authService.observeAuthStateChanges { [weak self] event, session in
            Task { @MainActor in
                switch event {
                case .signedIn, .initialSession:
                    await self?.restoreAuthenticatedState(trigger: "authState:\(event)")
                case .signedOut:
                    self?.cancelRestoreTask()
                    self?.onSignedOut()
                default:
                    break
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
        restoreTask?.cancel()
    }

    func checkAuthStatus() async {
        await restoreAuthenticatedState(trigger: "launch")
    }

    // MARK: - Authentication

    func login(user: User, organization: Organization?) {
        cancelRestoreTask()
        self.currentUser = user
        self.organization = organization  // Can be nil for personal/freelancer accounts
        self.isAuthenticated = true
        self.isLoading = false
        self.error = nil
    }

    var requiresOrganization: Bool {
        currentUser?.accountType.requiresOrganization ?? false
    }

    func logout() {
        cancelRestoreTask()
        self.currentUser = nil
        self.organization = nil
        self.isAuthenticated = false
        self.isLoading = false
        self.error = nil
    }

    // MARK: - Error Handling

    func setError(_ message: String) {
        self.error = message
    }

    func clearError() {
        self.error = nil
    }

    // MARK: - Private Helpers

    private func restoreAuthenticatedState(trigger: String) async {
        restoreTask?.cancel()
        let generation = UUID()
        restoreGeneration = generation

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRestore(trigger: trigger)
        }

        restoreTask = task
        await task.value

        if restoreGeneration == generation {
            restoreTask = nil
        }
    }

    private func performRestore(trigger: String) async {
        isLoading = true
        error = nil

        do {
            guard let restoredState = try await authService.restoreAuthenticatedState() else {
                onSignedOut()
                isLoading = false
                return
            }

            currentUser = restoredState.user
            organization = restoredState.organization
            isAuthenticated = true
            isLoading = false

            let restoredOrganizationId = restoredState.organization?.id ?? "none"
            print("✅ AppState.performRestore(\(trigger)): restored user=\(restoredState.user.id) org=\(restoredOrganizationId)")
        } catch is CancellationError {
            print("ℹ️ AppState.performRestore(\(trigger)): cancelled")
        } catch {
            print("❌ AppState.performRestore(\(trigger)): failed: \(error)")
            enterRecoveryState(for: error)
        }
    }

    private func enterRecoveryState(for error: Error) {
        currentUser = nil
        organization = nil
        isAuthenticated = false
        isLoading = false
        self.error = "We couldn’t restore your session. Please log in again."
    }

    private func cancelRestoreTask() {
        restoreGeneration = UUID()
        restoreTask?.cancel()
        restoreTask = nil
    }

    private func onSignedOut() {
        self.currentUser = nil
        self.organization = nil
        self.isAuthenticated = false
        self.isLoading = false
    }
}

// MARK: - Capability Helpers

extension AppState {
    /// Check if current user has a specific capability
    func hasCapability(_ capability: Capability) -> Bool {
        currentUser?.hasCapability(capability) ?? false
    }

    /// Determines which main tabs should be visible based on user capabilities and account type
    var visibleTabs: [MainTab] {
        guard let user = currentUser else { return [.dashboard] }

        var tabs: [MainTab] = [.dashboard]

        if user.hasCapability(.trackTime) ||
            user.hasCapability(.viewOwnTimeEntries) ||
            user.hasCapability(.viewTeamTimeEntries) {
            tabs.append(.timeEntries)
        }

        if user.canAccessBilling ||
            user.hasCapability(.viewBills) ||
            user.hasCapability(.viewAccountsPayable) ||
            user.hasCapability(.viewOwnExpenses) ||
            user.hasCapability(.viewTeamExpenses) {
            tabs.append(.money)
        }

        if user.hasCapability(.viewProjects) {
            tabs.append(.projects)
        }

        tabs.append(.more)
        return tabs
    }

    /// Feature modules available to the user (for future expansion)
    var availableModules: Set<AppModule> {
        guard let user = currentUser else { return [] }

        var modules: Set<AppModule> = [.dashboard, .settings]

        if user.hasCapability(.trackTime) {
            modules.insert(.timeTracking)
        }

        if user.canManageInvoices {
            modules.insert(.invoicing)
        }

        if user.hasCapability(.viewAccountsReceivable) || user.hasCapability(.viewAccountsPayable) {
            modules.insert(.accounting)
        }

        if user.canAccessPayroll {
            modules.insert(.payroll)
        }

        if user.canAccessInventory {
            modules.insert(.inventory)
        }

        if user.hasCapability(.viewTaxDashboard) {
            modules.insert(.taxCompliance)
        }

        if user.canManageTeam {
            modules.insert(.teamManagement)
        }

        return modules
    }
}

// MARK: - App Module Definition

/// Future module structure for app expansion
enum AppModule: String, CaseIterable, Hashable {
    case dashboard
    case timeTracking
    case invoicing
    case accounting
    case payroll
    case inventory
    case taxCompliance
    case teamManagement
    case settings

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .timeTracking: return "clock.fill"
        case .invoicing: return "doc.text.fill"
        case .accounting: return "chart.bar.fill"
        case .payroll: return "dollarsign.circle.fill"
        case .inventory: return "shippingbox.fill"
        case .taxCompliance: return "doc.plaintext.fill"
        case .teamManagement: return "person.3.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .timeTracking: return "Time Tracking"
        case .invoicing: return "Invoicing"
        case .accounting: return "Accounting"
        case .payroll: return "Payroll"
        case .inventory: return "Inventory"
        case .taxCompliance: return "Tax & Compliance"
        case .teamManagement: return "Team"
        case .settings: return "Settings"
        }
    }
}

// MARK: - Main Tab Definition

enum ProductScope {
    static let showAdvancedModules = false
}

/// Main tabs for the app navigation
enum MainTab: Int, Identifiable, CaseIterable {
    case dashboard = 0
    case timeEntries = 1
    case money = 2
    case projects = 3
    case more = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .timeEntries: return "Time"
        case .money: return "Money"
        case .projects: return "Projects"
        case .more: return "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .timeEntries: return "clock.fill"
        case .money: return "creditcard.fill"
        case .projects: return "folder.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }

    /// Capability required to see this tab (nil = always visible)
    var requiredCapability: Capability? {
        switch self {
        case .dashboard:
            return nil // Always visible
        case .timeEntries:
            return .trackTime
        case .money:
            return nil
        case .projects:
            return .viewProjects
        case .more:
            return nil
        }
    }
}
