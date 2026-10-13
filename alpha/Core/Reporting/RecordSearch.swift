import Foundation

enum RecordKind: String, CaseIterable { case expenses, invoices, bills, vendorBills = "vendor_bills" }
struct SearchRecord: Identifiable {
    let recordID: String
    let kind: RecordKind
    let label: String, detail: String, currency: String, date: String, status: String
    let amount: Double
    let receipt: Bool
    var id: String { "\(kind.rawValue):\(recordID)" }
    func validate() throws {
        guard UUID(uuidString: recordID) != nil, amount.isFinite, label.utf16.count <= 1000,
              detail.utf16.count <= 4000, (1...8).contains(currency.utf16.count), RecordCoding.parseDate(date) != nil,
              date.count == 10, RecordFilters.statuses.contains(status) else { throw RecordSearchError.invalid }
    }
}
enum RecordSearchError: Error { case invalid }
struct RecordFilters {
    var query = "", start = "", end = "", kind = "all", status = "all", receipt = "all"
    static let statuses = ["DRAFT", "SUBMITTED", "APPROVED", "REJECTED", "REIMBURSED", "SENT", "PAID", "OVERDUE", "CANCELLED", "upcoming", "due", "paid", "overdue", "cancelled"]
    static func statusLabel(_ status: String) -> String { status == status.lowercased() ? "Bill: \(status.capitalized)" : status.capitalized }
    var valid: Bool {
        query.utf16.count <= 100 && (start.isEmpty || (start.count == 10 && RecordCoding.parseDate(start) != nil))
            && (end.isEmpty || (end.count == 10 && RecordCoding.parseDate(end) != nil))
            && (start.isEmpty || end.isEmpty || start <= end)
            && (["all"] + RecordKind.allCases.map(\.rawValue)).contains(kind)
            && (["all"] + Self.statuses).contains(status) && ["all", "attached", "missing"].contains(receipt)
    }
    private func normalized(_ value: String) -> String { value.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "en_US")) }
    func apply(_ rows: [SearchRecord]) -> [SearchRecord] {
        guard valid else { return [] }
        let query = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = query.split(whereSeparator: \.isWhitespace)
        return rows.filter { row in
            let text = normalized("\(row.label) \(row.detail) \(String(format: "%.2f", row.amount)) \(Self.statusLabel(row.status)) \(row.kind.rawValue.replacingOccurrences(of: "_", with: " ")) \(row.date)")
            return terms.allSatisfy { text.contains($0) } && (kind == "all" || row.kind.rawValue == kind)
                && (start.isEmpty || row.date >= start) && (end.isEmpty || row.date <= end)
                && (status == "all" || row.status == status)
                && (receipt == "all" || (row.kind == .expenses && row.receipt == (receipt == "attached")))
        }.sorted { left, right in
            let a = !query.isEmpty && normalized(left.label) == query, b = !query.isEmpty && normalized(right.label) == query
            if a != b { return a }
            return left.date == right.date ? left.id < right.id : left.date > right.date
        }
    }
}
