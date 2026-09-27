//
//  TaxRepository.swift
//  alpha
//
//  Created by Claude Code on 2/1/26.
//

import Foundation
import Supabase

class TaxRepository {
    private let supabase = SupabaseClientManager.shared.client
    private let ownershipResolver = OwnershipResolver()
    private let expenseRepository = ExpenseRepository()
    private let invoiceRepository = InvoiceRepository()

    func fetchTaxFilings() async throws -> [TaxFiling] {
        let scope = try await ownershipResolver.currentScope()
        var rows: [TaxFiling] = []
        while true {
            let response = try await supabase.from("tax_filings").select().eq("user_id", value: scope.userId).order("due_date").order("id").range(from: rows.count, to: rows.count + 199).execute()
            let batch = try RecordCoding.decoder().decode([TaxFilingRowDTO].self, from: response.data)
            rows += batch.map { $0.taxFiling }
            if batch.count < 200 { return rows }
        }
    }
}

private struct TaxFilingRowDTO: Decodable {
    let id: String
    let name: String
    let formType: String
    let taxPeriodStart: String?
    let taxPeriodEnd: String?
    let dueDate: String
    let filedDate: String?
    let status: FilingStatus
    let amountDue: Double?
    let amountPaid: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case formType = "form_type"
        case taxPeriodStart = "tax_period_start"
        case taxPeriodEnd = "tax_period_end"
        case dueDate = "due_date"
        case filedDate = "filed_date"
        case status
        case amountDue = "amount_due"
        case amountPaid = "amount_paid"
        case notes
    }

    var taxFiling: TaxFiling {
        let due = Self.parseDate(dueDate) ?? Date()
        let filed = filedDate.flatMap(Self.parseDate) ?? due
        return TaxFiling(
            id: id,
            type: Self.deadlineType(formType: formType, name: name),
            filingDate: filed,
            taxYear: Calendar.current.component(.year, from: due),
            status: status,
            amount: amountDue ?? amountPaid,
            name: name,
            formType: formType,
            dueDate: due,
            taxPeriodStart: taxPeriodStart.flatMap(Self.parseDate),
            taxPeriodEnd: taxPeriodEnd.flatMap(Self.parseDate),
            notes: notes
        )
    }

    nonisolated private static func parseDate(_ value: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if let date = dateFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }

    nonisolated private static func deadlineType(formType: String, name: String) -> TaxDeadlineType {
        let normalized = "\(formType) \(name)".lowercased()

        if normalized.contains("1099") {
            return .estimated1099
        }

        if normalized.contains("sales") {
            return .salesTax
        }

        if normalized.contains("payroll") {
            return .payrollTax
        }

        if normalized.contains("1040-es") || normalized.contains("estimate") || normalized.contains("quarter") {
            return .quarterlyEstimate
        }

        return .annualReturn
    }
}
