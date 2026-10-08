//
//  ExpenseView.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import QuickLook

// MARK: - ViewModel

@MainActor
class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    private var currency = "USD"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: ExpenseFilter = .all
    @Published var searchText = ""
    @Published var categoryFilter = "all"
    @Published var startFilter = ""
    @Published var endFilter = ""

    // Summary metrics
    @Published var totalExpenses: Double = 0
    @Published var pendingCount: Int = 0
    @Published var approvedTotal: Double = 0

    private let expenseRepository = ExpenseRepository()

    var filteredExpenses: [Expense] {
        guard (startFilter.isEmpty || AIValidation.date(startFilter) != nil), (endFilter.isEmpty || AIValidation.date(endFilter) != nil), startFilter.isEmpty || endFilter.isEmpty || startFilter <= endFilter else { return [] }
        var result = expenses.filter { (categoryFilter == "all" || $0.category.rawValue == categoryFilter) && (startFilter.isEmpty || RecordCoding.day($0.expenseDate) >= startFilter) && (endFilter.isEmpty || RecordCoding.day($0.expenseDate) <= endFilter) }

        // Apply status filter
        switch selectedFilter {
        case .all:
            break
        case .needsReview:
            result = result.filter(\.needsReview)
        case .reviewed:
            result = result.filter { $0.reviewedAt != nil }
        case .draft:
            result = result.filter { $0.status == .draft }
        case .reimbursed:
            result = result.filter { $0.status == .reimbursed }
        case .pending:
            result = result.filter { $0.status == .submitted }
        case .approved:
            result = result.filter { $0.status == .approved }
        case .rejected:
            result = result.filter { $0.status == .rejected }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { expense in
                expense.description.localizedCaseInsensitiveContains(searchText) ||
                (expense.merchant?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                expense.category.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    func loadExpenses() async {
        isLoading = true
        errorMessage = nil

        do {
            currency = try await AuthService.shared.getCurrentUser().reportingCurrency
            expenses = try await expenseRepository.fetchExpenses()
            calculateSummaries()
        } catch {
            errorMessage = "Failed to load expenses: \(RecordError.safe(error).localizedDescription)"
            expenses = []
        }

        isLoading = false
    }

    func deleteExpense(_ expenseId: String) async {
        do {
            try await expenseRepository.deleteExpense(id: expenseId, expectedVersion: expenses.first { $0.id == expenseId }?.version)
            await loadExpenses()
        } catch {
            errorMessage = "Failed to delete expense: \(RecordError.safe(error).localizedDescription)"
        }
    }

    func submitExpense(_ expenseId: String) async {
        do {
            _ = try await expenseRepository.updateStatus(id: expenseId, status: "SUBMITTED", expectedVersion: expenses.first { $0.id == expenseId }?.version)
            await loadExpenses()
        } catch {
            errorMessage = "Failed to submit expense: \(RecordError.safe(error).localizedDescription)"
        }
    }

    func approveExpense(_ expenseId: String) async {
        do {
            _ = try await expenseRepository.updateStatus(id: expenseId, status: "APPROVED", expectedVersion: expenses.first { $0.id == expenseId }?.version)
            await loadExpenses()
        } catch {
            errorMessage = "Failed to approve expense: \(RecordError.safe(error).localizedDescription)"
        }
    }

    func rejectExpense(_ expenseId: String) async {
        do {
            _ = try await expenseRepository.updateStatus(id: expenseId, status: "REJECTED", expectedVersion: expenses.first { $0.id == expenseId }?.version)
            await loadExpenses()
        } catch {
            errorMessage = "Failed to reject expense: \(RecordError.safe(error).localizedDescription)"
        }
    }

    private func calculateSummaries() {
        totalExpenses = FinancialRules.sum(expenses.filter { $0.currency == currency && $0.status != .rejected }.map(\.amount))
        pendingCount = expenses.filter { $0.status == .submitted }.count
        approvedTotal = expenses.filter { $0.status == .approved && $0.currency == currency }.reduce(0) { $0 + $1.amount }
    }
}

enum ExpenseFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs review"
    case reviewed = "Reviewed"
    case draft = "Draft"
    case reimbursed = "Reimbursed"
    case pending = "Submitted"
    case approved = "Approved"
    case rejected = "Rejected"

    var id: String { rawValue }
}

// MARK: - ExpenseView

struct ExpenseView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ExpenseViewModel()
    @State private var showingAddExpense = false
    @State private var selectedExpense: Expense?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ExpenseWorkspaceSummary(expenses: viewModel.expenses)

                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExpenseFilter.allCases) { filter in
                            ExpenseFilterPill(
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
                .padding(.bottom, 12)

                ExpenseListFilters(viewModel: viewModel)
                // Expenses List
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.filteredExpenses.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.filteredExpenses) { expense in
                            ExpenseRow(expense: expense)
                                .onTapGesture {
                                    selectedExpense = expense
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if expense.status == .draft && appState.currentUser?.accountType == .business {
                                        Button(role: .destructive) {
                                            Task { await viewModel.deleteExpense(expense.id) }
                                        } label: {
                                            Label("Archive", systemImage: "trash")
                                        }

                                        Button {
                                            Task { await viewModel.submitExpense(expense.id) }
                                        } label: {
                                            Label("Submit", systemImage: "paperplane")
                                        }
                                        .tint(.blue)
                                    }

                                    if expense.status == .submitted && expense.userId != appState.currentUser?.id && appState.hasCapability(.approveExpenses) {
                                        Button {
                                            Task { await viewModel.rejectExpense(expense.id) }
                                        } label: {
                                            Label("Reject", systemImage: "xmark")
                                        }
                                        .tint(.red)

                                        Button {
                                            Task { await viewModel.approveExpense(expense.id) }
                                        } label: {
                                            Label("Approve", systemImage: "checkmark")
                                        }
                                        .tint(.green)
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search expenses")
            .toolbar {
                if appState.hasCapability(.submitExpenses) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingAddExpense = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.loadExpenses()
            }
            .task {
                await viewModel.loadExpenses()
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await viewModel.loadExpenses() } }
            .sheet(isPresented: $showingAddExpense) {
                ExpenseFormSheet(isPresented: $showingAddExpense, onSave: {
                    Task { await viewModel.loadExpenses() }
                })
                .withAppTheme()
            }
            .sheet(item: $selectedExpense) { expense in
                ExpenseDetailSheet(expense: expense, onUpdate: {
                    Task { await viewModel.loadExpenses() }
                })
                .withAppTheme()
            }
        }
    }

    private func countForFilter(_ filter: ExpenseFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.expenses.count
        case .needsReview: return viewModel.expenses.filter(\.needsReview).count
        case .reviewed: return viewModel.expenses.filter { $0.reviewedAt != nil }.count
        case .draft: return viewModel.expenses.filter { $0.status == .draft }.count
        case .reimbursed: return viewModel.expenses.filter { $0.status == .reimbursed }.count
        case .pending:
            return viewModel.expenses.filter { $0.status == .submitted }.count
        case .approved:
            return viewModel.expenses.filter { $0.status == .approved }.count
        case .rejected:
            return viewModel.expenses.filter { $0.status == .rejected }.count
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No expenses yet")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Add your first expense to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Expense Summary Card

struct ExpenseSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Expense Filter Pill

struct ExpenseFilterPill: View {
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

// MARK: - Expense Row

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: expense.category.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(categoryColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.description)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let merchant = expense.merchant {
                        Text(merchant)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Text(expense.expenseDate, style: .date)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Amount and Status
            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.amountFormatted)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                ExpenseStatusBadge(status: expense.status)
                if expense.reviewedAt != nil { Text("Reviewed").font(.caption2).foregroundStyle(.green) }
            }
        }
        .padding(.vertical, 8)
    }

    private var categoryColor: Color {
        switch expense.category {
        case .officeSupplies: return .blue
        case .travel: return .purple
        case .meals: return .orange
        case .software: return .cyan
        case .hardware: return .indigo
        case .marketing: return .pink
        case .utilities: return .yellow
        case .other: return .gray
        }
    }
}

