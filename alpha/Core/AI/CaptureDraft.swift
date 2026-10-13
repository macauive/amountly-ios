import Foundation

nonisolated struct CaptureFields: Codable, Sendable {
    var amount = "", currency = "", category: AICategory = .other
    var description = "", merchant = "", expense_date = "", project_id = "", notes = ""
    func validate() throws {
        try AIValidation.require(amount.isEmpty || amount.range(of: #"^\d{0,8}(?:\.\d{0,2})?$"#, options: .regularExpression) != nil)
        try AIValidation.require(["", "USD", "EUR", "GBP", "CAD", "AUD"].contains(currency))
        try AIValidation.require(description.utf16.count <= 1000 && merchant.utf16.count <= 200 && notes.utf16.count <= 4000)
        try AIValidation.require(expense_date.isEmpty || AIValidation.date(expense_date) != nil)
        try AIValidation.require(project_id.isEmpty || UUID(uuidString: project_id) != nil)
    }
}
nonisolated enum CaptureMethod: String, Codable, CaseIterable, Sendable { case file, text, manual }
nonisolated struct CapturePayload: Codable, Sendable {
    var method: CaptureMethod
    var fields: CaptureFields
    var text: String
    var extraction: AIReceiptFile?
    var extracted: Bool
    enum CodingKeys: String, CodingKey { case method, fields, text, extraction, extracted }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(method, forKey: .method); try values.encode(fields, forKey: .fields)
        try values.encode(text, forKey: .text); try values.encode(extraction, forKey: .extraction)
        try values.encode(extracted, forKey: .extracted)
    }
    func validate() throws {
        try fields.validate()
        try AIValidation.require(text.utf16.count <= 12000)
        if let extraction {
            _ = try AIReceiptFile.decode(JSONSerialization.data(withJSONObject: ["result": JSONSerialization.jsonObject(with: JSONEncoder().encode(extraction))]))
        }
    }
}
nonisolated struct CaptureDraft: Codable, Identifiable, Sendable {
    let id: UUID
    let revision: Int
    let updated_at: String
    let payload: CapturePayload
    let file_name: String?
    let content_type: String?
    static func decode(_ data: Data) throws -> CaptureDraft {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let row = object as? [String: Any], Set(row.keys) == ["id", "revision", "updated_at", "payload", "file_name", "content_type"],
              let payload = row["payload"] as? [String: Any], Set(payload.keys) == ["method", "fields", "text", "extraction", "extracted"],
              let fields = payload["fields"] as? [String: Any], Set(fields.keys) == ["amount", "currency", "category", "description", "merchant", "expense_date", "project_id", "notes"] else { throw AIError.response }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.payload.validate()
        try AIValidation.require((1...2147483647).contains(value.revision))
        try AIValidation.require(ISO8601DateFormatter().date(from: value.updated_at) != nil || validTimestamp(value.updated_at, revision: value.revision))
        try AIValidation.require((value.file_name == nil) == (value.content_type == nil))
        try AIValidation.require(value.file_name.map { !$0.isEmpty && $0.utf16.count <= 200 } ?? true)
        try AIValidation.require(value.content_type.map { ["image/jpeg", "image/png", "image/webp", "application/pdf"].contains($0) } ?? true)
        return value
    }
    private static func validTimestamp(_ text: String, revision: Int) -> Bool {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (1...2147483647).contains(revision) && f.date(from: text) != nil
    }
}
