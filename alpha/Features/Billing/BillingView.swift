//
//  BillingView.swift
//  alpha
//
//  Created by Claude Code on 12/16/25.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
class BillingViewModel: ObservableObject {
    @Published var invoices: [Invoice] = []
    private var currency = "USD"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: InvoiceFilter = .all

    // Summary metrics
    @Published var outstandingCount: Int = 0
    @Published var outstandingTotal: Double = 0
    @Published var draftCount: Int = 0
    @Published var paidThisMonth: Double = 0

    private let invoiceRepository = InvoiceRepository()

    var filteredInvoices: [Invoice] {
        switch selectedFilter {
        case .outstanding:
            return invoices.filter { $0.status == .sent || $0.status == .overdue }
        case .all:
            return invoices
        case .drafts:
            return invoices.filter { $0.status == .draft }
        case .paid:
            return invoices.filter { $0.status == .paid }
        }
    }

    // MARK: - Public Methods

    func loadInvoices() async {
        isLoading = true
        errorMessage = nil

        do {
            currency = try await AuthService.shared.getCurrentUser().reportingCurrency
            invoices = try await invoiceRepository.fetchInvoices()
            calculateSummaries()
        } catch {
            print("Failed to load invoices: \(error)")
            errorMessage = "Failed to load invoices"
            invoices = []
        }

        isLoading = false
    }

    func markAsPaid(_ invoiceId: String) async {
        do {
            _ = try await invoiceRepository.markAsPaid(id: invoiceId)
            await loadInvoices()
        } catch {
            errorMessage = "Failed to update invoice: \(RecordError.safe(error).localizedDescription)"
        }
    }

    func sendInvoice(_ invoiceId: String) async {
        do {
            _ = try await invoiceRepository.sendInvoice(id: invoiceId)
            await loadInvoices()
        } catch {
            errorMessage = "Failed to send invoice: \(RecordError.safe(error).localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func calculateSummaries() {
        let outstanding = invoices.filter { $0.currency == currency && ($0.status == .sent || $0.status == .overdue) }
        outstandingCount = outstanding.count
        outstandingTotal = outstanding.reduce(0) { $0 + $1.balanceDue }

        draftCount = invoices.filter { $0.status == .draft }.count

        // Calculate paid this month
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        paidThisMonth = invoices.filter { $0.currency == currency }.flatMap { $0.payments ?? [] }.filter { !$0.isReversed && $0.paid_on >= startOfMonth && $0.paid_on <= now }.reduce(0) { $0 + $1.amount }

    }
}

enum InvoiceFilter: String, CaseIterable, Identifiable {
    case outstanding = "Outstanding"
    case all = "All"
    case drafts = "Drafts"
    case paid = "Paid"

    var id: String { rawValue }
}

// MARK: - BillingView

struct BillingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = BillingViewModel()
    @State private var selectedTab = 0
    @State private var selectedInvoice: Invoice?
    @State private var showingCreateInvoice = false
    @State private var showingBillingRules = false
    var showSectionPicker = true
    var embeddedInParentNavigation = false

    var body: some View {
        Group {
            if embeddedInParentNavigation {
                billingBody
            } else {
                NavigationStack {
                    billingBody
                }
            }
        }
    }