// MARK: - Expense Status Badge

struct ExpenseStatusBadge: View {
    let status: ExpenseStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch status {
        case .draft: return .gray
        case .submitted: return .blue
        case .approved: return .green
        case .rejected: return .red
        case .reimbursed: return .purple
        }
    }
}

// MARK: - Expense Form Sheet

struct ExpenseFormSheet: View {
    @EnvironmentObject private var appState: AppState
    @State private var pickingReceipt = false
    @State private var originalPreviewURL: URL?
    @State private var receiptURL: URL?
    @State private var receiptPreview: AIReceiptFile?
    @State private var receiptSuggestionApplied = false
    @State private var receiptConfirmed = false
    @State private var receiptTask: Task<Void, Never>?
    @State private var extractingReceipt = false
    @State private var receiptDateMissing = false
    @State private var savedExpenses: [Expense] = []
    @State private var uploadedReceipt: String?
    @State private var captureStarted = false
    @State private var captureAttempt = RecordAttempt()
    @Binding var isPresented: Bool
    var expense: Expense?
    var onSave: () -> Void
    var openReceiptPicker = false

    @State private var description = ""
    @State private var amount = ""
    @State private var currency = "USD"
    @State private var category: ExpenseCategory = .other
    @State private var merchant = ""
    @State private var expenseDate = Date()
    @State private var selectedProjectId: String?
    @State private var notes = ""
    @State private var smartCaptureText = ""
    @State private var receiptText = ""

