import Foundation
import Testing
@testable import AmountlyRules

@Test func moneyUsesCents() {
    #expect(FinancialRules.sum([0.1, 0.2]) == 0.3)
    #expect(FinancialRules.sum([10.005, 0.005]) == 10.02)
    #expect(FinancialRules.cents(100 - 33.33) == 66.67)
}
@Test func fiscalPeriodsValidateBounds() {
    #expect(FinancialRules.period(year: 2026, month: 4)?.start == "2026-04-01")
    #expect(FinancialRules.period(year: 2026, month: 4)?.end == "2027-04-01")
    #expect(FinancialRules.period(year: 2026, month: 13) == nil)
    #expect(FinancialRules.period(year: 1999, month: 1) == nil)
}
@Test func exportsNeutralizeSpreadsheetFormulas() {
    for value in ["=1+1", " +SUM(A1)", "@SUM(A1)", "-2+3", "\tformula", "\n=1+1"] {
        #expect(FinancialRules.csvCell(value).hasPrefix("\"'"))
    }
    #expect(FinancialRules.csvCell("Client, \"A\"") == "\"Client, \"\"A\"\"\"")
}
@Test func estimatesMatchWebSupportedYears() {
    #expect(FinancialRules.federalTax(income: 16100, year: 2026) == 0)
    #expect(FinancialRules.federalTax(income: 28500, year: 2026) == 1240)
    #expect(FinancialRules.federalTax(income: 16100, year: 2027) == nil)
    #expect(FinancialRules.selfEmploymentTax(netEarnings: 399, year: 2026) == 0)
    #expect(FinancialRules.selfEmploymentTax(netEarnings: 400, year: 2026) == 61.2)
    #expect(FinancialRules.selfEmploymentTax(netEarnings: .infinity, year: 2026) == nil)
}

@Test func datesAcceptPostgresFormatsAndRejectInvalidInput() throws {
    #expect(RecordCoding.parseDate("2026-09-26T01:02:03.123456+00:00") != nil)
    #expect(RecordCoding.parseDate("2026-09-26T01:02:03Z") != nil)
    #expect(RecordCoding.parseDate("2026-02-30") == nil)
    struct Row: Decodable { let expense_date: Date; let updated_at: Date }
    let data = Data(#"{"expense_date":"2026-09-26T00:00:00+00:00","updated_at":"2026-09-26T01:02:03.123456+00:00"}"#.utf8)
    let row = try RecordCoding.decoder().decode(Row.self, from: data)
    #expect(RecordCoding.day(row.expense_date) == "2026-09-26")
    #expect(row.updated_at != row.expense_date)
}

@Test func timeBillingRespectsOwnershipApprovalAndReservations() {
    #expect(FinancialRules.canInvoiceTime(status: "DRAFT", freelancer: true, isOwner: true, reserved: false, hasProject: true))
    #expect(!FinancialRules.canInvoiceTime(status: "DRAFT", freelancer: false, isOwner: true, reserved: false, hasProject: true))
    #expect(!FinancialRules.canInvoiceTime(status: "APPROVED", freelancer: true, isOwner: false, reserved: false, hasProject: true))
    #expect(FinancialRules.canInvoiceTime(status: "APPROVED", freelancer: false, isOwner: false, reserved: false, hasProject: true))
    #expect(!FinancialRules.canInvoiceTime(status: "APPROVED", freelancer: true, isOwner: true, reserved: true, hasProject: true))
    #expect(!FinancialRules.canInvoiceTime(status: "APPROVED", freelancer: true, isOwner: true, reserved: false, hasProject: false))
    #expect(!FinancialRules.canInvoiceTime(status: "REJECTED", freelancer: true, isOwner: true, reserved: false, hasProject: true))
}

@Test func receiptUploadsRequireAllowedMatchingTypeAndBoundedSize() {
    let pdf = Data("%PDF-1.7 sample".utf8)
    #expect(ReceiptRules.mimeType(extension: "pdf", data: pdf) == "application/pdf")
    #expect(ReceiptRules.mimeType(extension: "jpg", data: pdf) == nil)
    #expect(ReceiptRules.mimeType(extension: "html", data: Data("<script>".utf8)) == nil)
    #expect(ReceiptRules.mimeType(extension: "pdf", data: Data()) == nil)
    #expect(ReceiptRules.mimeType(extension: "pdf", data: pdf + Data(repeating: 0, count: ReceiptRules.maxBytes)) == nil)
    #expect(ReceiptRules.mimeType(extension: "PNG", data: Data([137,80,78,71,13,10,26,10])) == "image/png")
}
