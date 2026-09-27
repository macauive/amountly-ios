import Foundation

// Shared wire format: SQL dates are calendar days; timestamps are UTC instants.
enum RecordCoding {
    nonisolated static func parseDate(_ text: String) -> Date? {
        if text.count == 10 {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            return formatter.date(from: text)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let text = try container.decode(String.self)
            let calendarFields = ["issue_date", "due_date", "expense_date", "paid_on", "date", "expected_date", "filed_date"]
            let calendarText = calendarFields.contains(value.codingPath.last?.stringValue ?? "") ? String(text.prefix(10)) : text
            guard let date = parseDate(calendarText) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid record date")
            }
            return date
        }
        return decoder
    }
    nonisolated static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    nonisolated static func money(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    nonisolated static let currencies = ["USD", "EUR", "GBP", "CAD", "AUD"]
}
