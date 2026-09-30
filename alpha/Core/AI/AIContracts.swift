import Foundation

nonisolated enum AITask: String, Sendable {
    case expense = "expense_capture", receipt = "receipt_capture", line = "invoice_line"
    case reminder = "invoice_reminder", time = "time_entry", contact = "contact_capture"
    case dashboard = "dashboard_insights"
}

nonisolated enum AIError: Error, LocalizedError, Equatable {
    case input, response, signIn, denied, limit, unavailable, network
    var errorDescription: String? {
        switch self {
        case .input: return "Check the input. Use up to 12,000 characters and valid amounts and dates."
        case .response: return "AI returned an incomplete or invalid suggestion. Please try again."
        case .signIn: return "Sign in again to use AI."
        case .denied: return "AI is unavailable for this account."
        case .limit: return "AI usage limit reached. Please try again later."
        case .unavailable: return "AI is temporarily unavailable. Your form has not changed."
        case .network: return "Could not reach AI. Check your connection and try again."
        }
    }
    static func message(_ error: Error) -> String { (error as? AIError ?? .network).localizedDescription }
}

nonisolated protocol AIResult: Decodable, Sendable {
    static var fields: Set<String> { get }
    func validate() throws
    var preview: [String] { get }
}

nonisolated enum AIValidation {
    static func require(_ value: Bool) throws { if !value { throw AIError.response } }
    static func text(_ values: String...) throws {
        try require(values.allSatisfy { $0.utf16.count <= 2000 && !$0.unicodeScalars.contains(where: { $0.value == 0 }) })
    }
    static func money(_ value: Double) -> Bool { value.isFinite && (0...99_999_999.99).contains(value) }
    static func date(_ text: String) -> Date? {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let date = f.date(from: text), f.string(from: date) == text else { return nil }
        return date
    }
    static func clockMinutes(_ text: String) -> Int? {
        guard text.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return nil }
        let p = text.split(separator: ":"); return Int(p[0])! * 60 + Int(p[1])!
    }
    static func decode<R: AIResult>(_ type: R.Type, data: Data) throws -> R {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["result", "safety"],
                  let result = object["result"] as? [String: Any], Set(result.keys) == R.fields,
                  let safety = object["safety"] as? [String: Any], Set(safety.keys) == ["redacted"],
                  safety["redacted"] is Bool else { throw AIError.response }
            if R.self == AIDashboard.self {
                guard let steps = result["nextSteps"] as? [[String: Any]], let search = result["searchResults"] as? [[String: Any]],
                      let summary = result["monthlySummary"] as? [String: Any], Set(summary.keys) == ["headline", "body", "highlights"],
                      steps.allSatisfy({ Set($0.keys) == ["id", "title", "detail", "href", "priority"] }),
                      search.allSatisfy({ Set($0.keys) == ["id", "title", "detail", "href", "priority", "label"] }) else { throw AIError.response }
            }
            let value = try JSONDecoder().decode(R.self, from: JSONSerialization.data(withJSONObject: result))
            try value.validate()
            return value
        } catch { throw AIError.response }
    }
}

