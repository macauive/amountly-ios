//
//  SettingsView.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import SwiftUI
import Supabase
import PostgREST

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // User Profile Section
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.alphaPrimary)
                            .frame(width: 60, height: 60)
                            .overlay {
                                Text(appState.currentUser?.initials ?? "")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.currentUser?.name ?? "User")
                                .font(.alphaHeadline)
                                .foregroundColor(.alphaPrimaryText)

                            Text(appState.currentUser?.email ?? "")
                                .font(.alphaBodySmall)
                                .foregroundColor(.alphaSecondaryText)

                            Text(appState.currentUser?.role.displayName ?? "")
                                .font(.alphaLabel)
                                .foregroundColor(.alphaTertiaryText)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Organization Section - Business accounts only
                if let org = appState.organization,
                   appState.hasCapability(.manageOrganization) {
                    Section("Organization") {
                        NavigationLink(destination: OrganizationSettingsSummaryView(organization: org)) {
                            Label("Organization Settings", systemImage: "building.2")
                        }

                        HStack {
                            Text("Company")
                            Spacer()
                            Text(org.name)
                                .foregroundColor(.alphaSecondaryText)
                        }

                        if let email = org.email {
                            HStack {
                                Text("Email")
                                Spacer()
                                Text(email)
                                    .foregroundColor(.alphaSecondaryText)
                            }
                        }
                    }
                }

                // Preferences Section
                Section("Preferences") {
                    NavigationLink(destination: NotificationPreferencesView(appState: appState)) {
                        Label("Notifications", systemImage: "bell")
                    }

                    NavigationLink(destination: DisplaySettingsView()) {
                        Label("Display", systemImage: "paintbrush")
                    }

                    NavigationLink(destination: TaxBillingDefaultsView(user: appState.currentUser)) {
                        Label("Tax & Billing Defaults", systemImage: "calendar.badge.clock")
                    }
                }

                // Business Section - Capability-based items
                if appState.hasCapability(.viewClients) {
                    Section("Business") {
                        NavigationLink(destination: ContactsListView()) {
                            Label("Contacts", systemImage: "person.2")
                        }
                    }
                }

                // Tax & Compliance - Freelancer+ only
                if appState.hasCapability(.viewTaxDashboard) &&
                   appState.currentUser?.accountType == .freelancer {
                    Section("Tax & Compliance") {
                        NavigationLink(destination: TaxComplianceView()) {
                            Label("Tax Dashboard", systemImage: "doc.plaintext.fill")
                        }

                        NavigationLink(destination: Text("Tax Estimates")) {
                            Label("Tax Estimates", systemImage: "calculator")
                        }
                        .requiresCapability(.generateTaxEstimates)

                        NavigationLink(destination: Text("Tax Documents")) {
                            Label("Tax Documents", systemImage: "folder.fill")
                        }
                        .requiresCapability(.exportTaxDocuments)
                    }
                }

                // Integrations Section - Advanced users
                if appState.hasCapability(.manageIntegrations) {
                    Section("Integrations") {
                        NavigationLink(destination: Text("Connected Accounts")) {
                            Label("Connected Accounts", systemImage: "link")
                        }

                        NavigationLink(destination: Text("API Settings")) {
                            Label("API Settings", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }

                // Data Section
                Section("Data") {
                    NavigationLink(destination: DataExportSettingsView(appState: appState)) {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    .requiresCapability(.exportAllData)

                    NavigationLink(destination: Text("Offline Data")) {
                        Label("Offline Data", systemImage: "arrow.down.circle")
                    }
                }

                // Support Section
                Section("Support") {
                    NavigationLink(destination: Text("Help Center")) {
                        Label("Help Center", systemImage: "questionmark.circle")
                    }

                    NavigationLink(destination: Text("Send Feedback")) {
                        Label("Send Feedback", systemImage: "envelope")
                    }

                    NavigationLink(destination: Text("About")) {
                        Label("About", systemImage: "info.circle")
                    }
                }

                // Sign Out Section
                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(.alphaBody)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Are you sure you want to sign out?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await AuthService.shared.logout()
                        appState.logout()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct OrganizationSettingsSummaryView: View {
    let organization: Organization

    var body: some View {
        Form {
            Section("Business Information") {
                SettingsDetailRow(label: "Name", value: organization.name)
                SettingsDetailRow(label: "Email", value: organization.email)
                SettingsDetailRow(label: "Phone", value: organization.phone)
                SettingsDetailRow(label: "Tax ID / EIN", value: organization.taxId)
            }

            Section("Address") {
                SettingsDetailRow(label: "Street", value: organization.address)
                SettingsDetailRow(label: "City", value: organization.city)
                SettingsDetailRow(label: "State", value: organization.state)
                SettingsDetailRow(label: "ZIP / Postal Code", value: organization.zipCode)
                SettingsDetailRow(label: "Country", value: organization.country)
            }
        }
        .navigationTitle("Organization")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TaxBillingDefaultsView: View {
    let user: User?

    private var preferences: [String: AnyCodable] {
        user?.preferences ?? [:]
    }

    var body: some View {
        Form {
            Section {
                SettingsDetailRow(label: "Default Tax Rate", value: formattedPreference("default_tax_rate", suffix: "%", fallback: "0%"))
                SettingsDetailRow(label: "Default Currency", value: stringPreference("default_currency") ?? "USD")
                SettingsDetailRow(label: "Fiscal Year Start", value: fiscalYearStart)
                SettingsDetailRow(label: "Payment Terms", value: paymentTerms)
                SettingsDetailRow(label: "Date Format", value: stringPreference("date_format") ?? "MM/DD/YYYY")
            } header: {
                Text("Tax & Billing Defaults")
            } footer: {
                Text("These defaults mirror the web app settings used when creating invoices, bills, and tax records.")
            }
        }
        .navigationTitle("Tax & Billing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fiscalYearStart: String {
        let monthNumber = intPreference("fiscal_year_start") ?? 1
        guard (1...12).contains(monthNumber) else { return "January" }
        return Calendar.current.monthSymbols[monthNumber - 1]
    }

    private var paymentTerms: String {
        let terms = intPreference("payment_terms") ?? 30
        return terms == 0 ? "Due on Receipt" : "Net \(terms)"
    }

    private func formattedPreference(_ key: String, suffix: String, fallback: String) -> String {
        if let double = doublePreference(key) {
            return String(format: "%.1f%@", double, suffix)
        }

        return fallback
    }

    private func stringPreference(_ key: String) -> String? {
        preferences[key]?.value as? String
    }

    private func intPreference(_ key: String) -> Int? {
        if let int = preferences[key]?.value as? Int {
            return int
        }

        if let double = preferences[key]?.value as? Double {
            return Int(double)
        }

        if let string = preferences[key]?.value as? String {
            return Int(string)
        }

        return nil
    }

    private func doublePreference(_ key: String) -> Double? {
        if let double = preferences[key]?.value as? Double {
            return double
        }

        if let int = preferences[key]?.value as? Int {
            return Double(int)
        }

        if let string = preferences[key]?.value as? String {
            return Double(string)
        }

        return nil
    }
}

private struct NotificationPreferencesView: View {
    let appState: AppState

    @AppStorage("notifications.overdue_invoices") private var overdueInvoices = true
    @AppStorage("notifications.bill_due_reminders") private var billDueReminders = true
    @AppStorage("notifications.payroll_confirmation") private var payrollConfirmation = true
    @AppStorage("notifications.low_stock_alerts") private var lowStockAlerts = false
    @AppStorage("notifications.weekly_summary") private var weeklySummary = false

    var body: some View {
        Form {
            Section {
                if appState.hasCapability(.viewInvoices) {
                    Toggle("Overdue Invoices", isOn: $overdueInvoices)
                }

                if appState.hasCapability(.viewBills) {
                    Toggle("Bill Due Reminders", isOn: $billDueReminders)
                }

                if appState.hasCapability(.viewPayroll) {
                    Toggle("Payroll Confirmation", isOn: $payrollConfirmation)
                }

                if appState.hasCapability(.viewInventory) {
                    Toggle("Low Stock Alerts", isOn: $lowStockAlerts)
                }

                Toggle("Weekly Summary", isOn: $weeklySummary)
            } header: {
                Text("Notification Preferences")
            } footer: {
                Text("Mobile notification toggles are stored on this device until server-backed notification preferences are enabled.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataExportSettingsView: View {
    let appState: AppState

    @State private var exportingKind: DataExportKind?
    @State private var exportFile: ExportFile?
    @State private var errorMessage: String?

    private var exportItems: [DataExportItem] {
        [
            DataExportItem(kind: .invoices, label: "Invoices", filename: "amountly-invoices.csv", capability: .viewInvoices),
            DataExportItem(kind: .invoiceLineItems, label: "Invoice Line Items", filename: "amountly-invoice-lines.csv", capability: .viewInvoices),
            DataExportItem(kind: .expenses, label: "Expenses", filename: "amountly-expenses.csv", capability: .viewOwnExpenses),
            DataExportItem(kind: .bills, label: "Bills", filename: "amountly-bills.csv", capability: .viewBills),
            DataExportItem(kind: .clients, label: "Clients", filename: "amountly-clients.csv", capability: .viewClients),
            DataExportItem(kind: .projects, label: "Projects", filename: "amountly-projects.csv", capability: .viewProjects),
            DataExportItem(kind: .timeEntries, label: "Time Entries", filename: "amountly-time-entries.csv", capability: .viewOwnTimeEntries),
            DataExportItem(kind: .taxFilings, label: "Tax Filings", filename: "amountly-tax-filings.csv", capability: .viewTaxDashboard)
        ].filter { appState.hasCapability($0.capability) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(exportItems) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .foregroundColor(.alphaPrimaryText)

                            Text(item.filename)
                                .font(.alphaCaption)
                                .foregroundColor(.alphaSecondaryText)
                        }

                        Spacer()

                        Button {
                            export(item)
                        } label: {
                            if exportingKind == item.kind {
                                ProgressView()
                            } else {
                                Label("CSV", systemImage: "square.and.arrow.up")
                                    .font(.alphaCaption)
                                    .foregroundColor(.alphaPrimary)
                            }
                        }
                        .disabled(exportingKind != nil)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("CSV Exports")
            } footer: {
                Text("Download your data as CSV files. Exports include records visible to your account.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    private func export(_ item: DataExportItem) {
        exportingKind = item.kind
        errorMessage = nil

        Task {
            do {
                let rows = try await rows(for: item.kind)
                let csv = CSVExportBuilder.makeCSV(headers: item.kind.headers, rows: rows)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.filename)
                try csv.write(to: url, atomically: true, encoding: .utf8)

                await MainActor.run {
                    exportFile = ExportFile(url: url)
                    exportingKind = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to export \(item.label.lowercased()): \(error.localizedDescription)"
                    exportingKind = nil
                }
            }
        }
    }

    private func rows(for kind: DataExportKind) async throws -> [[String: String]] {
        switch kind {
        case .invoices:
            return try await CSVExportDataSource.fetchRawRows(
                table: "invoices",
                headers: kind.headers,
                orderColumn: "created_at",
                ascending: false
            )

        case .invoiceLineItems:
            return try await CSVExportDataSource.fetchRawRows(
                table: "invoice_line_items",
                headers: kind.headers,
                orderColumn: "order",
                ascending: true
            )

        case .expenses:
            return try await CSVExportDataSource.fetchRawRows(table: "expenses", headers: kind.headers)

        case .bills:
            return try await CSVExportDataSource.fetchRawRows(table: "bills", headers: kind.headers)

        case .clients:
            return try await CSVExportDataSource.fetchRawRows(table: "clients", headers: kind.headers)

        case .projects:
            return try await CSVExportDataSource.fetchRawRows(table: "projects", headers: kind.headers)

        case .timeEntries:
            return try await CSVExportDataSource.fetchRawRows(table: "time_entries", headers: kind.headers)

        case .taxFilings:
            return try await CSVExportDataSource.fetchRawRows(table: "tax_filings", headers: kind.headers)
        }
    }
}

private struct DataExportItem: Identifiable {
    var id: DataExportKind { kind }
    let kind: DataExportKind
    let label: String
    let filename: String
    let capability: Capability
}

private enum DataExportKind {
    case invoices
    case invoiceLineItems
    case expenses
    case bills
    case clients
    case projects
    case timeEntries
    case taxFilings

    var headers: [String] {
        switch self {
        case .invoices:
            return ["id", "organization_id", "user_id", "client_id", "project_id", "invoice_number", "issue_date", "due_date", "subtotal", "tax_rate", "tax_amount", "total", "currency", "status", "notes"]
        case .invoiceLineItems:
            return ["id", "invoice_id", "description", "quantity", "rate", "amount", "order"]
        case .expenses:
            return ["id", "user_id", "project_id", "task_id", "amount", "currency", "category", "description", "merchant", "expense_date", "receipt_url", "status", "notes", "invoice_id", "created_at", "updated_at"]
        case .bills:
            return ["id", "user_id", "name", "payee", "amount", "currency", "category", "due_date", "status", "recurrence", "notes", "paid_at", "auto_pay", "created_at", "updated_at"]
        case .clients:
            return ["id", "organization_id", "user_id", "name", "email", "phone", "address", "city", "state", "zip_code", "country", "contact_name", "notes", "is_active", "created_at", "updated_at"]
        case .projects:
            return ["id", "organization_id", "user_id", "client_id", "name", "description", "billing_model", "rate", "budget", "start_date", "end_date", "is_active", "color", "created_at", "updated_at"]
        case .timeEntries:
            return ["id", "user_id", "project_id", "task_id", "start_at", "end_at", "duration_minutes", "notes", "status", "source", "billable_rate", "invoice_id", "created_at", "updated_at"]
        case .taxFilings:
            return ["id", "organization_id", "user_id", "name", "form_type", "tax_period_start", "tax_period_end", "due_date", "filed_date", "status", "amount_due", "amount_paid", "notes", "created_at", "updated_at"]
        }
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private enum CSVExportBuilder {
    static func makeCSV(headers: [String], rows: [[String: String]]) -> String {
        let lines = rows.map { row in
            headers.map { escape(row[$0] ?? "") }.joined(separator: ",")
        }

        return ([headers.joined(separator: ",")] + lines).joined(separator: "\n")
    }

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    static func amount(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        return value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum CSVExportDataSource {
    static func fetchRawRows(
        table: String,
        headers: [String],
        orderColumn: String = "created_at",
        ascending: Bool = false
    ) async throws -> [[String: String]] {
        let response = try await SupabaseClientManager.shared.client
            .from(table)
            .select("*")
            .order(orderColumn, ascending: ascending)
            .limit(500)
            .execute()

        let object = try JSONSerialization.jsonObject(with: response.data)
        let records = object as? [[String: Any]] ?? []
        return records.map { record in
            Dictionary(uniqueKeysWithValues: headers.map { header in
                (header, stringValue(record[header]))
            })
        }
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull:
            return ""
        case let number as NSNumber:
            return "\(number)"
        case let string as String:
            return string
        default:
            return "\(value ?? "")"
        }
    }
}

private struct SettingsDetailRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(displayValue)
                .foregroundColor(value == nil || value?.isEmpty == true ? .alphaTertiaryText : .alphaSecondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var displayValue: String {
        guard let value, !value.isEmpty else {
            return "Not set"
        }

        return value
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = true
            state.currentUser = .preview
            state.organization = .preview
            return state
        }())
}
