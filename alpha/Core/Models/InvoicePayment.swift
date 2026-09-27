import Foundation

struct InvoicePayment: Codable, Identifiable {
    let id: String
    let invoice_id: String
    let amount: Double
    let paid_on: Date
    let method: String
    let reference: String?
    let created_at: Date?
    let reversal: [PaymentReversal]?
    var isReversed: Bool { !(reversal ?? []).isEmpty }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        invoice_id = try c.decode(String.self, forKey: .invoice_id)
        amount = try c.decode(Double.self, forKey: .amount)
        paid_on = try c.decode(Date.self, forKey: .paid_on)
        method = try c.decode(String.self, forKey: .method)
        reference = try c.decodeIfPresent(String.self, forKey: .reference)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
        if let rows = try? c.decode([PaymentReversal].self, forKey: .reversal) { reversal = rows }
        else if let row = try c.decodeIfPresent(PaymentReversal.self, forKey: .reversal) { reversal = [row] }
        else { reversal = [] }
    }
}
struct PaymentReversal: Codable { let id: String; let reason: String? }
struct InvoiceSnapshot: Codable { let client: InvoiceSnapshotClient?; let lines: [InvoiceLineItem]? }
struct InvoiceSnapshotClient: Codable { let name: String?; let email: String?; let address: String? }