nonisolated enum AIConfidence: String, Decodable, Sendable { case high, medium, low }
nonisolated enum AICategory: String, Decodable, Sendable {
    case office = "OFFICE_SUPPLIES", travel = "TRAVEL", meals = "MEALS", software = "SOFTWARE"
    case hardware = "HARDWARE", marketing = "MARKETING", utilities = "UTILITIES", other = "OTHER"
}
nonisolated struct AIExpense: AIResult {
    static let fields: Set<String> = ["amount", "merchant", "description", "expense_date", "category", "confidence", "reason"]
    let amount: String, merchant: String, description: String, expense_date: String
    let category: AICategory, confidence: AIConfidence
    let reason: String
    func validate() throws {
        try AIValidation.text(merchant, description, reason)
        try AIValidation.require(amount.isEmpty || amount.range(of: #"^\d{1,8}(\.\d{1,2})?$"#, options: .regularExpression) != nil)
        try AIValidation.require(expense_date.isEmpty || AIValidation.date(expense_date) != nil)
    }
    var preview: [String] { [merchant, description, amount.isEmpty ? "Amount not found" : "Amount: \(amount)", expense_date, category.rawValue.replacingOccurrences(of: "_", with: " "), "Confidence: \(confidence.rawValue)", reason].filter { !$0.isEmpty } }
}
nonisolated struct AIReceipt: AIResult {
    static let fields = AIExpense.fields.union(["notes", "summary"])
    let amount: String, merchant: String, description: String, expense_date: String
    let category: AICategory, confidence: AIConfidence
    let reason: String, notes: String, summary: String
    var expense: AIExpense { AIExpense(amount: amount, merchant: merchant, description: description, expense_date: expense_date, category: category, confidence: confidence, reason: reason) }
    func validate() throws { try expense.validate(); try AIValidation.text(notes, summary) }
    var preview: [String] { expense.preview + [notes, summary].filter { !$0.isEmpty } }
}
nonisolated struct AILine: AIResult {
    static let fields: Set<String> = ["description", "quantity", "rate", "amount", "reason"]
    let description: String, quantity: Double, rate: Double, amount: Double, reason: String
    func validate() throws {
        try AIValidation.text(description, reason)
        try AIValidation.require([quantity, rate, amount].allSatisfy(AIValidation.money))
        try AIValidation.require(abs(amount - (quantity * rate * 100).rounded() / 100) < 0.005)
    }
    var preview: [String] { [description, "\(quantity.formatted()) × \(rate.formatted()) = \(amount.formatted())", reason] }
}
nonisolated struct AIContact: AIResult {
    static let fields: Set<String> = ["name", "contact_name", "email", "phone", "address", "city", "state", "zip_code", "notes", "reason"]
    let name: String, contact_name: String, email: String, phone: String, address: String
    let city: String, state: String, zip_code: String, notes: String, reason: String
    func validate() throws { try AIValidation.text(name, contact_name, email, phone, address, city, state, zip_code, notes, reason) }
    var preview: [String] { ["Company: \(name)", "Contact: \(contact_name)", email, phone, address, "\(city), \(state) \(zip_code)", notes, reason].filter { !$0.isEmpty } }
}
nonisolated struct AITime: AIResult {
    static let fields: Set<String> = ["date", "start_time", "end_time", "notes", "duration_minutes", "reason"]
    let date: String, start_time: String, end_time: String, notes: String, duration_minutes: Int, reason: String
    func validate() throws {
        try AIValidation.text(notes, reason)
        try AIValidation.require(date.isEmpty || AIValidation.date(date) != nil)
        try AIValidation.require((0...1440).contains(duration_minutes))
        try AIValidation.require(start_time.isEmpty || AIValidation.clockMinutes(start_time) != nil)
        try AIValidation.require(end_time.isEmpty || AIValidation.clockMinutes(end_time) != nil)
        if let start = AIValidation.clockMinutes(start_time), let end = AIValidation.clockMinutes(end_time) {
            try AIValidation.require(end > start && (duration_minutes == 0 || duration_minutes == end - start))
        }
    }
    var minutes: Int {
        if let start = AIValidation.clockMinutes(start_time), let end = AIValidation.clockMinutes(end_time) { return end - start }
        return duration_minutes
    }
    // Missing time-of-day remains a visible estimate; never invent a duration.
    func interval(referenceDate: Date, calendar: Calendar = .current) -> (Date, Date)? {
        guard minutes > 0 else { return nil }
        let day = AIValidation.date(date) ?? referenceDate
        func clock(_ value: Int) -> Date? {
            calendar.date(bySettingHour: value / 60, minute: value % 60, second: 0, of: day)
        }
        if let startMinute = AIValidation.clockMinutes(start_time), let start = clock(startMinute) {
            let end = AIValidation.clockMinutes(end_time).flatMap(clock) ?? start.addingTimeInterval(Double(minutes * 60))
            return end > start ? (start, end) : nil
        }
        if let endMinute = AIValidation.clockMinutes(end_time), let end = clock(endMinute) {
            return (end.addingTimeInterval(-Double(minutes * 60)), end)
        }
        guard let start = clock(540) else { return nil }
        return (start, start.addingTimeInterval(Double(minutes * 60)))
    }
    var preview: [String] { [date, "\(minutes) minutes", start_time.isEmpty ? "Start time not supplied; review the estimated time block." : "Start: \(start_time)", end_time.isEmpty ? "" : "End: \(end_time)", notes, reason].filter { !$0.isEmpty } }
}
nonisolated struct AIReminder: AIResult {
    nonisolated enum Tone: String, Decodable, Sendable { case friendly, firm }
    static let fields: Set<String> = ["tone", "subject", "body", "reason"]
    let tone: Tone, subject: String, body: String, reason: String
    func validate() throws { try AIValidation.text(subject, body, reason) }
    var preview: [String] { ["Tone: \(tone.rawValue)", subject, body, reason] }
}
nonisolated enum AIRoute: String, Codable, CaseIterable, Sendable {
    case dashboard = "/dashboard", bills = "/bills", expenses = "/expenses", invoices = "/invoices", time = "/time-entries", tax = "/tax"
}
nonisolated struct AIInsight: Decodable, Sendable {
    let id: String, title: String, detail: String, href: AIRoute, priority: AIConfidence
    let label: String?
    func validate() throws { try AIValidation.text(id, title, detail, label ?? "") }
}
nonisolated struct AIDashboard: AIResult {
    nonisolated struct Summary: Decodable, Sendable { let headline: String, body: String, highlights: [String] }
    static let fields: Set<String> = ["nextSteps", "monthlySummary", "searchResults"]
    let nextSteps: [AIInsight], monthlySummary: Summary, searchResults: [AIInsight]
    func validate() throws {
        try AIValidation.require(nextSteps.count <= 12 && searchResults.count <= 12 && monthlySummary.highlights.count <= 12)
        try AIValidation.text(monthlySummary.headline, monthlySummary.body)
        for row in nextSteps + searchResults { try row.validate() }
        for text in monthlySummary.highlights { try AIValidation.text(text) }
    }
    var preview: [String] { [monthlySummary.headline, monthlySummary.body] + monthlySummary.highlights }
}

nonisolated struct AIReminderInput: Encodable, Sendable {
    nonisolated struct Client: Encodable, Sendable { let name: String?, contact_name: String? }
    let invoice_number: String, total: Double, currency: String, due_date: String, status: String, client: Client
}
nonisolated struct AISummaryRecord: Encodable, Sendable {
    let id: String, label: String, amount: Double?, date: String, status: String
    var category: String? = nil
    var needsReceipt: Bool? = nil
}
nonisolated struct AIDashboardInput: Encodable, Sendable {
    nonisolated struct Work: Encodable, Sendable {
        var invoices: [AISummaryRecord], expenses: [AISummaryRecord], timeEntries: [AISummaryRecord], vendorBills: [AISummaryRecord]
    }
    let accountType: String, searchQuery: String, bills: [AISummaryRecord], expenses: [AISummaryRecord]
    let workData: Work, candidateHrefs: [AIRoute]
}
