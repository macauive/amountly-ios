import SwiftUI

struct DashboardAI: View {
    let input: AIDashboardInput
    let currency: String
    let navigate: (FinancialSearchDestination) -> Void
    @State private var result: AIDashboard?
    @State private var error: String?
    @State private var loading = false
    @State private var retry = 0
    private var requestKey: Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(input)) ?? Data()
    }
    var body: some View {
        GroupBox("AI insights") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Suggestions from a bounded sample of loaded \(currency) records. Use the recorded totals above for accounting.").font(.caption).foregroundStyle(.secondary)
                if loading { ProgressView("Reviewing workspace…") }
                if let result {
                    Text(result.monthlySummary.headline).font(.headline)
                    Text(result.monthlySummary.body)
                    ForEach(Array(result.monthlySummary.highlights.enumerated()), id: \.offset) { _, value in Text("• " + value).font(.callout) }
                    if !result.nextSteps.isEmpty { Text("Suggested next steps").font(.headline) }
                    ForEach(Array(result.nextSteps.enumerated()), id: \.offset) { _, item in insight(item) }
                    if !input.searchQuery.isEmpty && !result.searchResults.isEmpty { Text("AI search results").font(.headline) }
                    ForEach(Array(result.searchResults.enumerated()), id: \.offset) { _, item in insight(item) }
                }
                if let error { Text(error).font(.caption); Button("Retry AI insights") { retry += 1 } }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .task(id: requestKey.base64EncodedString() + String(retry)) {
            result = nil; error = nil; loading = true
            do {
                // No paid request on each keystroke or intermediate data load.
                try await Task.sleep(for: .milliseconds(750))
                let value: AIDashboard = try await AIService.client.run(.dashboard, payload: input)
                try Task.checkCancellation()
                result = value; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = AIError.message(error); loading = false } }
        }
    }
    @ViewBuilder private func insight(_ item: AIInsight) -> some View {
        if input.candidateHrefs.contains(item.href) {
            Button {
                switch item.href {
                case .dashboard: break
                case .invoices: navigate(.invoices)
                case .bills: navigate(.bills)
                case .expenses: navigate(.expenses)
                case .time: navigate(.timeEntries)
                case .tax: navigate(.taxPrep)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.bold())
                    Text(item.detail).font(.caption)
                    Text(item.priority.rawValue.capitalized + " priority").font(.caption2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }
}

extension AIDashboardInput {
    // Meet the shared 12,000 UTF-16-character request budget without exposing
    // receipt paths, client addresses, user IDs, notes blobs, or nested records.
    static func summary(account: AccountType, query: String, currency: String, invoices: [Invoice], expenses: [Expense], bills: [Bill], vendorBills: [VendorBill], time: [TimeEntry], routes: [AIRoute]) -> AIDashboardInput {
        func label(_ text: String) -> String { String(text.prefix(160)) }
        let today = RecordCoding.day(Date())
        func billStatus(_ status: BillStatus, due: String) -> String {
            if status == .paid || status == .cancelled { return status.rawValue }
            return due < today ? "overdue" : due == today ? "due" : "upcoming"
        }
        let expenseRows = expenses.filter { $0.currency == currency }.prefix(100).map {
            AISummaryRecord(id: $0.id, label: label($0.merchant ?? $0.description), amount: $0.amount, date: RecordCoding.day($0.expenseDate), status: $0.status.rawValue, category: $0.category.rawValue, needsReceipt: !$0.hasReceipt)
        }
        var personalBills = bills.filter { $0.currency == currency }.prefix(100).map {
            AISummaryRecord(id: $0.id, label: label($0.name), amount: $0.amount, date: RecordCoding.day($0.dueDate), status: billStatus($0.status, due: RecordCoding.day($0.dueDate)))
        }
        var personalExpenses = account == .personal ? expenseRows : []
        var work = Work(invoices: invoices.filter { $0.currency == currency }.prefix(100).map {
            AISummaryRecord(id: $0.id, label: label($0.invoiceNumber), amount: $0.balanceDue, date: RecordCoding.day($0.dueDate), status: $0.isOverdue ? "OVERDUE" : $0.status.rawValue.uppercased())
        }, expenses: account == .personal ? [] : expenseRows,
            timeEntries: time.prefix(100).map { AISummaryRecord(id: $0.id, label: label($0.notes ?? "Time entry"), amount: nil, date: RecordCoding.day($0.startAt), status: $0.status.rawValue.uppercased()) },
            vendorBills: vendorBills.filter { ($0.currency ?? "USD") == currency }.prefix(100).map {
                AISummaryRecord(id: $0.id, label: label($0.bill_number), amount: $0.total, date: $0.due_date, status: $0.displayStatus.rawValue)
            })
        while true {
            let value = AIDashboardInput(accountType: account.rawValue, searchQuery: String(query.prefix(1000)), bills: personalBills, expenses: personalExpenses, workData: work, candidateHrefs: routes)
            let size = (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self).utf16.count } ?? Int.max
            if size <= 11000 { return value }
            let counts = [personalBills.count, personalExpenses.count, work.invoices.count, work.expenses.count, work.timeEntries.count, work.vendorBills.count]
            guard let largest = counts.max(), largest > 0, let index = counts.firstIndex(of: largest) else { return value }
            switch index {
            case 0: personalBills.removeLast()
            case 1: personalExpenses.removeLast()
            case 2: work.invoices.removeLast()
            case 3: work.expenses.removeLast()
            case 4: work.timeEntries.removeLast()
            default: work.vendorBills.removeLast()
            }
        }
    }
}
