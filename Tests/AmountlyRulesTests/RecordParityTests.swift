import Foundation
import Testing
@testable import AmountlyRules

@Test func offsetFinancialDaysKeepUTCYearAndDatePickerRoundTrip() throws {
    struct Row: Decodable { let expense_date: Date; let issue_date: Date; let paid_on: Date; let updated_at: Date }
    for (wire, expected) in [("2026-10-11T19:00:00-05:00", "2026-10-12"), ("2025-12-31T19:00:00-05:00", "2026-01-01"), ("2026-10-12T05:00:00+05:00", "2026-10-12")] {
        let data = try JSONSerialization.data(withJSONObject: ["expense_date":wire,"issue_date":wire,"paid_on":wire,"updated_at":wire])
        let row = try RecordCoding.decoder().decode(Row.self, from: data)
        #expect(RecordCoding.day(row.expense_date) == expected)
        #expect(RecordCoding.day(row.issue_date) == expected)
        #expect(RecordCoding.day(row.paid_on) == expected)
        #expect(row.updated_at == RecordCoding.parseDate(wire))
    }
}
@Test func recordSearchMatchesAllTermsAmountsAndExactTitlesFirst() {
    let a = SearchRecord(recordID: "00000000-0000-4000-8000-000000000001", kind: .expenses, label: "Paper", detail: "Office purchase", currency: "USD", date: "2026-10-12", status: "DRAFT", amount: 12.50, receipt: true)
    let b = SearchRecord(recordID: "00000000-0000-4000-8000-000000000002", kind: .invoices, label: "Paper billing", detail: "Office", currency: "EUR", date: "2026-10-13", status: "SENT", amount: 20, receipt: false)
    #expect(RecordFilters(query: "Paper").apply([b,a]).map(\.id) == [a.id,b.id])
    #expect(RecordFilters(query: "office 12.50").apply([b,a]).map(\.id) == [a.id])
    #expect(RecordFilters(query: "missing").apply([a,b]).isEmpty)
    #expect(RecordFilters(start: "2026-10-12", end: "2026-10-12", receipt: "attached").apply([a,b]).map(\.id) == [a.id])
    #expect(RecordFilters(query: "Ｐａｐｅｒ").apply([a]).count == 1)
    #expect(RecordFilters(query: "Paper").apply([a,b])[1].currency == "EUR")
    let bill = SearchRecord(recordID: "00000000-0000-4000-8000-000000000003", kind: .bills, label: "Synthetic loan", detail: "", currency: "CAD", date: "2026-10-12", status: "paid", amount: 10, receipt: false)
    #expect(RecordFilters(query: "Bill: Paid").apply([bill,a,b]).map(\.id) == [bill.id])
}
@Test func malformedRecordFiltersFailClosed() {
    for filter in [RecordFilters(query: String(repeating: "x", count: 101)), RecordFilters(start: "2026-02-30"), RecordFilters(start: "2026-12-31", end: "2026-01-01"), RecordFilters(kind: "users"), RecordFilters(status: "unknown"), RecordFilters(receipt: "anything")] { #expect(!filter.valid) }
}
