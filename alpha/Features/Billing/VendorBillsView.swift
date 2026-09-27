import SwiftUI

struct VendorBillsView: View {
    @State private var bills: [VendorBill] = []
    @State private var error: String?
    @State private var loading = true
    @State private var showingCreate = false
    @State private var selected: VendorBill?
    @State private var history: VendorBill?
    @State private var action = "pay"
    @State private var paidOn = Date()
    @State private var saving = false
    var body: some View {
        List {
            if loading { ProgressView("Loading vendor bills…") }
            if let error { Text(error).foregroundStyle(.red) }
            NavigationLink("Vendors", destination: VendorsView())
            NavigationLink("Purchase Orders", destination: PurchaseOrdersView())
            Button("New Vendor Bill") { showingCreate = true }
            if !loading && bills.isEmpty && error == nil { ContentUnavailableView("No vendor bills", systemImage: "creditcard", description: Text("Add a bill to track money owed to a vendor.")) }
            ForEach(bills) { bill in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(bill.vendor?.name ?? "Vendor").font(.headline); Spacer(); Text(bill.total, format: .currency(code: bill.currency ?? "USD")) }
                    Text("\(bill.bill_number) · Due \(bill.due_date)").font(.caption)
                    Text(bill.displayStatus.displayName).font(.caption)
                    Button("History") { history = bill }.buttonStyle(.bordered)
                    if bill.isOpen {
                        HStack {
                            Button("Record Payment") { action = "pay"; selected = bill }.buttonStyle(.bordered)
                            Button("Cancel Bill", role: .destructive) { action = "cancel"; selected = bill }.buttonStyle(.bordered)
                        }
                    }
                }.padding(.vertical, 6)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await load() } }
        .sheet(isPresented: $showingCreate) { VendorBillForm(isPresented: $showingCreate) }
        .sheet(item: $history) { bill in RecordHistoryView(kind: "vendor_bills", id: bill.id) }
        .sheet(item: $selected) { bill in
            NavigationStack {
                Form {
                    Text(bill.bill_number)
                    if action == "pay" { DatePicker("Paid on", selection: $paidOn, in: ...Date(), displayedComponents: .date) }
                    Text(action == "pay" ? "Records an existing payment. No money will be moved." : "Cancellation preserves the bill and its history.")
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(action == "pay" ? "Record Payment" : "Cancel Bill", role: action == "cancel" ? .destructive : nil) {
                        Task { saving = true; defer { saving = false }; do { try await VendorRepository().action(bill, action: action, paidOn: paidOn); selected = nil; await load() } catch { self.error = RecordError.safe(error).localizedDescription } }
                    }.disabled(saving)
                }.navigationTitle("Review Bill")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { selected = nil }.disabled(saving) } }
            }.interactiveDismissDisabled(saving)
        }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { bills = try await VendorRepository().bills(); error = nil }
        catch { self.error = "Could not load vendor bills. Pull to retry." }
    }
}

struct VendorBillForm: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    var purchaseOrder = false
    @State private var vendors: [Vendor] = []
    @State private var vendor = ""
    @State private var vendorName = ""
    @State private var number = ""
    @State private var date = Date()
    @State private var due = Date()
    @State private var tax = 0.0
    @State private var currency = "USD"
    @State private var notes = ""
    @State private var lines = [LineItem()]
    @State private var error: String?
    @State private var saving = false
    @State private var attempted = false
    @State private var attempt = RecordAttempt()
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Vendor") {
                        Picker("Vendor", selection: $vendor) { Text("Select vendor").tag(""); ForEach(vendors.filter { $0.status == "active" }) { Text($0.name).tag($0.id) } }
                        TextField("New vendor name", text: $vendorName)
                        Button("Add Vendor") { Task { await addVendor() } }.disabled(vendorName.isEmpty || saving)
                    }
                    Section("Bill details") {
                        TextField(purchaseOrder ? "Purchase order number" : "Bill number", text: $number)
                        DatePicker("Issue date", selection: $date, displayedComponents: .date)
                        DatePicker(purchaseOrder ? "Expected date" : "Due date", selection: $due, displayedComponents: .date)
                        Picker("Currency", selection: $currency) { ForEach(RecordCoding.currencies, id: \.self) { Text($0) } }
                        TextField("Tax %", value: $tax, format: .number).keyboardType(.decimalPad)
                    }
                    Section("Line items") {
                        ForEach($lines) { $line in
                            VStack {
                                TextField("Description", text: $line.description)
                                HStack {
                                    TextField("Quantity", value: $line.quantity, format: .number).keyboardType(.decimalPad)
                                    TextField("Rate", value: $line.rate, format: .number).keyboardType(.decimalPad)
                                }
                            }
                        }.onDelete { lines.remove(atOffsets: $0) }
                        Button("Add Line") { lines.append(LineItem()) }.disabled(lines.count >= 100)
                        TextField("Notes", text: $notes, axis: .vertical)
                    }
                }.disabled(attempted || saving)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(purchaseOrder ? "New Purchase Order" : "New Vendor Bill")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button(attempted ? "Retry" : "Save") { Task { await save() } }.disabled(vendor.isEmpty || number.isEmpty || saving) }
                }
                .task {
                    currency = appState.currentUser?.reportingCurrency ?? "USD"
                    do { vendors = try await VendorRepository().vendors() } catch { self.error = "Could not load vendors." }
                }.interactiveDismissDisabled(saving)
        }
    }
    private func addVendor() async {
        saving = true; defer { saving = false }
        do { try await VendorRepository().createVendor(name: vendorName); vendors = try await VendorRepository().vendors(); vendorName = "" }
        catch { self.error = RecordError.safe(error).localizedDescription }
    }
    private func save() async {
        saving = true; attempted = true; defer { saving = false }
        do { try await VendorRepository().createBill(vendor: vendor, number: number, date: date, due: due, tax: tax, currency: currency, notes: notes, lines: lines, attempt: attempt, purchaseOrder: purchaseOrder); isPresented = false }
        catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
