//
//  Capability.swift
//  alpha
//
//  Created by Claude Code
//

import Foundation

/// Defines all possible features and actions in the Amountly app
/// Used to control access based on account type and user role
enum Capability: String, CaseIterable {
    // MARK: - Time & Attendance

    /// Log time entries
    case trackTime

    /// See own time logs
    case viewOwnTimeEntries

    /// See team member time logs
    case viewTeamTimeEntries

    /// Approve submitted time
    case approveTimeEntries

    /// Edit own entries
    case editOwnTimeEntries

    /// Edit team entries
    case editTeamTimeEntries

    /// Delete time logs
    case deleteTimeEntries

    // MARK: - Invoicing & Billing

    /// Create new invoices
    case createInvoices

    /// Send invoices to clients
    case sendInvoices

    /// View invoices list
    case viewInvoices

    /// Modify existing invoices
    case editInvoices

    /// Remove invoices
    case deleteInvoices

    /// Brand/customize invoice design
    case customizeInvoiceTemplate

    /// Automated reminders
    case schedulePaymentReminders

    /// Mark invoices as paid
    case recordPayments

    /// Issue refunds
    case processRefunds

    /// Quick billing action
    case quickBill

    // MARK: - Client & Contact Management

    /// Full CRUD on clients
    case manageClients

    /// View client list
    case viewClients

    /// Bulk import
    case importContacts

    /// Export client data
    case exportContacts

    // MARK: - Project & Task Management

    /// Create new projects
    case createProjects

    /// Full project admin
    case manageProjects

    /// View projects
    case viewProjects

    /// Assign work to team
    case assignTasks

    /// See task list
    case viewTasks

    /// Set hourly/fixed rates
    case configureBillingRules

    /// Budget tracking
    case trackProjectBudgets

    /// Project P&L
    case viewProjectReports

    // MARK: - Team & Organization

    /// Send invites
    case inviteTeamMembers

    /// Add/edit/remove users
    case manageUsers

    /// Change user roles
    case assignRoles

    /// Activity feed
    case viewTeamActivity

    /// Security audit trail
    case viewAuditLog

    /// Org settings
    case manageOrganization

    // MARK: - Expenses & Reimbursement

    /// Create expense reports
    case submitExpenses

    /// See own expenses
    case viewOwnExpenses

    /// See team expenses
    case viewTeamExpenses

    /// Approve submissions
    case approveExpenses

    /// Set tax categories
    case categorizeExpenses

    /// Upload receipt images
    case attachReceipts

    /// Mileage logging
    case trackMileage

    /// Process reimbursements
    case reimburseExpenses

    // MARK: - Bills & Payments (Personal)

    /// View personal bills
    case viewBills

    /// Manage personal bill payments
    case manageBillPayments

    /// Recurring bill management
    case trackRecurringBills

    // MARK: - Accounting & Finance

    /// AR dashboard
    case viewAccountsReceivable

    /// AP dashboard
    case viewAccountsPayable

    /// Vendor bills/payments
    case manageBills

    /// Vendor relationships
    case manageVendors

    /// PO system
    case createPurchaseOrders

    /// Bank reconciliation
    case reconcileBankAccounts

    /// Account structure
    case manageChartOfAccounts

    /// Manual accounting entries
    case recordJournalEntries

    /// View P&L, Balance Sheet (business reporting)
    case viewFinancialReports

    // MARK: - Inventory (for product businesses)

    /// Inventory list
    case viewInventory

    /// Add/edit products
    case manageInventory

    /// Low stock alerts
    case trackStockLevels

    /// Physical inventory
    case performStockCounts

    // MARK: - Payroll

    /// Payroll dashboard
    case viewPayroll

    /// Run payroll
    case processPayroll

    /// Employee data
    case manageEmployeeProfiles

    /// Tax reports
    case viewPayrollReports

    // MARK: - Reports & Analytics

    /// Simple summaries
    case viewBasicReports

    /// Detailed analytics
    case viewAdvancedReports

    /// P&L, Balance Sheet, Cash Flow
    case viewFinancialStatements

    /// Report builder
    case customizeReports

    /// CSV/PDF exports
    case exportData

    /// Automated email reports
    case scheduledReports

    // MARK: - Tax & Compliance

    /// Tax overview
    case viewTaxDashboard

    /// Quarterly estimates
    case generateTaxEstimates

    /// 1099s, W2s, etc.
    case exportTaxDocuments

    /// Sales tax calculations
    case trackSalesTax

    /// Payroll tax tracking
    case managePayrollTax

    // MARK: - Integrations

    /// Bank sync
    case connectBankAccounts

    /// QuickBooks, Xero
    case connectAccountingSoftware

    /// Stripe, PayPal
    case connectPaymentProcessors

    /// API settings
    case manageIntegrations

    // MARK: - Settings & Preferences

    /// Notification preferences
    case configureNotifications

    /// Theme/branding
    case customizeAppearance

    /// Full data export
    case exportAllData

    /// Account deletion
    case deleteAccount
}
