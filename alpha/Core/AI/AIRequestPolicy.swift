import Foundation

// Validate database-derived values and structured requests at the HTTP boundary.
nonisolated enum AIRequestPolicy {
    static func validate(_ task: AITask, payload: Any) throws {
        func fail(_ valid: Bool) throws { if !valid { throw AIError.input } }
        func object(_ value: Any?, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
            guard let dict = value as? [String: Any], required.isSubset(of: Set(dict.keys)), Set(dict.keys).isSubset(of: required.union(optional)) else { throw AIError.input }
            return dict
        }
        func text(_ value: Any?, limit: Int = 2000) throws {
            guard let value = value as? String, value.utf16.count <= limit else { throw AIError.input }
        }
        switch task {
        case .expense, .receipt, .line, .time, .contact:
            guard let value = payload as? String else { throw AIError.input }
            try fail(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 12000)
        case .reminder:
            let p = try object(payload, required: ["invoice_number", "total", "currency", "due_date", "status", "client"])
            try text(p["invoice_number"]); try text(p["due_date"], limit: 40); try text(p["status"], limit: 40)
            try fail((p["currency"] as? String)?.count == 3)
            try fail((p["total"] as? Double).map(AIValidation.money) == true)
            let client = try object(p["client"], required: [], optional: ["name", "contact_name"])
            for value in client.values { try text(value) }
        case .dashboard:
            let p = try object(payload, required: ["accountType", "searchQuery", "bills", "expenses", "workData", "candidateHrefs"])
            try fail(["personal", "freelancer", "business"].contains(p["accountType"] as? String ?? ""))
            try text(p["searchQuery"])
            guard let routes = p["candidateHrefs"] as? [String], routes.count <= 6, routes.allSatisfy({ AIRoute(rawValue: $0) != nil }) else { throw AIError.input }
            let work = try object(p["workData"], required: ["invoices", "expenses", "timeEntries", "vendorBills"])
            for rows in [p["bills"], p["expenses"]] + Array(work.values).map(Optional.some) {
                guard let rows = rows as? [[String: Any]], rows.count <= 100 else { throw AIError.input }
                for value in rows {
                    let row = try object(value, required: ["id", "label", "date", "status"], optional: ["amount", "category", "needsReceipt"])
                    try fail((row["id"] as? String).flatMap(UUID.init(uuidString:)) != nil)
                    try text(row["label"]); try text(row["date"], limit: 40); try text(row["status"], limit: 40)
                    if let amount = row["amount"] { try fail((amount as? Double).map(AIValidation.money) == true) }
                    if let category = row["category"] { try text(category, limit: 80) }
                    if let needsReceipt = row["needsReceipt"] { try fail(needsReceipt is Bool) }
                }
            }
        }
    }
}
