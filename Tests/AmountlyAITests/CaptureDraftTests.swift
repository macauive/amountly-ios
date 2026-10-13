import Foundation
import XCTest
@testable import AmountlyAI

final class CaptureDraftTests: XCTestCase {
    private func object() throws -> [String: Any] {
        var fields = CaptureFields(); fields.description = "Synthetic paper"; fields.amount = "12.50"; fields.currency = "USD"; fields.expense_date = "2026-10-12"
        let payload = CapturePayload(method: .manual, fields: fields, text: "", extraction: nil, extracted: false)
        return ["id":"00000000-0000-4000-8000-000000000001", "revision":1, "updated_at":"2026-10-12T00:00:00.000Z", "payload":try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)), "file_name":NSNull(), "content_type":NSNull()]
    }
    func testPrivateCaptureRoundTripPreservesExplicitNullAndIncompleteFields() throws {
        var row = try object()
        XCTAssertNoThrow(try CaptureDraft.decode(JSONSerialization.data(withJSONObject: row)))
        var payload = row["payload"] as! [String: Any]
        XCTAssertTrue(payload["extraction"] is NSNull)
        var fields = payload["fields"] as! [String: Any]; fields["amount"] = ""; fields["currency"] = ""; fields["expense_date"] = ""
        payload["fields"] = fields; row["payload"] = payload
        let draft = try CaptureDraft.decode(JSONSerialization.data(withJSONObject: row))
        XCTAssertEqual(draft.payload.fields.amount, "")
    }
    func testUnknownFieldsAndInvalidExternalCapturesAreRejected() throws {
        for (key,value) in [("revision",0 as Any),("revision",2147483648),("id","not-a-uuid"),("content_type","text/html"),("unexpected",true)] {
            var row = try object(); row[key] = value
            XCTAssertThrowsError(try CaptureDraft.decode(JSONSerialization.data(withJSONObject: row)))
        }
        var row = try object(); var payload = row["payload"] as! [String: Any]; var fields = payload["fields"] as! [String: Any]
        fields["expense_date"] = "2026-02-30"; payload["fields"] = fields; row["payload"] = payload
        XCTAssertThrowsError(try CaptureDraft.decode(JSONSerialization.data(withJSONObject: row)))
    }
}