    @State private var projects: [Project] = []
    @State private var isLoadingProjects = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingScanner = false

    private let projectRepository = ProjectRepository()
    private let expenseRepository = ExpenseRepository()

    var isEditing: Bool { expense != nil }

    init(isPresented: Binding<Bool>, expense: Expense? = nil, openReceiptPicker: Bool = false, onSave: @escaping () -> Void) {
        self._isPresented = isPresented
        self.expense = expense
        self.onSave = onSave
        self.openReceiptPicker = openReceiptPicker

        if let expense = expense {
            _description = State(initialValue: expense.description)
            _amount = State(initialValue: String(format: "%.2f", expense.amount))
            _category = State(initialValue: expense.category)
            _merchant = State(initialValue: expense.merchant ?? "")
            _expenseDate = State(initialValue: expense.expenseDate)
            _selectedProjectId = State(initialValue: expense.projectId)
            _notes = State(initialValue: expense.notes ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if appState.hasCapability(.submitExpenses) {
                    Section("Receipt attachment") {
                        Button(receiptURL == nil ? "Choose Receipt" : "Replace Receipt") { pickingReceipt = true }.disabled(captureStarted || extractingReceipt).accessibilityIdentifier("expense.receipt.choose")
                        if receiptURL != nil {
                            Button("Preview selected receipt") {
                                do {
                                    if let url = receiptURL { let file = try ReceiptStorage.read(url: url); let ext = file.mime == "image/jpeg" ? "jpg" : url.pathExtension.lowercased(); originalPreviewURL = try PrivateDocument.write(file.data, extension: ext, prefix: "receipt") }
                                } catch { errorMessage = "Could not preview this receipt. Try selecting it again." }
                            }
                            .accessibilityIdentifier("expense.receipt.preview")
                            Button(extractingReceipt ? "Reading receipt…" : "Read receipt with AI") { extractReceipt() }.disabled(extractingReceipt || captureStarted)
                        }
                        Text("Extraction sends your selected receipt to OpenAI through Amountly. Check the amount, currency, date and category against the original. Your original attaches only when you save.").font(.caption)
                        if receiptSuggestionApplied { Toggle("I checked this draft and attachment against my receipt", isOn: $receiptConfirmed) }
                        if extractingReceipt { ProgressView(); Button("Cancel extraction") { receiptTask?.cancel(); extractingReceipt = false } }
                        if let preview = receiptPreview {
                            Text(preview.summary)
                            Text(preview.reason).font(.caption)
                            Text("\(preview.document_type.rawValue.capitalized) · Confidence: \(preview.confidence.rawValue)").font(.caption)
                            if preview.document_type == .receipt {
                                Text("\(preview.merchant) · \(preview.amount.isEmpty ? "Amount missing" : preview.amount) \(preview.currency) · \(preview.expense_date.isEmpty ? "Date missing" : preview.expense_date)")
                                Button("Apply receipt suggestion") { applyReceipt(preview) }
                            } else { Text("This document is not a purchase receipt. Enter the details manually; no expense fields were applied.") }
                            Button("Discard suggestion") { receiptPreview = nil }
                        }
                        Text("JPEG, PNG, WebP or PDF · up to 10 MB. Originals remain private.").font(.caption)
                    }
                }
                // Scan Receipt Button
                if !isEditing && ReceiptScanner.isAvailable {
                    Section {
                        Button(action: { showingScanner = true }) {
                            HStack {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 20))
                                    .foregroundColor(.alphaPrimary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scan Receipt")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text("Auto-fill expense details from a photo")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                AICaptureSection<AIExpense>(title: "Smart expense capture", text: $smartCaptureText, task: .expense, apply: applyExpense)
                AICaptureSection<AIReceipt>(title: "Receipt/document extraction", text: $receiptText, task: .receipt) { result in
                    applyExpense(result.expense)
                    if !result.notes.isEmpty { notes = result.notes }
                }

                // Description
                Section("Description") {
                    TextField("What was this expense for?", text: $description)
                        .accessibilityIdentifier("expense.description")
                }

                // Amount and Category
                Section("Details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        HStack(spacing: 4) {
                            Text(currency)
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                                .accessibilityIdentifier("expense.amount")
                        }
                    }

                    Picker("Currency", selection: $currency) { Text("Choose currency").tag(""); ForEach(RecordCoding.currencies, id: \.self) { Text($0) } }
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.iconName)
                                .tag(cat)
                        }
                    }

                    TextField("Merchant (optional)", text: $merchant)
                        .accessibilityIdentifier("expense.merchant")

                    if receiptDateMissing { Text("Receipt date is missing. Select the transaction date before saving.").foregroundStyle(.orange) }
                    DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                        .onChange(of: expenseDate) { _, _ in receiptDateMissing = false }
                    if receiptDateMissing { Button("Use selected date") { receiptDateMissing = false } }
                }

                // Project (optional)
                Section("Project (Optional)") {
                    if isLoadingProjects {
                        HStack {
                            Text("Loading projects...")
                                .foregroundColor(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Picker("Project", selection: $selectedProjectId) {
                            Text("No project").tag(nil as String?)
                            ForEach(projects) { project in
                                Text(project.name).tag(project.id as String?)
                            }
                        }
                    }
                }

                if let duplicate = possibleDuplicate {
                    Section("Possible duplicate") { Text("An expense for this merchant, amount, currency and date already exists: \(duplicate.description). Review before saving; this warning does not prevent saving.") }
                }
                // Notes
                Section("Notes (Optional)") {
                    TextField("Additional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
            }
            .disabled(captureStarted && !isEditing)
            .navigationTitle(isEditing ? "Edit Expense" : "New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        Task { await saveExpense() }
                    }
                    .accessibilityIdentifier("expense.save")
                    .disabled(description.isEmpty || amount.isEmpty || currency.isEmpty || receiptDateMissing || isSaving || extractingReceipt || (receiptSuggestionApplied && !receiptConfirmed))
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
            .task {
                if openReceiptPicker { pickingReceipt = true }
                currency = expense?.currency ?? appState.currentUser?.reportingCurrency ?? "USD"
                await loadProjects()
                savedExpenses = (try? await expenseRepository.fetchExpenses()) ?? []
            }
            .quickLookPreview($originalPreviewURL)
            .onDisappear { receiptTask?.cancel() }
            .onChange(of: originalPreviewURL) { previous, current in if previous != current, let url = previous { try? FileManager.default.removeItem(at: url) } }
            .onChange(of: appState.currentUser?.id) { _, _ in receiptTask?.cancel(); receiptPreview = nil; isPresented = false }
            .fileImporter(isPresented: $pickingReceipt, allowedContentTypes: [.jpeg, .png, .webP, .pdf]) { result in
                do { receiptTask?.cancel(); receiptPreview = nil; receiptURL = try result.get(); uploadedReceipt = nil; receiptConfirmed = false; if openReceiptPicker { extractReceipt() } } catch { errorMessage = "Could not select the receipt." }
            }
            .sheet(isPresented: $showingScanner) {
                ReceiptScannerView(onScanComplete: { receiptText = $0 }, onError: { errorMessage = $0 })
                .withAppTheme()
            }
        }
    }

    private var possibleDuplicate: Expense? {
        func normalized(_ value: String) -> String { value.precomposedStringWithCompatibilityMapping.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") }
        guard let value = Double(amount), value > 0, !normalized(merchant).isEmpty, !receiptDateMissing else { return nil }
        return savedExpenses.first { $0.id != expense?.id && RecordCoding.money($0.amount) == RecordCoding.money(value) && $0.currency == currency && RecordCoding.day($0.expenseDate) == RecordCoding.day(expenseDate) && normalized($0.merchant ?? "") == normalized(merchant) }
    }
    private func extractReceipt() {
        guard !extractingReceipt, let url = receiptURL else { return }
        receiptPreview = nil; errorMessage = nil; extractingReceipt = true; receiptConfirmed = false; receiptSuggestionApplied = false
        receiptTask = Task { @MainActor in
            defer { extractingReceipt = false }
            do { let result = try await ReceiptCaptureService.capture(url: url); try Task.checkCancellation(); receiptPreview = result }
            catch is CancellationError {} catch { if !Task.isCancelled { errorMessage = "Could not read this receipt. Try again or enter the details manually." } }
        }
    }
    private func applyReceipt(_ result: AIReceiptFile) {
        guard result.document_type == .receipt else { return }
        amount = result.amount; currency = result.supportedCurrency; merchant = result.merchant; description = result.description
        category = ExpenseCategory(rawValue: result.category.rawValue) ?? .other
        receiptDateMissing = AIValidation.date(result.expense_date) == nil
        if let date = AIValidation.date(result.expense_date) { expenseDate = date }
        receiptPreview = nil; receiptSuggestionApplied = true; receiptConfirmed = false
    }

    private func applyExpense(_ result: AIExpense) {
        if !result.amount.isEmpty { amount = result.amount }
        if !result.merchant.isEmpty { merchant = result.merchant }
        if !result.description.isEmpty { description = result.description }
        if let date = AIValidation.date(result.expense_date) { expenseDate = date }
        category = ExpenseCategory(rawValue: result.category.rawValue) ?? .other
    }

    private func loadProjects() async {
        isLoadingProjects = true
        do {
            projects = try await projectRepository.fetchProjects()
        } catch {
            projects = []
        }
        isLoadingProjects = false
    }

    private func saveExpense() async {
        guard !receiptDateMissing, (!receiptSuggestionApplied || receiptConfirmed), RecordCoding.currencies.contains(currency), let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            if let receiptURL, uploadedReceipt == nil { uploadedReceipt = try await ReceiptStorage().upload(url: receiptURL) }
            captureStarted = true
            if let existingExpense = expense {
                _ = try await expenseRepository.updateExpense(
                    id: existingExpense.id,
                    description: description,
                    amount: amountValue,
                    currency: currency,
                    category: category.rawValue,
                    merchant: merchant.isEmpty ? nil : merchant,
                    expenseDate: expenseDate,
                    projectId: selectedProjectId,
                    notes: notes.isEmpty ? nil : notes,
                    status: existingExpense.status.rawValue,
                    expectedVersion: existingExpense.version, receiptPath: uploadedReceipt
                )
            } else {
                _ = try await expenseRepository.createExpense(
                    description: description,
                    amount: amountValue,
                    currency: currency,
                    category: category.rawValue,
                    merchant: merchant.isEmpty ? nil : merchant,
                    expenseDate: expenseDate,
                    projectId: selectedProjectId,
                    notes: notes.isEmpty ? nil : notes,
                    status: "DRAFT", attempt: captureAttempt, receiptPath: uploadedReceipt
                )
            }

            onSave()
            isPresented = false
        } catch {
            errorMessage = "Failed to save expense: \(RecordError.safe(error).localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - Expense Detail Sheet

struct ExpenseDetailSheet: View {
    @State private var receiptDocument: ReceiptDocument?
    @State private var reviewConfirmation = false
    @State private var showingEdit = false
    private struct ReceiptDocument: Identifiable { let id = UUID(); let url: URL }
    let expense: Expense
    var onUpdate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var isUpdating = false
    @State private var errorMessage: String?

    private let expenseRepository = ExpenseRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if appState.currentUser?.accountType == .freelancer && appState.currentUser?.organizationId == nil && expense.userId == appState.currentUser?.id && [.draft, .rejected].contains(expense.status) {
                        Text(expense.reviewedAt == nil ? "Needs review" : "Reviewed").font(.headline)
                        Button(expense.reviewedAt == nil ? "Mark reviewed" : "Clear review") { reviewConfirmation = true }.disabled(isUpdating)
                        Text("Review the saved amount, currency, date, category and receipt. Editing the expense clears its review.").font(.caption)
                    }
                    if expense.userId == appState.currentUser?.id && [.draft, .rejected].contains(expense.status) { Button("Edit expense") { showingEdit = true } }
                    // Amount Header
                    VStack(spacing: 8) {
                        Text(expense.amountFormatted)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.primary)

                        ExpenseStatusBadge(status: expense.status)
                        if expense.reviewedAt != nil { Text("Reviewed").font(.caption2).foregroundStyle(.green) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))

                    // Details
                    VStack(spacing: 16) {
                        DetailRow(label: "Description", value: expense.description)
                        DetailRow(label: "Category", value: expense.category.displayName)

                        if let merchant = expense.merchant {
                            DetailRow(label: "Merchant", value: merchant)
                        }

                        DetailRow(label: "Date", value: expense.expenseDate.formatted(date: .abbreviated, time: .omitted))

                        if let project = expense.project {
                            DetailRow(label: "Project", value: project.name)
                        }

                        if let notes = expense.notes, !notes.isEmpty {
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

                        if expense.hasReceipt {
                            Button("Open Receipt") { Task {
                                do { let url = try await ReceiptStorage().signedURL(for: expense); receiptDocument = ReceiptDocument(url: url) }
                                catch { errorMessage = "Could not open the receipt. Check access and try again." }
                            } }
                            Divider()
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.blue)
                                Text("Receipt attached")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Action Buttons
                    VStack(spacing: 12) {
                        if expense.status == .draft && appState.currentUser?.accountType == .business {
                            Button(action: { Task { await submitExpense() } }) {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text("Submit for Approval")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }

                        if expense.status == .submitted && expense.userId != appState.currentUser?.id && appState.hasCapability(.approveExpenses) {
                            HStack(spacing: 12) {
                                Button(action: { Task { await rejectExpense() } }) {
                                    HStack {
                                        Image(systemName: "xmark")
                                        Text("Reject")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }

                                Button(action: { Task { await approveExpense() } }) {
                                    HStack {
                                        Image(systemName: "checkmark")
                                        Text("Approve")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                        }

                        if expense.status == .approved {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Approved")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }

                        if expense.status == .rejected {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Rejected")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
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
            .navigationTitle("Expense Details")
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
        }
        .sheet(item: $receiptDocument, onDismiss: { PrivateDocument.removeAll() }) { document in ShareSheet(activityItems: [document.url]) }
        .sheet(isPresented: $showingEdit) { ExpenseFormSheet(isPresented: $showingEdit, expense: expense) { onUpdate(); dismiss() } }
        .confirmationDialog(expense.reviewedAt == nil ? "Mark expense reviewed?" : "Clear expense review?", isPresented: $reviewConfirmation, titleVisibility: .visible) {
            Button("Confirm") { Task { await setReviewed() } }
        } message: { Text("Check the saved details and receipt. This action is recorded in the expense history.") }
    }
    private func setReviewed() async {
        guard !isUpdating else { return }; isUpdating = true; defer { isUpdating = false }
        do { try await expenseRepository.setReviewed(expense, reviewed: expense.reviewedAt == nil); onUpdate(); dismiss() }
        catch { errorMessage = RecordError.safe(error).localizedDescription }
    }



    private func submitExpense() async {
        isUpdating = true
        errorMessage = nil

        do {
            _ = try await expenseRepository.updateStatus(id: expense.id, status: "SUBMITTED", expectedVersion: expense.version)
            onUpdate()
            dismiss()
        } catch {
            errorMessage = "Failed to submit expense: \(RecordError.safe(error).localizedDescription)"
        }

        isUpdating = false
    }

    private func approveExpense() async {
        isUpdating = true
        errorMessage = nil

        do {
            _ = try await expenseRepository.updateStatus(id: expense.id, status: "APPROVED", expectedVersion: expense.version)
            onUpdate()
            dismiss()
        } catch {
            errorMessage = "Failed to approve expense: \(RecordError.safe(error).localizedDescription)"
        }

        isUpdating = false
    }

    private func rejectExpense() async {
        isUpdating = true
        errorMessage = nil

        do {
            _ = try await expenseRepository.updateStatus(id: expense.id, status: "REJECTED", expectedVersion: expense.version)
            onUpdate()
            dismiss()
        } catch {
            errorMessage = "Failed to reject expense: \(RecordError.safe(error).localizedDescription)"
        }

        isUpdating = false
    }
}

// MARK: - ExpenseViewContent (for embedding in BillingView)

struct ExpenseViewContent: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ExpenseViewModel()
    @State private var selectedExpense: Expense?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ExpenseWorkspaceSummary(expenses: viewModel.expenses)

                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExpenseFilter.allCases) { filter in
                            ExpenseFilterPill(
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

                ExpenseListFilters(viewModel: viewModel)
                // Expenses List
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if viewModel.filteredExpenses.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredExpenses) { expense in
                            ExpenseCardRow(expense: expense)
                                .onTapGesture {
                                    selectedExpense = expense
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.loadExpenses()
        }
        .task {
            await viewModel.loadExpenses()
        }
        .sheet(item: $selectedExpense) { expense in
            ExpenseDetailSheet(expense: expense, onUpdate: {
                Task { await viewModel.loadExpenses() }
            })
        }
    }

    private func countForFilter(_ filter: ExpenseFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.expenses.count
        case .needsReview: return viewModel.expenses.filter(\.needsReview).count
        case .reviewed: return viewModel.expenses.filter { $0.reviewedAt != nil }.count
        case .draft: return viewModel.expenses.filter { $0.status == .draft }.count
        case .reimbursed: return viewModel.expenses.filter { $0.status == .reimbursed }.count
        case .pending:
            return viewModel.expenses.filter { $0.status == .submitted }.count
        case .approved:
            return viewModel.expenses.filter { $0.status == .approved }.count
        case .rejected:
            return viewModel.expenses.filter { $0.status == .rejected }.count
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No expenses yet")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Add your first expense to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// Card-style row for expense content view
private struct ExpenseCardRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: expense.category.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(categoryColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.description)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let merchant = expense.merchant {
                        Text(merchant)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Text(expense.expenseDate, style: .date)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Amount and Status
            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.amountFormatted)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                ExpenseStatusBadge(status: expense.status)
                if expense.reviewedAt != nil { Text("Reviewed").font(.caption2).foregroundStyle(.green) }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var categoryColor: Color {
        switch expense.category {
        case .officeSupplies: return .blue
        case .travel: return .purple
        case .meals: return .orange
        case .software: return .cyan
        case .hardware: return .indigo
        case .marketing: return .pink
        case .utilities: return .yellow
        case .other: return .gray
        }
    }
}

// MARK: - Preview

#Preview("Expenses") {
    ExpenseView()
        .environmentObject({
            let state = AppState()
            state.isAuthenticated = true
            state.currentUser = .preview
            return state
        }())
}