    @ViewBuilder
    private var billingBody: some View {
        if appState.hasCapability(.viewBills) && !appState.hasCapability(.viewInvoices) {
            BillsView()
                .navigationTitle("Bills & Payments")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            // Freelancer / Business users: full invoice management
            VStack(spacing: 0) {
                // Tab Picker - only show if user has expense capabilities
                if showSectionPicker && (appState.hasCapability(.submitExpenses) || appState.hasCapability(.approveExpenses)) {
                    Picker("", selection: $selectedTab) {
                        Text("Invoices").tag(0)
                        Text("Expenses").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                // Content
                if selectedTab == 0 {
                    invoicesContent
                } else {
                    ExpenseViewContent()
                }
            }
            .background(Color.alphaGroupedBackground)
            .navigationTitle(embeddedInParentNavigation ? "Money" : "Billing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if appState.hasCapability(.configureBillingRules) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: { showingBillingRules = true }) {
                                Label("Billing Rules", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .medium))
                        }
                    }
                }
            }
            .sheet(item: $selectedInvoice) { invoice in
                InvoiceDetailSheet(invoice: invoice, onUpdate: {
                    Task {
                        await viewModel.loadInvoices()
                    }
                })
                .withAppTheme()
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await viewModel.loadInvoices() } }
            .sheet(isPresented: $showingCreateInvoice) {
                CreateInvoiceSheet(isPresented: $showingCreateInvoice)
                    .withAppTheme()
            }
            .sheet(isPresented: $showingBillingRules) {
                BillingRulesSheet(isPresented: $showingBillingRules)
                    .withAppTheme()
            }
        }
    }

    // MARK: - Invoices Content

    private var invoicesContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Cards
                HStack(spacing: 12) {
                    BillingSummaryCard(
                        title: "Outstanding",
                        count: viewModel.outstandingCount,
                        total: viewModel.outstandingTotal,
                        icon: "doc.text",
                        color: .orange
                    )

                    BillingSummaryCard(
                        title: "Paid This Month",
                        count: nil,
                        total: viewModel.paidThisMonth,
                        icon: "checkmark.circle",
                        color: .green
                    )
                }
                .padding(.horizontal)

                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(InvoiceFilter.allCases) { filter in
                            FilterPill(
                                title: filter.rawValue,
                                count: countForFilter(filter),
                                isSelected: viewModel.selectedFilter == filter
                            ) {
                                viewModel.selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Invoices List
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if viewModel.filteredInvoices.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredInvoices) { invoice in
                            InvoiceCard(invoice: invoice)
                                .onTapGesture {
                                    selectedInvoice = invoice
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.loadInvoices()
        }
        .task {
            await viewModel.loadInvoices()
        }
    }

    private func countForFilter(_ filter: InvoiceFilter) -> Int {
        switch filter {
        case .outstanding:
            return viewModel.invoices.filter { $0.status == .sent || $0.status == .overdue }.count
        case .all:
            return viewModel.invoices.count
        case .drafts:
            return viewModel.invoices.filter { $0.status == .draft }.count
        case .paid:
            return viewModel.invoices.filter { $0.status == .paid }.count
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.alphaSecondaryText)

            Text("No invoices yet")
                .font(.alphaBody)
                .foregroundColor(.alphaSecondaryText)

            Text("Tap + to create your first invoice")
                .font(.alphaBodySmall)
                .foregroundColor(.alphaTertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Bills

@MainActor
class BillsViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    private var currency = "USD"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: BillListFilter = .open

    @Published var unpaidTotal: Double = 0
    @Published var dueThisWeekCount = 0
    @Published var paidThisMonthTotal: Double = 0

    private let billRepository = BillRepository()

    var filteredBills: [Bill] {
        switch selectedFilter {
        case .open:
            return bills.filter { !$0.isPaid && $0.status != .cancelled }
        case .all:
            return bills
        case .paid:
            return bills.filter { $0.isPaid }
        case .overdue:
            return bills.filter { $0.isOverdue }
        }
    }

    func loadBills() async {
        isLoading = true
        errorMessage = nil

        do {
            currency = try await AuthService.shared.getCurrentUser().reportingCurrency
            bills = try await billRepository.fetchBills()
            calculateSummaries()
        } catch {
            errorMessage = "Failed to load bills: \(RecordError.safe(error).localizedDescription)"
            bills = []
            calculateSummaries()
        }

        isLoading = false
    }

    func markPaid(_ bill: Bill) async {
        do {
            try await billRepository.action(bill, action: "pay", paidOn: Date())
            await loadBills()
        } catch {
            errorMessage = "Failed to mark bill paid: \(RecordError.safe(error).localizedDescription)"
        }
    }

    func deleteBill(_ bill: Bill) async {
        do {
            try await billRepository.action(bill, action: "cancel")
            await loadBills()
        } catch {
            errorMessage = "Failed to delete bill: \(RecordError.safe(error).localizedDescription)"
        }
    }

    private func calculateSummaries() {
        let calendar = Calendar.current
        let now = Calendar.current.startOfDay(for: Date())
        let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now

        let openBills = bills.filter { $0.currency == currency && !$0.isPaid && $0.status != .cancelled }
        unpaidTotal = openBills.reduce(0) { $0 + $1.amount }
        dueThisWeekCount = openBills.filter { $0.dueDate >= now && $0.dueDate <= weekFromNow }.count
        paidThisMonthTotal = bills.filter { bill in
            guard bill.currency == currency, bill.isPaid, let paidAt = bill.paidAt else { return false }
            return paidAt >= startOfMonth
        }.reduce(0) { $0 + $1.amount }
    }
}

enum BillListFilter: String, CaseIterable, Identifiable {
    case open = "Open"
    case all = "All"
    case paid = "Paid"
    case overdue = "Overdue"

    var id: String { rawValue }
}

struct BillsView: View {
    @StateObject private var viewModel = BillsViewModel()
    @State private var showingNewBill = false
    @State private var paymentBill: Bill?
    @State private var cancelledBill: Bill?
    @State private var paidOn = Date()
    @State private var savingBill = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    BillingSummaryCard(
                        title: "Open",
                        count: viewModel.bills.filter { !$0.isPaid && $0.status != .cancelled }.count,
                        total: viewModel.unpaidTotal,
                        icon: "creditcard",
                        color: .blue
                    )

                    BillingSummaryCard(
                        title: "Paid MTD",
                        count: nil,
                        total: viewModel.paidThisMonthTotal,
                        icon: "checkmark.circle",
                        color: .green
                    )
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BillListFilter.allCases) { filter in
                            FilterPill(
                                title: filter.rawValue,
                                count: countForFilter(filter),
                                isSelected: viewModel.selectedFilter == filter
                            ) {
                                viewModel.selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if viewModel.filteredBills.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredBills) { bill in
                            BillCard(bill: bill) {
                                paymentBill = bill
                            } onDelete: {
                                cancelledBill = bill
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color.alphaGroupedBackground)
        .navigationTitle("Bills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingNewBill = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.loadBills()
        }
        .task {
            await viewModel.loadBills()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await viewModel.loadBills() } }
        .sheet(item: $paymentBill) { bill in
            NavigationStack {
                Form {
                    Text(bill.name)
                    Text(bill.amountFormatted)
                    DatePicker("Paid on", selection: $paidOn, in: ...Date(), displayedComponents: .date)
                    Text("Records a payment already made. No money is moved.")
                    if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red) }
                    Button("Confirm Payment") { Task {
                        savingBill = true; defer { savingBill = false }
                        do { try await BillRepository().action(bill, action: "pay", paidOn: paidOn); paymentBill = nil; await viewModel.loadBills() }
                        catch { viewModel.errorMessage = RecordError.safe(error).localizedDescription }
                    } }.disabled(savingBill)
                }.navigationTitle("Record Bill Payment")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { paymentBill = nil }.disabled(savingBill) } }
            }.interactiveDismissDisabled(savingBill)
        }
        .confirmationDialog("Cancel this bill?", isPresented: Binding(get: { cancelledBill != nil }, set: { if !$0 { cancelledBill = nil } })) {
            if let bill = cancelledBill { Button("Cancel Bill", role: .destructive) { Task { await viewModel.deleteBill(bill) } } }
        } message: { Text("The bill and its history will be preserved.") }
        .sheet(isPresented: $showingNewBill) {
            QuickBillSheet(isPresented: $showingNewBill)
                .withAppTheme()
        }
        .alert("Bills Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func countForFilter(_ filter: BillListFilter) -> Int {
        switch filter {
        case .open:
            return viewModel.bills.filter { !$0.isPaid && $0.status != .cancelled }.count
        case .all:
            return viewModel.bills.count
        case .paid:
            return viewModel.bills.filter { $0.isPaid }.count
        case .overdue:
            return viewModel.bills.filter { $0.isOverdue }.count
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No bills yet")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Tap + to add a vendor bill")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct BillCard: View {
    let bill: Bill
    var onMarkPaid: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.alphaPrimaryText)

                    Text(bill.payee)
                        .font(.system(size: 14))
                        .foregroundColor(.alphaSecondaryText)
                }

                Spacer()

                Text(bill.amountFormatted)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.alphaPrimaryText)
            }

            HStack {
                Label(bill.dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(bill.isOverdue ? .red : .alphaSecondaryText)

                Spacer()

                Text(bill.effectiveStatus.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor)
                    .cornerRadius(8)
            }

            if !bill.isPaid && bill.status != .cancelled {
                Button(action: onMarkPaid) {
                    Label("Mark Paid", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.alphaCardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Cancel Bill", systemImage: "xmark.circle")
            }
        }
    }

    private var statusColor: Color {
        switch bill.effectiveStatus {
        case .paid:
            return .green
        case .overdue:
            return .red
        case .due:
            return .orange
        case .cancelled:
            return .gray
        case .upcoming:
            return .blue
        }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .foregroundColor(isSelected ? Color(uiColor: .systemBackground) : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color(uiColor: .label) : Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(20)
        }
    }
}

