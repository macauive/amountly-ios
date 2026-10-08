import SwiftUI

struct ExpenseListFilters: View {
    @ObservedObject var viewModel: ExpenseViewModel
    var body: some View {
        DisclosureGroup("Search and filter expenses") {
            VStack(spacing: 12) {
                TextField("Search merchant or description", text: $viewModel.searchText).textFieldStyle(.roundedBorder)
                Picker("Category", selection: $viewModel.categoryFilter) {
                    Text("All categories").tag("all")
                    ForEach(ExpenseCategory.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                HStack {
                    TextField("From YYYY-MM-DD", text: $viewModel.startFilter)
                    TextField("Through YYYY-MM-DD", text: $viewModel.endFilter)
                }.textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                if (!viewModel.startFilter.isEmpty && AIValidation.date(viewModel.startFilter) == nil) || (!viewModel.endFilter.isEmpty && AIValidation.date(viewModel.endFilter) == nil) || (!viewModel.startFilter.isEmpty && !viewModel.endFilter.isEmpty && viewModel.startFilter > viewModel.endFilter) {
                    Text("Enter valid dates with From on or before Through.").foregroundStyle(.red).font(.caption)
                }
                Button("Clear filters") { viewModel.searchText = ""; viewModel.categoryFilter = "all"; viewModel.startFilter = ""; viewModel.endFilter = ""; viewModel.selectedFilter = .all }
            }
        }.padding(.horizontal)
    }
}

struct ExpenseWorkspaceSummary: View {
    let expenses: [Expense]
    @EnvironmentObject private var appState: AppState
    private var currencies: [String] { Array(Set(expenses.map(\.currency))).sorted() }
    private var solo: Bool { appState.currentUser?.accountType == .freelancer }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabeledContent("Expenses", value: String(expenses.count))
                Spacer()
                Text("\(solo ? expenses.filter(\.needsReview).count : expenses.filter { $0.status == .submitted }.count) \(solo ? "need review" : "submitted")")
            }
            ForEach(currencies, id: \.self) { currency in
                LabeledContent(currency, value: FinancialRules.sum(expenses.filter { $0.currency == currency }.map(\.amount)).formatted(.currency(code: currency)))
            }
            Text("Summary totals include all loaded expenses. Currencies remain separate.").font(.caption).foregroundStyle(.secondary)
        }.padding().background(Color.alphaCardBackground, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
    }
}
