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
                    NavigationLink("Workspace Preferences", destination: WorkspacePreferencesView())
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
    @State private var overdueInvoices = true
    @State private var billDueReminders = true
    @State private var payrollConfirmation = true
    @State private var lowStockAlerts = false
    @State private var weeklySummary = false
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Shared notification preferences") {
                if appState.hasCapability(.viewInvoices) { Toggle("Overdue Invoices", isOn: $overdueInvoices) }
                if appState.hasCapability(.viewBills) || appState.hasCapability(.viewAccountsPayable) { Toggle("Bill Due Reminders", isOn: $billDueReminders) }
                Toggle("Weekly Summary", isOn: $weeklySummary)
                Text("Preferences are shared with the web app. Saving them does not enable email delivery or device push notifications.").font(.caption)
            }.disabled(saving)
            if let message { Text(message) }
            Button("Save Preferences") { Task { await save() } }.disabled(saving)
        }.navigationTitle("Notifications")
            .onAppear {
                let values = appState.currentUser?.preferences?["notifications"]?.value as? [String: Any] ?? [:]
                overdueInvoices = values["overdue_invoices"] as? Bool ?? true
                billDueReminders = values["bill_due_reminders"] as? Bool ?? true
                payrollConfirmation = values["payroll_confirmation"] as? Bool ?? true
                lowStockAlerts = values["low_stock_alerts"] as? Bool ?? false
                weeklySummary = values["weekly_summary"] as? Bool ?? false
            }
    }
    private func save() async {
        guard let user = appState.currentUser else { return }
        saving = true; defer { saving = false }
        do {
            let client = SupabaseClientManager.shared.client
            let values: [String: AnyJSON] = ["overdue_invoices": .bool(overdueInvoices), "bill_due_reminders": .bool(billDueReminders), "payroll_confirmation": .bool(payrollConfirmation), "low_stock_alerts": .bool(lowStockAlerts), "weekly_summary": .bool(weeklySummary)]
            try await client.rpc("set_own_preferences", params: ["p_patch": AnyJSON.object(["notifications": .object(values)])]).execute()
            let response = try await client.from("users").select().eq("id", value: user.id).single().execute()
            appState.currentUser = try RecordCoding.decoder().decode(User.self, from: response.data)
            message = "Preferences saved."
        } catch { message = RecordError.safe(error).localizedDescription }
    }
}

private struct DataExportSettingsView: View {
    let appState: AppState

    @State private var exportingKind: DataExportKind?
    @State private var exportFile: ExportFile?
    @State private var lastExportURL: URL?
    @State private var errorMessage: String?

    private var exportItems: [DataExportItem] {
        [
            DataExportItem(kind: .invoices, label: "Invoices", filename: "amountly-invoices.csv", capability: .viewInvoices),
            DataExportItem(kind: .invoicePayments, label: "Invoice Payments", filename: "amountly-payments.csv", capability: .viewInvoices),
            DataExportItem(kind: .paymentReversals, label: "Payment Corrections", filename: "amountly-payment-corrections.csv", capability: .viewInvoices),
            DataExportItem(kind: .vendors, label: "Vendors", filename: "amountly-vendors.csv", capability: .viewAccountsPayable),
            DataExportItem(kind: .vendorBills, label: "Vendor Bills", filename: "amountly-vendor-bills.csv", capability: .viewAccountsPayable),
            DataExportItem(kind: .purchaseOrders, label: "Purchase Orders", filename: "amountly-purchase-orders.csv", capability: .viewAccountsPayable),
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
        .sheet(item: $exportFile, onDismiss: { if let lastExportURL { try? FileManager.default.removeItem(at: lastExportURL) }; lastExportURL = nil }) { file in
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
                guard csv.utf8.count <= 2_000_000 else { throw RecordError(message: "This export exceeds the 2 MB limit.") }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(item.filename)")
                try csv.write(to: url, atomically: true, encoding: .utf8)

                await MainActor.run {
                    lastExportURL = url
                    exportFile = ExportFile(url: url)
                    exportingKind = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to export \(item.label.lowercased()): \(RecordError.safe(error).localizedDescription)"
                    exportingKind = nil
                }
            }
        }
    }

    private func rows(for kind: DataExportKind) async throws -> [[String: String]] {
        switch kind {
        case .invoicePayments: return try await CSVExportDataSource.fetchRawRows(table: "invoice_payments", headers: kind.headers)
        case .paymentReversals: return try await CSVExportDataSource.fetchRawRows(table: "invoice_payment_reversals", headers: kind.headers)
        case .vendors: return try await CSVExportDataSource.fetchRawRows(table: "vendors", headers: kind.headers)
        case .vendorBills: return try await CSVExportDataSource.fetchRawRows(table: "vendor_bills", headers: kind.headers)
        case .purchaseOrders: return try await CSVExportDataSource.fetchRawRows(table: "purchase_orders", headers: kind.headers)
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

enum DataExportKind {
    case invoicePayments, paymentReversals, vendors, vendorBills, purchaseOrders
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
        case .invoicePayments: return ["id", "invoice_id", "amount", "paid_on", "method", "reference", "created_at"]
        case .paymentReversals: return ["id", "payment_id", "reason", "created_at"]
        case .vendors: return ["id", "name", "email", "phone", "address", "status", "created_at", "archived_at"]
        case .vendorBills: return ["id", "vendor_id", "bill_number", "due_date", "total", "currency", "status", "notes", "created_at"]
        case .purchaseOrders: return ["id", "vendor_id", "po_number", "date", "expected_date", "total", "currency", "status", "notes", "created_at"]
        case .invoices:
            return ["id", "organization_id", "user_id", "client_id", "project_id", "invoice_number", "issue_date", "due_date", "subtotal", "tax_rate", "tax_amount", "total", "currency", "status", "notes"]
        case .invoiceLineItems:
            return ["id", "invoice_id", "description", "quantity", "rate", "amount", "order"]
        case .expenses:
            return ["id", "user_id", "project_id", "task_id", "amount", "currency", "category", "description", "merchant", "expense_date", "status", "notes", "invoice_id", "created_at", "updated_at"]
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

enum CSVExportBuilder {
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

    private static func escape(_ value: String) -> String { FinancialRules.csvCell(value) }

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

enum CSVExportDataSource {
    static func fetchRawRows(
        table: String,
        headers: [String],
        orderColumn: String = "created_at",
        ascending: Bool = false
    ) async throws -> [[String: String]] {
        let allowed = ["invoices", "invoice_line_items", "invoice_payments", "invoice_payment_reversals", "expenses", "bills", "clients", "projects", "time_entries", "tax_filings", "vendors", "vendor_bills", "purchase_orders"]
        guard allowed.contains(table), !headers.contains(where: { ["receipt_url", "receipt_path", "issued_snapshot"].contains($0) }) else { throw RecordError.invalid }
        var records: [[String: Any]] = []
        while true {
            let response = try await SupabaseClientManager.shared.client.from(table)
                .select(headers.joined(separator: ",")).order(orderColumn, ascending: ascending).order("id")
                .range(from: records.count, to: records.count + 499).execute()
            guard let page = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else { throw RecordError.invalid }
            records += page
            guard records.count <= 10000 else { throw RecordError(message: "This export exceeds the 10,000 record limit. Use a reporting-period export.") }
            if page.count < 500 { break }
        }
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
