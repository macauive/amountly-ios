import SwiftUI

struct PurchaseOrdersView: View {
    @State private var orders: [PurchaseOrder] = []
    @State private var error: String?
    @State private var creating = false
    @State private var pending: PurchaseOrder?
    @State private var history: PurchaseOrder?
    @State private var action = "send"
    @State private var busy = false
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Button("New Purchase Order") { creating = true }
            ForEach(orders) { order in
                VStack(alignment: .leading, spacing: 10) {
                    Text(order.po_number).font(.headline)
                    Text("\(order.vendor?.name ?? "Vendor") · \(order.total.formatted(.currency(code: order.currency ?? "USD")))")
                    Text(order.status.capitalized).font(.caption)
                    HStack {
                        Button("History") { history = order }
                        if order.status == "draft" { Button("Mark Sent") { action = "send"; pending = order } }
                        if order.status == "sent" { Button("Mark Received") { action = "receive"; pending = order } }
                        if ["draft", "sent"].contains(order.status) { Button("Cancel Order", role: .destructive) { action = "cancel"; pending = order } }
                    }.buttonStyle(.bordered).font(.caption)
                }
            }
        }.navigationTitle("Purchase Orders").disabled(busy)
            .task { await load() }.refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await load() } }
            .sheet(item: $history) { order in RecordHistoryView(kind: "purchase_orders", id: order.id) }
            .sheet(isPresented: $creating) { VendorBillForm(isPresented: $creating, purchaseOrder: true) }
            .confirmationDialog("Confirm purchase order status", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                if let order = pending { Button("Confirm \(action)") { Task { busy = true; defer { busy = false }; do { try await VendorRepository().orderAction(order, action: action); await load() } catch { self.error = RecordError.safe(error).localizedDescription } } } }
            } message: { Text("This updates the recorded status. It does not send the order to your vendor.") }
    }
    private func load() async { do { orders = try await VendorRepository().purchaseOrders(); error = nil } catch { self.error = "Could not load purchase orders." } }
}
struct VendorsView: View {
    @State private var vendors: [Vendor] = []
    @State private var error: String?
    @State private var name = ""
    @State private var busy = false
    @State private var archive: Vendor?
    var body: some View {
        List {
            Section("New Vendor") {
                TextField("Name", text: $name)
                Button("Add Vendor") { Task { busy = true; defer { busy = false }; do { try await VendorRepository().createVendor(name: name); name = ""; await load() } catch { self.error = RecordError.safe(error).localizedDescription } } }.disabled(name.isEmpty || busy)
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(vendors) { vendor in
                HStack { Text(vendor.name); Spacer(); Text(vendor.status.capitalized).foregroundStyle(.secondary) }
                    .swipeActions { Button("Archive", role: .destructive) { archive = vendor } }
            }
        }.navigationTitle("Vendors").task { await load() }.refreshable { await load() }
            .confirmationDialog("Archive vendor?", isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } })) {
                if let vendor = archive { Button("Archive", role: .destructive) { Task { do { try await VendorRepository().archiveVendor(vendor); await load() } catch { self.error = RecordError.safe(error).localizedDescription } } } }
            } message: { Text("Existing bills and purchase orders remain available.") }
    }
    private func load() async { do { vendors = try await VendorRepository().vendors(); error = nil } catch { self.error = "Could not load vendors." } }
}
