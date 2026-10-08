import XCTest
@testable import AmountlyAI

final class ReceiptFileTests: XCTestCase {
    let sample: [String: Any] = ["document_type": "receipt", "amount": "10.80", "currency": "USD", "merchant": "Demo Shop", "description": "Paper", "expense_date": "2026-10-07", "category": "OFFICE_SUPPLIES", "confidence": "high", "reason": "Total paid", "summary": "Purchase receipt"]
    func decode(_ value: [String: Any]) throws -> AIReceiptFile { try AIReceiptFile.decode(JSONSerialization.data(withJSONObject: ["result": value])) }
    func testReceiptAndUnknownFieldsRemainReviewable() throws {
        XCTAssertEqual(try decode(sample).amount, "10.80")
        var value = sample; value["amount"] = ""; value["currency"] = ""; value["expense_date"] = ""
        let unknown = try decode(value); XCTAssertEqual(unknown.amount, ""); XCTAssertEqual(unknown.supportedCurrency, ""); XCTAssertEqual(unknown.expense_date, "")
        value["currency"] = "OTHER"; XCTAssertEqual(try decode(value).supportedCurrency, "")
        for kind in ["invoice", "statement", "other"] { value["document_type"] = kind; XCTAssertNotEqual(try decode(value).document_type, .receipt) }
    }
    func testRejectsInvalidOrUnboundedProposals() {
        for (key, invalid): (String, Any) in [("amount", "-10"), ("amount", "$10.80"), ("amount", "999999999"), ("currency", "JPY"), ("expense_date", "2026-02-31"), ("merchant", String(repeating: "x", count: 201)), ("category", "INVENTED"), ("document_type", "refund"), ("summary", String(repeating: "x", count: 1001))] {
            var value = sample; value[key] = invalid; XCTAssertThrowsError(try decode(value))
        }
        var extra = sample; extra["owner_id"] = "untrusted"; XCTAssertThrowsError(try decode(extra))
        XCTAssertThrowsError(try AIReceiptFile.decode(Data("{}".utf8)))
    }
}
