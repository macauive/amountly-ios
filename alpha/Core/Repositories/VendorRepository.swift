import Foundation
import Supabase

struct Vendor: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String
}
struct VendorBill: Decodable, Identifiable {
    let id: String
    let vendor: Vendor?
    let bill_number: String
    let due_date: String
    let status: BillStatus
    let total: Double
    let currency: String?
    let updated_at: String
    var isOpen: Bool { status != .paid && status != .cancelled }
    var displayStatus: BillStatus {
        guard isOpen else { return status }
        let today = RecordCoding.day(Date())
        if due_date < today { return .overdue }
        return due_date == today ? .due : .upcoming
    }
}
final class VendorRepository {
    private let supabase = SupabaseClientManager.shared.client
    func vendors() async throws -> [Vendor] {
        try await supabase.from("vendors").select("id,name,status").is("archived_at", value: nil).order("name").execute().value
    }
    func bills() async throws -> [VendorBill] {
        var rows: [VendorBill] = []
        while true {
            let batch: [VendorBill] = try await supabase.from("vendor_bills").select("*,vendor:vendors(id,name,status)")
                .order("due_date").order("id").range(from: rows.count, to: rows.count + 199).execute().value
            rows += batch
            if batch.count < 200 { return rows }
        }
    }
    func createVendor(name: String) async throws {
        let scope = try await OwnershipResolver().currentScope()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw RecordError.invalid }
        try await supabase.from("vendors").insert(["name": AnyJSON.string(name), "user_id": .string(scope.userId), "organization_id": scope.organizationId.map(AnyJSON.string) ?? .null, "status": .string("active")]).execute()
    }
    func createBill(vendor: String, number: String, date: Date, due: Date, tax: Double, currency: String, notes: String, lines: [LineItem], attempt: RecordAttempt, purchaseOrder: Bool = false) async throws {
        guard !vendor.isEmpty, !number.isEmpty, !lines.isEmpty, lines.count <= 100,
              tax.isFinite, (0...100).contains(tax), RecordCoding.currencies.contains(currency),
              lines.allSatisfy({ !$0.description.isEmpty && $0.quantity.isFinite && $0.quantity > 0 && $0.rate.isFinite && $0.rate >= 0 }) else { throw RecordError.invalid }
        try await attempt.perform(purchaseOrder ? "save_purchase_order" : "save_vendor_bill", params: ["p_id": .string(attempt.id), "p_data": .object(["vendor_id": .string(vendor), (purchaseOrder ? "po_number" : "bill_number"): .string(number), (purchaseOrder ? "date" : "issue_date"): .string(RecordCoding.day(date)), (purchaseOrder ? "expected_date" : "due_date"): .string(RecordCoding.day(due)), "tax_rate": .double(tax), "currency": .string(currency), "notes": .string(notes)]), "p_lines": .array(lines.map { .object(["description": .string($0.description), "quantity": .double($0.quantity), "rate": .double($0.rate)]) })])
    }
    func action(_ bill: VendorBill, action: String, paidOn: Date) async throws {
        guard ["pay", "cancel"].contains(action) else { throw RecordError.invalid }
        do {
            try await supabase.rpc("vendor_bill_action", params: ["p_id": bill.id, "p_action": action, "p_expected_updated_at": bill.updated_at, "p_paid_on": RecordCoding.day(paidOn)]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch { throw RecordError.safe(error) }
    }
}

struct PurchaseOrder: Decodable, Identifiable {
    let id: String
    let po_number: String
    let vendor: Vendor?
    let total: Double
    let currency: String?
    let status: String
    let updated_at: String
}
extension VendorRepository {
    func purchaseOrders() async throws -> [PurchaseOrder] {
        var rows: [PurchaseOrder] = []
        while true {
            let page: [PurchaseOrder] = try await supabase.from("purchase_orders").select("*,vendor:vendors(id,name,status)").order("date", ascending: false).order("id").range(from: rows.count, to: rows.count + 199).execute().value
            rows += page
            if page.count < 200 { return rows }
        }
    }
    func orderAction(_ order: PurchaseOrder, action: String) async throws {
        guard ["send", "receive", "cancel"].contains(action) else { throw RecordError.invalid }
        do {
            try await supabase.rpc("purchase_order_action", params: ["p_id": order.id, "p_action": action, "p_expected_updated_at": order.updated_at]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch { throw RecordError.safe(error) }
    }
    func archiveVendor(_ vendor: Vendor) async throws {
        try await supabase.from("vendors").update(["archived_at": Date().iso8601String]).eq("id", value: vendor.id).select("id").single().execute()
    }
}