// MARK: - Billing Summary Card

struct BillingSummaryCard: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let count: Int?
    let total: Double
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.alphaPrimaryText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.alphaSecondaryText)

                Text(total, format: .currency(code: appState.currentUser?.reportingCurrency ?? "USD"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.alphaPrimaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.alphaCardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Invoice Card

struct InvoiceCard: View {
    let invoice: Invoice
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.alphaPrimaryText)

                    if let clientName = invoice.displayClientName {
                        Text(clientName)
                            .font(.system(size: 14))
                            .foregroundColor(.alphaSecondaryText)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(invoice.totalFormatted)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.alphaPrimaryText)

                    statusBadge
                }
            }

            if !compact {
                Divider()

                // Details Row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Due Date")
                            .font(.system(size: 12))
                            .foregroundColor(.alphaSecondaryText)

                        Text(invoice.dueDate, style: .date)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.alphaPrimaryText)
                    }

                    Spacer()

                    if invoice.isOverdue {
                        Label {
                            Text("Overdue by \(-invoice.daysUntilDue) days")
                                .font(.system(size: 12, weight: .medium))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundColor(.alphaError)
                    } else if invoice.status == .sent {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Days Until Due")
                                .font(.system(size: 12))
                                .foregroundColor(.alphaSecondaryText)

                            Text("\(invoice.daysUntilDue)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.alphaPrimaryText)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.alphaCardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(invoice.isOverdue ? Color.alphaError.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }

    private var statusBadge: some View {
        Text(invoice.displayStatus.displayName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .cornerRadius(6)
    }

    private var statusColor: Color {
        switch invoice.displayStatus {
        case .draft:
            return .gray
        case .sent:
            return .blue
        case .paid:
            return .green
        case .overdue:
            return .red
        case .cancelled:
            return .gray
        }
    }
}

// MARK: - Billing Rules Content

struct BillingRulesContent: View {
    @StateObject private var viewModel = BillingRulesViewModel()

    var body: some View {
        List {
            // Active Projects Section
            if !viewModel.filteredActiveProjects.isEmpty {
                Section {
                    ForEach(viewModel.filteredActiveProjects) { project in
                        NavigationLink {
                            ProjectBillingEditView(project: project) {
                                Task {
                                    await viewModel.loadProjects()
                                }
                            }
                        } label: {
                            ProjectBillingRow(project: project)
                        }
                    }
                } header: {
                    Text("Active Projects")
                }
            }

            // Inactive Projects Section
            if !viewModel.filteredInactiveProjects.isEmpty {
                Section {
                    ForEach(viewModel.filteredInactiveProjects) { project in
                        NavigationLink {
                            ProjectBillingEditView(project: project) {
                                Task {
                                    await viewModel.loadProjects()
                                }
                            }
                        } label: {
                            ProjectBillingRow(project: project)
                        }
                    }
                } header: {
                    Text("Inactive Projects")
                }
            }

            // Empty State
            if viewModel.projects.isEmpty && !viewModel.isLoading {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No projects yet")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("Create a project to configure billing rules")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search projects")
        .refreshable {
            await viewModel.loadProjects()
        }
        .task {
            await viewModel.loadProjects()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }
}

// MARK: - Billing Rules Sheet

struct BillingRulesSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            BillingRulesContent()
                .navigationTitle("Billing Rules")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
        }
    }
}

// MARK: - Project Billing Row

struct ProjectBillingRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: project.color ?? "#007AFF"))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    if let client = project.client {
                        Text(client.name)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }

                    Text(project.billingModel.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
            }

            Spacer()

            if project.rate != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(project.displayRate)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if let budget = project.budget, budget > 0 {
                        Text(String(format: "Budget: $%.0f", budget))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invoice Detail Sheet

struct InvoiceDetailSheet: View {
    @EnvironmentObject var appState: AppState
    let invoice: Invoice
    var onUpdate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false
    @State private var errorMessage: String?
    private struct PDFDocument: Identifiable { let id = UUID(); let url: URL }
    @State private var sharedPDF: PDFDocument?
    @State private var pdfURL: URL?
    @State private var showingPayment = false
    @State private var showingReminder = false

    private let invoiceRepository = InvoiceRepository()
    private let pdfGenerator = InvoicePDFGenerator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Header
                    VStack(spacing: 8) {
                        Text(invoice.totalFormatted)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.primary)

                        statusBadge
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))

                    // Invoice Info & Bill To
                    VStack(spacing: 16) {
                        DetailRow(label: "Invoice Number", value: invoice.invoiceNumber)

                        Divider()

                        // Bill To Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bill To")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            if let clientName = invoice.displayClientName {
                                Text(clientName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)

                                if let email = invoice.displayClientEmail {
                                    Text(email)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Unknown Client")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        DetailRow(label: "Issue Date", value: invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                        DetailRow(label: "Due Date", value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))

                        if let project = invoice.project {
                            DetailRow(label: "Project", value: project.name)
                        }

                        if invoice.isOverdue {
                            HStack {
                                Text("Status")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Label("Overdue by \(-invoice.daysUntilDue) days", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Line Items Section
                    if let lineItems = invoice.issuedSnapshot?.lines ?? invoice.lineItems, !lineItems.isEmpty {
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text("Description")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("Qty")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)

                                Text("Rate")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .trailing)

                                Text("Amount")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))

                            // Line Items
                            ForEach(lineItems) { item in
                                HStack(alignment: .top) {
                                    Text(item.description)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(item.quantity, format: .number.precision(.fractionLength(0...4)))
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .frame(width: 40, alignment: .trailing)

                                    Text(item.rate, format: .currency(code: invoice.currency))
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .frame(width: 70, alignment: .trailing)

                                    Text(item.amount, format: .currency(code: invoice.currency))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                if item.id != lineItems.last?.id {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Totals Section
                    VStack(spacing: 12) {
                        DetailRow(label: "Subtotal", value: invoice.subtotal.formatted(.currency(code: invoice.currency)))

                        if let taxRate = invoice.taxRate, let taxAmount = invoice.taxAmount {
                            DetailRow(label: "Tax (\(String(format: "%.1f%%", taxRate)))", value: taxAmount.formatted(.currency(code: invoice.currency)))
                        }

                        Divider()

                        DetailRow(label: "Total", value: invoice.totalFormatted, isBold: true)
                        DetailRow(label: "Received", value: invoice.amountPaid.formatted(.currency(code: invoice.currency)))
                        DetailRow(label: "Balance due", value: invoice.balanceDue.formatted(.currency(code: invoice.currency)))
                        if invoice.needsLegacyReview { Text("Legacy paid status: no payment evidence recorded. Review before including in cash income.").font(.caption).foregroundStyle(.orange) }
                        ForEach(invoice.payments ?? []) { payment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(payment.paid_on, style: .date); Spacer(); Text(payment.amount, format: .currency(code: invoice.currency)) }
                                Text(payment.method.replacingOccurrences(of: "_", with: " "))
                                if let reference = payment.reference, !reference.isEmpty { Text(reference) }
                                if payment.isReversed {
                                    Text("Corrected" + (payment.reversal?.first?.reason.map { ": \($0)" } ?? "")).foregroundStyle(.secondary)
                                }
                            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let notes = invoice.notes, !notes.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Text(notes)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    InvoiceRecordActions(invoice: invoice, onSaved: { onUpdate(); dismiss() })

                    // Action Buttons
                    VStack(spacing: 12) {
                        if invoice.status == .draft {
                            Button(action: { Task { await sendInvoice() } }) {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text("Issue Invoice")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }

                        if invoice.status == .sent || invoice.status == .overdue {
                            Button(action: { showingPayment = true }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Record Payment")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }

                        if invoice.status == .paid, let paidAt = invoice.lastPaymentDate {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Paid on \(paidAt.formatted(date: .abbreviated, time: .omitted))")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }

                        if [.sent, .overdue].contains(invoice.status), invoice.balanceDue > 0 {
                            Button("Draft Payment Reminder", systemImage: "wand.and.stars") { showingReminder = true }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                        // Download PDF Button
                        Button(action: generateAndSharePDF) {
                            HStack {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("Download PDF")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(uiColor: .separator), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Invoice Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isUpdating {
                    ProgressView()
                }
            }
            .sheet(isPresented: $showingReminder) { AIReminderSheet(invoice: invoice) }
            .sheet(isPresented: $showingPayment) {
                QuickPaymentSheet(isPresented: $showingPayment, initialInvoice: invoice, onSave: { onUpdate(); dismiss() })
            }
            .sheet(item: $sharedPDF, onDismiss: { if let pdfURL { try? FileManager.default.removeItem(at: pdfURL.deletingLastPathComponent()) }; pdfURL = nil }) { document in
                ShareSheet(activityItems: [document.url]).withAppTheme()
            }
        }
    }

    private func generateAndSharePDF() {
        guard let pdfData = pdfGenerator.generatePDF(for: invoice, organization: appState.organization) else {
            errorMessage = "Failed to generate PDF"
            return
        }

        let filename = "Invoice-\(invoice.invoiceNumber)"
        guard let url = pdfGenerator.savePDF(pdfData, filename: filename) else {
            errorMessage = "Failed to save PDF"
            return
        }

        pdfURL = url
        sharedPDF = PDFDocument(url: url)
    }

    private var statusBadge: some View {
        Text(invoice.displayStatus.displayName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor)
            .cornerRadius(8)
    }

    private var statusColor: Color {
        switch invoice.displayStatus {
        case .draft: return .gray
        case .sent: return .blue
        case .paid: return .green
        case .overdue: return .red
        case .cancelled: return .gray
        }
    }

    private func sendInvoice() async {
        isUpdating = true
        errorMessage = nil

        do {
            try await invoiceRepository.action(invoice, "issue")
            onUpdate()
            dismiss()
        } catch {
            errorMessage = "Failed to send invoice: \(RecordError.safe(error).localizedDescription)"
        }

        isUpdating = false
    }

    private func markAsPaid() async {
        isUpdating = true
        errorMessage = nil

        do {
            _ = try await invoiceRepository.markAsPaid(id: invoice.id)
            onUpdate()
            dismiss()
        } catch {
            errorMessage = "Failed to update invoice: \(RecordError.safe(error).localizedDescription)"
        }

        isUpdating = false
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    var isBold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(isBold ? .semibold : .regular)
                .foregroundColor(.primary)
        }
        .font(.system(size: 15))
    }
}

// MARK: - Personal Bills Placeholder

struct PersonalBillsPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 32)

                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 56))
                    .foregroundColor(.alphaSecondaryText)

                VStack(spacing: 8) {
                    Text("Bills & Payments")
                        .font(.alphaTitle)
                        .foregroundColor(.alphaPrimaryText)

                    Text("Track your recurring bills and payment history.")
                        .font(.alphaBody)
                        .foregroundColor(.alphaSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundColor(.alphaSecondaryText)

                    Text("Full bills management is available on the web app at alpha.app")
                        .font(.alphaBodySmall)
                        .foregroundColor(.alphaTertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding()
                .background(Color.alphaCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.alphaGroupedBackground)
    }
}

// MARK: - Preview

#Preview("Billing View") {
    BillingView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = true
            state.currentUser = .preview
            return state
        }())
}
