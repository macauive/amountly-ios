import Foundation

enum FinancialRules {
    nonisolated static func canInvoiceTime(status: String, freelancer: Bool, isOwner: Bool, reserved: Bool, hasProject: Bool) -> Bool {
        guard !reserved, hasProject else { return false }
        return freelancer ? isOwner && ["DRAFT", "SUBMITTED", "APPROVED"].contains(status) : status == "APPROVED"
    }
    nonisolated static func cents(_ amount: Double) -> Double { (amount * 100).rounded() / 100 }
    nonisolated static func sum(_ amounts: [Double]) -> Double { amounts.reduce(0) { $0 + ($1 * 100).rounded() } / 100 }
    nonisolated static func period(year: Int, month: Int) -> (start: String, end: String)? {
        guard (2000...2100).contains(year), (1...12).contains(month) else { return nil }
        return (String(format: "%04d-%02d-01", year, month), String(format: "%04d-%02d-01", year + 1, month))
    }
    nonisolated static func csvCell(_ value: String) -> String {
        // Prefix text that spreadsheet applications could execute as a formula.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = ["=", "+", "-", "@", "\t", "\r", "\n"].contains { value.hasPrefix($0) || trimmed.hasPrefix($0) } ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    nonisolated static func federalTax(income: Double, year: Int) -> Double? {
        guard income.isFinite, let config = taxYears[year] else { return nil }
        let taxable = max(0, income - config.deduction)
        var previous = 0.0, total = 0.0
        for (limit, rate) in zip(config.limits, [0.10,0.12,0.22,0.24,0.32,0.35,0.37]) {
            total += max(0, min(taxable, limit) - previous) * rate
            previous = limit
        }
        return total
    }
    nonisolated static func selfEmploymentTax(netEarnings: Double, year: Int) -> Double? {
        guard netEarnings.isFinite, let config = taxYears[year] else { return nil }
        return netEarnings < 400 ? 0 : min(netEarnings, config.ssBase) * 0.124 + netEarnings * 0.029
    }
    nonisolated static let taxYears: [Int: (deduction: Double, ssBase: Double, limits: [Double])] = [
        2025: (15750, 176100, [11925,48475,103350,197300,250525,626350,.infinity]),
        2026: (16100, 184500, [12400,50400,105700,201775,256225,640600,.infinity])
    ]
}
