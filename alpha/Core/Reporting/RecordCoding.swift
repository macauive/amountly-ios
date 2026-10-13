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
            let calendarText = calendarFields.contains(value.codingPath.last?.stringValue ?? "") ? calendarDay(text) : text
            guard let date = parseDate(calendarText) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid record date")
            }
            return date
        }
        return decoder
    }
    // Financial commands store UTC midnight. Normalize offset timestamps before
    // constructing a local calendar date for DatePicker and financial periods.
    nonisolated static func calendarDay(_ text: String) -> String {
        guard text.count != 10, let instant = parseDate(text) else { return text }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: instant)
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
