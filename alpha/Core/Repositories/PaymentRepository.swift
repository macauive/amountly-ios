import Foundation
import Supabase

final class PaymentRepository {
    func record(invoice: Invoice, amount: Double, method: String, reference: String, date: Date, attempt: RecordAttempt) async throws {
        guard [.sent, .overdue].contains(invoice.status), amount.isFinite, amount > 0,
              amount <= invoice.balanceDue, RecordCoding.money(amount) == amount,
              ["bank_transfer", "card", "cash", "check", "other"].contains(method), reference.count <= 500,
              RecordCoding.day(date) <= RecordCoding.day(Date()) else { throw RecordError.invalid }
        try await attempt.perform("record_invoice_payment", params: ["p_id": .string(attempt.id), "p_invoice_id": .string(invoice.id), "p_amount": .double(amount), "p_paid_on": .string(RecordCoding.day(date)), "p_method": .string(method), "p_reference": .string(reference)])
    }
    func reverse(payment: InvoicePayment, reason: String, attempt: RecordAttempt) async throws {
        guard !payment.isReversed, (5...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count) else { throw RecordError.invalid }
        try await attempt.perform("reverse_invoice_payment", params: ["p_id": .string(attempt.id), "p_payment_id": .string(payment.id), "p_reason": .string(reason)])
    }
}
