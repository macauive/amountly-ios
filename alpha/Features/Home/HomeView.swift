import SwiftUI

enum FinancialSearchDestination { case invoices, bills, expenses, timeEntries, projects, taxPrep }

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    let onFinancialSearchDestination: (FinancialSearchDestination) -> Void
    @State private var invoices: [Invoice] = []
    @State private var expenses: [Expense] = []
    @State private var bills: [Bill] = []
    @State private var vendorBills: [VendorBill] = []
    @State private var time: [TimeEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var showInvoice = false
    @State private var showBill = false
    @State private var showExpense = false
    @State private var showPayment = false
    @State private var showTime = false
    @State private var showAccount = false
    init(onFinancialSearchDestination: @escaping (FinancialSearchDestination) -> Void = { _ in }) { self.onFinancialSearchDestination = onFinancialSearchDestination }
    private var currency: String { appState.currentUser?.reportingCurrency ?? "USD" }
    private var personal: Bool { appState.currentUser?.accountType == .personal }
    private var openInvoices: [Invoice] { invoices.filter { $0.currency == currency && [.sent, .overdue].contains($0.status) } }
    private func thisMonth(_ date: Date) -> Bool { Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) }
    private var received: Double { FinancialRules.sum(invoices.filter { $0.currency == currency }.flatMap { $0.payments ?? [] }.filter { !$0.isReversed && thisMonth($0.paid_on) }.map(\.amount)) }
    private var spending: Double { FinancialRules.sum(expenses.filter { $0.currency == currency && $0.status != .rejected && thisMonth($0.expenseDate) }.map(\.amount)) }
    private var dueBills: Double { personal ? FinancialRules.sum(bills.filter { $0.currency == currency && !$0.isPaid && $0.status != .cancelled }.map(\.amount)) : FinancialRules.sum(vendorBills.filter { $0.currency == currency && $0.isOpen }.map(\.total)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Money Overview").font(.largeTitle.bold())
                    Text("\(Date().formatted(.dateTime.month(.wide).year())) · \(currency)").foregroundStyle(.secondary)
                    if loading { ProgressView("Loading workspace…") }
                    else if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
                    else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            metric(personal ? "Bills Due" : "Cash received MTD", amount: personal ? dueBills : received, icon: "dollarsign.circle")
                            metric(personal ? "Monthly Spending" : "Open Invoices", amount: personal ? spending : FinancialRules.sum(openInvoices.map(\.balanceDue)), icon: "doc.text")
                            metric(personal ? "Payments Made" : "Vendor Bills Due", amount: personal ? FinancialRules.sum(bills.filter { $0.currency == currency && $0.isPaid && $0.paidAt.map(thisMonth) == true }.map(\.amount)) : dueBills, icon: "creditcard")
                            if personal {
                                metric("Upcoming Bills", text: String(bills.filter { !$0.isPaid && $0.status != .cancelled }.count), icon: "calendar")
                            } else {
                                metric(appState.currentUser?.accountType == .business ? "Team Hours" : "Billable Hours", text: String(format: "%.1fh", time.filter { thisMonth($0.startAt) }.reduce(0) { $0 + $1.durationHours }), icon: "clock")
                            }
                        }
                        Text("Cash received includes recorded payments only. Totals exclude other currencies.").font(.caption).foregroundStyle(.secondary)
                        GroupBox("Needs attention") {
                            VStack(alignment: .leading, spacing: 12) {
                                if !personal {
                                    Button("\(openInvoices.filter(\.isOverdue).count) overdue invoices") { onFinancialSearchDestination(.invoices) }
                                    Button("\(invoices.filter { $0.status == .draft }.count) invoice drafts") { onFinancialSearchDestination(.invoices) }
                                }
                                Button("\(expenses.filter { $0.status == .draft || $0.status == .rejected }.count) expenses to review") { onFinancialSearchDestination(.expenses) }
                                NavigationLink("Open Review Inbox", destination: ReviewInboxView())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }
                        DashboardAI(input: aiInput, currency: currency, navigate: onFinancialSearchDestination).id(appState.currentUser?.id)
                        GroupBox("Financial Search") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Search invoices, expenses, bills…", text: $search).textFieldStyle(.roundedBorder)
                                if !search.isEmpty {
                                    ForEach(invoices.filter { $0.invoiceNumber.localizedCaseInsensitiveContains(search) || ($0.displayClientName?.localizedCaseInsensitiveContains(search) ?? false) }.prefix(5)) { row in
                                        Button("\(row.invoiceNumber) · \(row.totalFormatted)") { onFinancialSearchDestination(.invoices) }
                                    }
                                    ForEach(expenses.filter { $0.description.localizedCaseInsensitiveContains(search) || ($0.merchant?.localizedCaseInsensitiveContains(search) ?? false) || (search.lowercased().contains("receipt") && !$0.hasReceipt) }.prefix(5)) { row in
                                        Button("\(row.description) · \(row.amountFormatted)") { onFinancialSearchDestination(.expenses) }
                                    }
                                    ForEach(bills.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.payee.localizedCaseInsensitiveContains(search) || (search.lowercased().contains("overdue") && $0.isOverdue) }.prefix(5)) { row in
                                        Button("\(row.name) · \(row.amountFormatted)") { onFinancialSearchDestination(.bills) }
                                    }
                                    ForEach(vendorBills.filter { $0.bill_number.localizedCaseInsensitiveContains(search) || ($0.vendor?.name.localizedCaseInsensitiveContains(search) ?? false) }.prefix(5)) { row in
                                        Button(row.bill_number) { onFinancialSearchDestination(.bills) }
                                    }
                                    if search.lowercased().contains("tax") { Button("Open Tax Prep") { onFinancialSearchDestination(.taxPrep) } }
                                }
                            }.padding(.top, 8)
                        }
                    }
                    GroupBox("Quick Actions") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            if appState.hasCapability(.createInvoices) { Button("Create Invoice", systemImage: "doc.badge.plus") { showInvoice = true } }
                            if appState.hasCapability(.viewBills) || appState.hasCapability(.viewAccountsPayable) { Button("Add Bill", systemImage: "creditcard") { showBill = true } }
                            if appState.hasCapability(.submitExpenses) { Button("Add Expense", systemImage: "receipt") { showExpense = true } }
                            if appState.hasCapability(.recordPayments) { Button("Record Payment", systemImage: "dollarsign.circle") { showPayment = true } }
                            if appState.hasCapability(.trackTime) && !personal { Button("Log Time", systemImage: "clock") { showTime = true } }
                        }.buttonStyle(.bordered).padding(.top, 8)
                    }
                    GroupBox("Monthly Close") {
                        VStack(alignment: .leading, spacing: 12) {
                            if !personal { Button("Review open invoices") { onFinancialSearchDestination(.invoices) } }
                            Button("Review bills due") { onFinancialSearchDestination(.bills) }
                            Button("Capture missing expenses") { onFinancialSearchDestination(.expenses) }
                            Button("Review income and expenses for export") { onFinancialSearchDestination(.taxPrep) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }.padding().padding(.bottom, 70)
            }.background(Color.alphaGroupedBackground)
                .navigationTitle("Overview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Account", systemImage: "person.crop.circle") { showAccount = true } } }
                .task { await load() }.refreshable { await load() }
                .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await load() } }
                .sheet(isPresented: $showInvoice) { CreateInvoiceSheet(isPresented: $showInvoice) }
                .sheet(isPresented: $showBill) { QuickBillSheet(isPresented: $showBill) }
                .sheet(isPresented: $showExpense) { ExpenseFormSheet(isPresented: $showExpense, onSave: {}) }
                .sheet(isPresented: $showPayment) { QuickPaymentSheet(isPresented: $showPayment) }
                .sheet(isPresented: $showTime) { QuickEntrySheet(isPresented: $showTime) }
                .sheet(isPresented: $showAccount) { AccountSheet(isPresented: $showAccount) }
        }
    }
    private var aiInput: AIDashboardInput {
        var routes: [AIRoute] = [.dashboard, .expenses]
        if appState.hasCapability(.viewInvoices) || appState.hasCapability(.viewAccountsReceivable) { routes.append(.invoices) }
        if personal || appState.hasCapability(.viewAccountsPayable) { routes.append(.bills) }
        if appState.hasCapability(.trackTime) { routes.append(.time) }
        if appState.hasCapability(.viewTaxDashboard) { routes.append(.tax) }
        return .summary(account: appState.currentUser?.accountType ?? .personal, query: search, currency: currency,
            invoices: invoices, expenses: expenses, bills: bills, vendorBills: vendorBills, time: time, routes: routes)
    }
    private func metric(_ title: String, amount: Double, icon: String) -> some View { metric(title, text: amount.formatted(.currency(code: currency)), icon: icon) }
    private func metric(_ title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.caption); Text(text).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1) }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding().background(Color.alphaCardBackground, in: RoundedRectangle(cornerRadius: 12))
    }
    private func load() async {
        loading = true; error = nil; invoices = []; expenses = []; bills = []; vendorBills = []; time = []; defer { loading = false }
        do {
            expenses = try await ExpenseRepository().fetchExpenses()
            if appState.hasCapability(.viewInvoices) || appState.hasCapability(.viewAccountsReceivable) { invoices = try await InvoiceRepository().fetchInvoices() }
            if personal { bills = try await BillRepository().fetchBills() }
            else {
                if appState.hasCapability(.viewAccountsPayable) { vendorBills = try await VendorRepository().bills() }
                time = try await TimeEntryRepository().fetchTimeEntries()
            }
        } catch {
#if DEBUG
            recordDiagnostic(error)
#endif
            self.error = "Could not load the complete workspace. Pull to retry."
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState
    let onCreateInvoice: () -> Void
    let onLogHours: () -> Void
    let onAddExpense: () -> Void
    let onRecordPayment: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 64))
                    .foregroundColor(.alphaSecondaryText.opacity(0.5))

                Text("Welcome to Amountly!")
                    .font(.alphaTitle)
                    .foregroundColor(.alphaPrimaryText)

                Text(emptyStateMessage)
                    .font(.alphaBody)
                    .foregroundColor(.alphaSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 16) {
                // Show quick actions based on capabilities
                if appState.hasCapability(.createInvoices) {
                    QuickActionCard(
                        title: "Create Invoice",
                        description: "Bill your clients for completed work",
                        icon: "doc.text.fill",
                        backgroundColor: Color.blue.opacity(0.1),
                        iconColor: .blue,
                        action: onCreateInvoice
                    )
                }

                if appState.hasCapability(.trackTime) {
                    QuickActionCard(
                        title: "Log Time",
                        description: "Track billable time on tasks",
                        icon: "clock.fill",
                        backgroundColor: Color.purple.opacity(0.1),
                        iconColor: .purple,
                        action: onLogHours
                    )
                }

                if appState.hasCapability(.submitExpenses) {
                    QuickActionCard(
                        title: "Add Expense",
                        description: "Track business expenses",
                        icon: "dollarsign.circle.fill",
                        backgroundColor: Color.green.opacity(0.1),
                        iconColor: .green,
                        action: onAddExpense
                    )
                }

                if appState.hasCapability(.recordPayments) {
                    QuickActionCard(
                        title: "Record Payment",
                        description: "Log received payments",
                        icon: "creditcard.fill",
                        backgroundColor: Color.orange.opacity(0.1),
                        iconColor: .orange,
                        action: onRecordPayment
                    )
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        switch appState.currentUser?.accountType {
        case .personal:
            return "Track bills, payments, and personal expenses to manage your finances."
        case .freelancer:
            return "Log billable hours, create invoices, and track client payments."
        case .business:
            return "Start managing your team's time and projects. Create invoices and track revenue."
        case .none:
            return "Get started with Amountly!"
        }
    }
}
