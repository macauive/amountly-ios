//
//  LineItem.swift
//  alpha
//
//  Created by Claude Code on 12/18/25.
//

import Foundation

struct LineItem: Identifiable, Codable {
    let id: UUID
    var description: String
    var quantity: Double
    var rate: Double

    var total: Double {
        FinancialRules.cents(quantity * rate)
    }

    init(id: UUID = UUID(), description: String = "", quantity: Double = 1.0, rate: Double = 0.0) {
        self.id = id
        self.description = description
        self.quantity = quantity
        self.rate = rate
    }
}
