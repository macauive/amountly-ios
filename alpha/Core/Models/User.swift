//
//  User.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let organizationId: String?  // Optional - null for personal/freelancer accounts
    let email: String
    let name: String
    let role: Role
    let accountType: AccountType  // New field to track account type
    let hourlyRate: Double?
    let isActive: Bool
    let avatarUrl: String?
    let phone: String?
    let timezone: String?
    let preferences: [String: AnyCodable]?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case email
        case name
        case role
        case accountType = "account_type"
        case hourlyRate = "hourly_rate"
        case isActive = "is_active"
        case avatarUrl = "avatar_url"
        case phone
        case timezone
        case preferences
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Computed properties
    var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var isAdmin: Bool {
        role == .owner || role == .admin
    }
}

// MARK: - Capability Resolution

extension User {
    /// Computed capabilities based on account type and role
    /// For non-business accounts: uses account type capabilities
    /// For business accounts: uses role-based capabilities
    var capabilities: Set<Capability> {
        var caps = accountType.capabilities

        // For business accounts, role determines actual capabilities
        // Members/contractors have restricted access even in business accounts
        if accountType == .business {
            switch role {
            case .owner, .admin:
                // Owners and admins get role-based capabilities
                caps = role.additionalCapabilities
            case .member, .contractor:
                // Members and contractors get limited capabilities
                caps = role.additionalCapabilities
            }
        }

        return caps
    }

    /// Check if user has a specific capability
    func hasCapability(_ capability: Capability) -> Bool {
        capabilities.contains(capability)
    }

    var canExportAccountantPacket: Bool {
        isActive && accountType == .freelancer && organizationId == nil && hasCapability(.exportTaxDocuments)
    }

    // MARK: - Convenience Capability Checks

    /// Can manage team members (invite, edit, remove)
    var canManageTeam: Bool {
        hasCapability(.manageUsers) || hasCapability(.inviteTeamMembers)
    }

    /// Can create and manage invoices
    var canManageInvoices: Bool {
        hasCapability(.createInvoices) && hasCapability(.sendInvoices)
    }

    /// Can access billing features (invoices, AR, or personal bills)
    var canAccessBilling: Bool {
        hasCapability(.viewInvoices) || hasCapability(.viewAccountsReceivable) || hasCapability(.viewBills)
    }

    /// Can access personal bills & payments
    var canAccessBills: Bool {
        hasCapability(.viewBills) || hasCapability(.manageBillPayments)
    }

    /// Can approve time entries or expenses
    var canApprove: Bool {
        hasCapability(.approveTimeEntries) || hasCapability(.approveExpenses)
    }

    /// Can manage organization settings
    var canManageOrganization: Bool {
        hasCapability(.manageOrganization)
    }

    /// Can access payroll features
    var canAccessPayroll: Bool {
        hasCapability(.viewPayroll) || hasCapability(.processPayroll)
    }

    /// Can access inventory features
    var canAccessInventory: Bool {
        hasCapability(.viewInventory)
    }

    /// Can access accounting features
    var canAccessAccounting: Bool {
        hasCapability(.viewAccountsPayable) ||
        hasCapability(.reconcileBankAccounts) ||
        hasCapability(.recordJournalEntries)
    }
}

// MARK: - Preview Helpers
extension User {
    static let preview = User(
        id: "user_1",
        organizationId: "org_1",
        email: "john@example.com",
        name: "John Doe",
        role: .member,
        accountType: .business,
        hourlyRate: 150.0,
        isActive: true,
        avatarUrl: nil,
        phone: "+1 555-0123",
        timezone: "America/Los_Angeles",
        preferences: nil,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let personalPreview = User(
        id: "user_2",
        organizationId: nil,
        email: "jane@example.com",
        name: "Jane Smith",
        role: .member,
        accountType: .personal,
        hourlyRate: nil,
        isActive: true,
        avatarUrl: nil,
        phone: nil,
        timezone: "America/New_York",
        preferences: nil,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let freelancerPreview = User(
        id: "user_3",
        organizationId: nil,
        email: "bob@example.com",
        name: "Bob Johnson",
        role: .contractor,
        accountType: .freelancer,
        hourlyRate: 125.0,
        isActive: true,
        avatarUrl: nil,
        phone: nil,
        timezone: "America/Chicago",
        preferences: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

extension User {
    var reportingCurrency: String { preferences?["default_currency"]?.value as? String ?? "USD" }
    var incomeBasis: String { preferences?["accounting_basis"]?.value as? String ?? "cash" }
    var fiscalStartMonth: Int { let value = preferences?["fiscal_year_start"]?.value as? Int ?? 1; return (1...12).contains(value) ? value : 1 }
}
