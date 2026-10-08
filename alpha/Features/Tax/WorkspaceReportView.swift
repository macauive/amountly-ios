import SwiftUI

struct WorkspaceReportView: View {
    @EnvironmentObject private var appState: AppState
    @State private var invoices: [Invoice] = []
    @State private var expenses: [Expense] = []
    @State private var filings: [FilingReminder] = []
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = 1
    @State private var currency = "USD"
    @State private var basis = "cash"
    @State private var loading = true
    @State private var error: String?
    @State private var exportURL: URL?
    @State private var showingAccountantPacket = false
    private struct ExportDocument: Identifiable { let id = UUID(); let url: URL }
    @State private var exportDocument: ExportDocument?
    private struct Row { let date: String; let type: String; let name: String; let amount: Double; let status: String }
    private var period: (start: String, end: String) { FinancialRules.period(year: year, month: month)! }
    private var inclusivePeriodEnd: String { RecordCoding.day(Calendar.current.date(byAdding: .day, value: -1, to: RecordCoding.parseDate(period.end)!)!) }
    private func inPeriod(_ date: Date) -> Bool { let day = RecordCoding.day(date); return day >= period.start && day < period.end }
    private var rows: [Row] {
        let income: [Row] = invoices.filter { $0.currency == currency && $0.status != .draft && $0.status != .cancelled }.flatMap { invoice in
            if basis == "accrual" {
                return inPeriod(invoice.issueDate) ? [Row(date: RecordCoding.day(invoice.issueDate), type: "income", name: invoice.invoiceNumber, amount: invoice.total, status: invoice.status.rawValue.uppercased())] : []
            }
            return (invoice.payments ?? []).filter { !$0.isReversed && inPeriod($0.paid_on) }.map { Row(date: RecordCoding.day($0.paid_on), type: "income", name: invoice.invoiceNumber, amount: $0.amount, status: "RECEIVED") }
        }
        return (income + expenses.filter { $0.currency == currency && $0.status != .rejected && inPeriod($0.expenseDate) }.map {
            Row(date: RecordCoding.day($0.expenseDate), type: "expense", name: $0.description, amount: $0.amount, status: $0.status.rawValue)
        }).sorted { $0.date < $1.date }
    }
    private var income: Double { FinancialRules.sum(rows.filter { $0.type == "income" }.map(\.amount)) }
    private var spending: Double { FinancialRules.sum(rows.filter { $0.type == "expense" }.map(\.amount)) }
    var body: some View {
        List {
            NavigationLink("Filings & Deadlines", destination: TaxRemindersView())
            Section("Reporting period") {
                Stepper("Year: \(String(year))", value: $year, in: 2000...2100)
                Picker("Starts in", selection: $month) { ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) } }
                Picker("Currency", selection: $currency) { ForEach(RecordCoding.currencies, id: \.self) { Text($0) } }
                Picker("Income basis", selection: $basis) { Text("Cash received").tag("cash"); Text("Issued invoices").tag("accrual") }
                Text("\(period.start) to \(inclusivePeriodEnd)").font(.caption)
            }
            if loading { ProgressView("Loading records…") }
            else if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
            else {
                Section("Workspace totals · \(currency)") {
                    LabeledContent(basis == "cash" ? "Cash received" : "Issued income", value: income.formatted(.currency(code: currency)))
                    LabeledContent("Captured expenses", value: spending.formatted(.currency(code: currency)))
                    LabeledContent("Net recorded income", value: (income - spending).formatted(.currency(code: currency)))
                    Text("Expenses use captured record dates. Rejected and archived expenses are excluded. Bills are not counted again as expenses. Other currencies are excluded; no conversion is applied.").font(.caption)
                }
                Section("Before exporting") {
                    LabeledContent("Legacy paid invoices without evidence", value: String(invoices.filter { $0.currency == currency && $0.needsLegacyReview }.count))
                    LabeledContent("Expenses missing receipts", value: String(expenses.filter { $0.currency == currency && inPeriod($0.expenseDate) && $0.status != .rejected && !$0.hasReceipt }.count))
                    LabeledContent("Expenses to categorize", value: String(expenses.filter { $0.currency == currency && inPeriod($0.expenseDate) && $0.status != .rejected && $0.category == .other }.count))
                    if appState.currentUser?.canExportAccountantPacket == true { Button("Export accountant packet") { showingAccountantPacket = true }.disabled(rows.isEmpty) }
                    Button("Export Workspace CSV") { export() }
                    Button("Export Tax Packet CSV") { exportPacket() }
                    Text("The tax packet includes income, expenses and filing reminders due in this reporting period.").font(.caption)
                }
                if currency == "USD" && month == 1 && appState.hasCapability(.generateTaxEstimates) {
                    Section("Illustrative US estimate") {
                        if let se = FinancialRules.selfEmploymentTax(netEarnings: max(0, income - spending) * 0.9235, year: year), let federal = FinancialRules.federalTax(income: max(0, income - spending) - se / 2, year: year) {
                            LabeledContent("Federal + self-employment", value: (se + federal).formatted(.currency(code: "USD")))
                            Text("Single-filer ordinary income illustration, not a tax bill or filing calculation. Excludes credits, QBI, state taxes, other wages, capital gains and payment safe-harbor rules.").font(.caption)
                            Link("IRS tax-year guidance", destination: URL(string: "https://www.irs.gov/newsroom/irs-releases-tax-inflation-adjustments-for-tax-year-2026-including-amendments-from-the-one-big-beautiful-bill")!)
                        } else { Text("Estimates for this year need review before use.") }
                    }
                }
            }
        }
        .navigationTitle("Tax Prep")
        .task {
            currency = appState.currentUser?.reportingCurrency ?? "USD"
            basis = appState.currentUser?.incomeBasis ?? "cash"
            month = appState.currentUser?.fiscalStartMonth ?? 1
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showingAccountantPacket) { AccountantPacketSheet(year: year, month: month, currency: currency, basis: basis, start: period.start, end: inclusivePeriodEnd) }
        .sheet(item: $exportDocument, onDismiss: { if let exportURL { try? FileManager.default.removeItem(at: exportURL) }; exportURL = nil }) { document in ShareSheet(activityItems: [document.url]) }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            async let expenseRows = ExpenseRepository().fetchExpenses()
            let canView = appState.hasCapability(.viewInvoices) || appState.hasCapability(.viewAccountsReceivable)
            invoices = canView ? try await InvoiceRepository().fetchInvoices() : []
            expenses = try await expenseRows
            filings = try await FilingReminder.fetchAll()
        } catch { self.error = "Could not load all report records. Totals and export are unavailable until the complete report loads." }
    }
    private func exportPacket() {
        let header = ["record_type", "date", "name", "category", "status", "amount", "currency", "basis", "notes"]
        let expenseRows = expenses.filter { $0.currency == currency && $0.status != .rejected && inPeriod($0.expenseDate) }.map {
            ["expense", RecordCoding.day($0.expenseDate), $0.merchant ?? $0.description, $0.category.rawValue, $0.status.rawValue, String(format: "%.2f", $0.amount), $0.currency, "recorded_expense_date", $0.notes ?? ""]
        }
        let incomeRows = rows.filter { $0.type == "income" }.map {
            [basis == "cash" ? "payment" : "invoice", $0.date, $0.name, "Income", $0.status, String(format: "%.2f", $0.amount), currency, basis, ""]
        }
        let filingRows = filings.filter { $0.due_date >= period.start && $0.due_date < period.end }.map {
            ["filing", $0.due_date, $0.name, $0.form_type, $0.status, $0.amount_due.map { String(format: "%.2f", $0) } ?? "", "USD", "filing_record", $0.notes ?? ""]
        }
        let values = expenseRows + incomeRows + filingRows
        guard !values.isEmpty, values.count <= 10000 else { error = "Choose a period with between 1 and 10,000 export records."; return }
        let csv = ([header] + values).map { $0.map(FinancialRules.csvCell).joined(separator: ",") }.joined(separator: "\r\n")
        guard csv.utf8.count <= 2_000_000 else { error = "This packet exceeds the export size limit."; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amountly-tax-packet-\(UUID().uuidString).csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); exportURL = url; exportDocument = ExportDocument(url: url) }
        catch { self.error = "Could not create the tax packet." }
    }
    private func export() {
        guard rows.count <= 10000 else { error = "This report is too large. Choose a smaller reporting scope."; return }
        let header = ["period_start","period_end","currency","income_basis","expense_basis","date","record_type","name","amount","status"]
        let inclusiveEnd = inclusivePeriodEnd
        let values = [header] + rows.map { [period.start, inclusiveEnd, currency, basis, "captured_record", $0.date, $0.type, $0.name, String(format: "%.2f", $0.amount), $0.status] }
        let csv = values.map { $0.map(FinancialRules.csvCell).joined(separator: ",") }.joined(separator: "\r\n")
        guard csv.utf8.count <= 2_000_000 else { error = "This report exceeds the export size limit."; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amountly-workspace-\(UUID().uuidString).csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); exportURL = url; exportDocument = ExportDocument(url: url) }
        catch { self.error = "Could not create the export." }
    }
}
