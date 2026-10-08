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
    @Published var needsSoloSetup = false
    @Published var needsOrganizationSetup = false
    @Published var setupName = ""
    @Published var setupEmail = ""
    @Published var currentUser: User?
    @Published var organization: Organization?
    @Published var isLoading = false
    @Published var error: String?

    private let authService = AuthService.shared
    private var authStateTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var restoreGeneration = UUID()
    private var signingIn = false

    func beginSignIn() { signingIn = true; cancelRestoreTask() }
    func endSignIn() { signingIn = false }

    // MARK: - Initialization

    init() {
#if DEBUG
        // Hosted XCTest owns its sessions; background UI restoration would race it.
        if ProcessInfo.processInfo.environment["AMOUNTLY_XCTEST"] == "1" { return }
#endif
        PrivateDocument.removeAll()
        // Observe auth state changes
        authStateTask = authService.observeAuthStateChanges { [weak self] event, session in
            Task { @MainActor in
                switch event {
                case .signedIn, .initialSession:
                    guard self?.signingIn == false else { return }
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
#if DEBUG
        if ProcessInfo.processInfo.environment["AMOUNTLY_XCTEST"] == "1" { return }
#endif
        await restoreAuthenticatedState(trigger: "launch")
    }

    // MARK: - Authentication

    func login(user: User, organization: Organization?) {
        needsSoloSetup = false; needsOrganizationSetup = false; setupName = ""; setupEmail = ""
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
        needsSoloSetup = false; needsOrganizationSetup = false; setupName = ""; setupEmail = ""
        PrivateDocument.removeAll()
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
            await self.performRestore(trigger: trigger, generation: generation)
        }

        restoreTask = task
        await task.value

        if restoreGeneration == generation {
            restoreTask = nil
        }
    }

    private func performRestore(trigger: String, generation: UUID) async {
        isLoading = true
        error = nil

        do {
            guard let restoredState = try await authService.restoreAuthenticatedState() else {
                guard restoreGeneration == generation else { return }
                onSignedOut()
                isLoading = false
                return
            }

            guard restoreGeneration == generation else { return }
            needsSoloSetup = false; needsOrganizationSetup = false; setupName = ""; setupEmail = ""
            currentUser = restoredState.user
            organization = restoredState.organization
            isAuthenticated = true
            isLoading = false
        } catch AuthError.profileSetupRequired {
            guard restoreGeneration == generation else { return }
            enterSetup(organization: false)
        } catch AuthError.organizationSetupRequired {
            guard restoreGeneration == generation else { return }
            enterSetup(organization: true)
        } catch is CancellationError {
            print("ℹ️ AppState.performRestore(\(trigger)): cancelled")
        } catch let error as URLError where error.code == .cancelled {
            print("ℹ️ AppState.performRestore(\(trigger)): cancelled URL request")
        } catch {
            guard restoreGeneration == generation else { return }
            print("Authentication operation failed; retry or sign in again.")
            enterRecoveryState(for: error)
        }
    }

    private func enterSetup(organization: Bool) {
        currentUser = nil; self.organization = nil; isAuthenticated = false; isLoading = false; error = nil
        setupName = authService.currentSession?.user.userMetadata["name"]?.description ?? "New user"
        setupEmail = authService.currentSession?.user.email ?? ""
        needsSoloSetup = !organization; needsOrganizationSetup = organization
    }

    private func enterRecoveryState(for error: Error) {
        needsSoloSetup = false; needsOrganizationSetup = false
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
        needsSoloSetup = false; needsOrganizationSetup = false; setupName = ""; setupEmail = ""
        PrivateDocument.removeAll()
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
