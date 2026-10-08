import Foundation

nonisolated struct AIReceiptFile: Decodable, Sendable {
    enum DocumentType: String, Decodable, Sendable { case receipt, invoice, statement, other }
    static let fields: Set<String> = ["document_type", "amount", "currency", "merchant", "description", "expense_date", "category", "confidence", "reason", "summary"]
    let document_type: DocumentType
    let amount: String, currency: String, merchant: String, description: String, expense_date: String
    let category: AICategory, confidence: AIConfidence
    let reason: String, summary: String
    static func decode(_ data: Data) throws -> AIReceiptFile {
        do {
            guard data.count <= 128000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == ["result"],
                  let result = object["result"] as? [String: Any], Set(result.keys) == fields else { throw AIError.response }
            let value = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: result))
            try AIValidation.require(value.amount.isEmpty || value.amount.range(of: #"^[0-9]{1,8}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil)
            try AIValidation.require(["", "USD", "EUR", "GBP", "CAD", "AUD", "OTHER"].contains(value.currency))
            try AIValidation.require(value.expense_date.isEmpty || AIValidation.date(value.expense_date) != nil)
            try AIValidation.require(value.merchant.count <= 200 && [value.description, value.reason, value.summary].allSatisfy { $0.count <= 1000 })
            try AIValidation.text(value.merchant, value.description, value.reason, value.summary)
            return value
        } catch { throw AIError.response }
    }
    var supportedCurrency: String { ["USD", "EUR", "GBP", "CAD", "AUD"].contains(currency) ? currency : "" }
}
