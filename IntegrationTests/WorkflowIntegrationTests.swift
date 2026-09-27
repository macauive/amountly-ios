import XCTest
import Supabase
import PDFKit
@testable import alpha

@MainActor
final class WorkflowIntegrationTests: XCTestCase {
    struct Actor: Decodable { let id: String; let email: String; let password: String; let organization: String?; let client: String?; let project: String?; let timeEntry: String? }
    struct Fixtures: Decodable { let actors: [String: Actor]; let anonKey: String }
    private var fixtures: Fixtures!
    private var client: SupabaseClient { SupabaseClientManager.shared.client }
    private var day: Date { RecordCoding.parseDate("2026-01-15")! }
    private var due: Date { RecordCoding.parseDate("2026-02-15")! }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_LOCAL_TESTING"] == "1", "Local integration configuration required")
        guard let url = ProcessInfo.processInfo.environment["AMOUNTLY_LOCAL_URL"], url == "http://127.0.0.1:54331",
              let raw = ProcessInfo.processInfo.environment["AMOUNTLY_TEST_FIXTURES"] else { throw RecordError.invalid }
        fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(raw.utf8))
    }
    @discardableResult private func login(_ name: String) async throws -> Actor {
        let actor = try XCTUnwrap(fixtures.actors[name])
        _ = try await AuthService.shared.login(email: actor.email, password: actor.password)
        return actor
    }
    private func denied(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected operation to be rejected", file: file, line: line) } catch {}
    }
    private func fault(_ path: String, method: String = "POST", mode: String = "drop") async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:54331/__test/fault")!)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path":path,"method":method,"mode":mode])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
    }
    private func draft(_ actor: Actor, amount: Double = 100, attempt: RecordAttempt = RecordAttempt(), lines: Int = 1) async throws -> Invoice {
        try await InvoiceRepository().createInvoice(clientId: actor.client!, projectId: nil, dueDate: due,
            lineItems: (0..<lines).map { InvoiceLineItemCreate(description: "Design work \($0) " + String(repeating: "detail ", count: 12), quantity: 1, rate: amount) },
            taxRate: 0, notes: "Synthetic native integration", currency: "USD", attempt: attempt, issueDate: day)
    }
    private func expense(_ amount: Double = 15, attempt: RecordAttempt = RecordAttempt(), receiptPath: String? = nil) async throws -> Expense {
        try await ExpenseRepository().createExpense(description: "Synthetic native expense", amount: amount, currency: "USD", category: "OTHER", merchant: nil, expenseDate: day, projectId: nil, notes: nil, status: "DRAFT", attempt: attempt, receiptPath: receiptPath)
    }

    func test01InvoiceWritesCorrectionsConcurrencyAndSnapshots() async throws {
        let owner = try await login("owner"), repo = InvoiceRepository()
        let original = try await draft(owner)
        XCTAssertEqual(original.total,100); XCTAssertEqual(original.status,.draft)
        let data: [String:AnyJSON] = ["client_id":.string(owner.client!),"project_id":.null,"invoice_number":.string(original.invoiceNumber),"issue_date":.string("2026-01-15"),"due_date":.string("2026-02-15"),"tax_rate":.double(0),"currency":.string("USD"),"notes":.string("Edited from second session")]
        let second = SupabaseClient(supabaseURL: URL(string:"http://127.0.0.1:54321")!, supabaseKey: fixtures.anonKey)
        try await second.auth.signIn(email:owner.email,password:owner.password)
        try await second.rpc("save_invoice",params:["p_id":AnyJSON.string(original.id),"p_data":.object(data),"p_lines":.array([.object(["description":.string("Edited line"),"quantity":.double(1),"rate":.double(100)])]),"p_expected_updated_at":.string(original.version!)]).execute()
        await denied { try await repo.action(original,"issue") }
        var invoice = try await repo.fetchInvoice(id:original.id)
        try await repo.action(invoice,"issue")
        invoice = try await repo.fetchInvoice(id:invoice.id)
        XCTAssertEqual(invoice.status,.sent); XCTAssertEqual(invoice.issuedSnapshot?.lines?.count,1)
        let frozen = invoice.displayClientName
        try await client.from("clients").update(["name":"Renamed after issue"]).eq("id",value:owner.client!).execute()
        invoice = try await repo.fetchInvoice(id:invoice.id)
        XCTAssertEqual(invoice.displayClientName,frozen)
        try await PaymentRepository().record(invoice:invoice,amount:40,method:"bank_transfer",reference:"Synthetic deposit",date:day,attempt:RecordAttempt())
        invoice = try await repo.fetchInvoice(id:invoice.id)
        XCTAssertEqual(invoice.amountPaid,40);XCTAssertEqual(invoice.balanceDue,60)
        let current = invoice
        async let one: Void = PaymentRepository().record(invoice:current,amount:60,method:"cash",reference:"Concurrent A",date:day,attempt:RecordAttempt())
        async let two: Void = PaymentRepository().record(invoice:current,amount:60,method:"cash",reference:"Concurrent B",date:day,attempt:RecordAttempt())
        var accepted = 0
        do { try await one; accepted += 1 } catch {}
        do { try await two; accepted += 1 } catch {}
        XCTAssertEqual(accepted,1)
        invoice = try await repo.fetchInvoice(id:invoice.id)
        XCTAssertEqual(invoice.amountPaid,100); XCTAssertEqual(invoice.status,.paid)
        XCTAssertEqual(invoice.lastPaymentDate, day)
        let payment = try XCTUnwrap(invoice.payments?.first { $0.amount == 40 })
        let correction = RecordAttempt()
        try await PaymentRepository().reverse(payment:payment,reason:"Synthetic incorrect deposit",attempt:correction)
        try await PaymentRepository().reverse(payment:payment,reason:"Synthetic incorrect deposit",attempt:correction)
        invoice = try await repo.fetchInvoice(id:invoice.id)
        XCTAssertEqual(invoice.amountPaid,60);XCTAssertEqual(invoice.balanceDue,40)
        try await PaymentRepository().record(invoice:invoice,amount:40,method:"card",reference:"Replacement",date:day,attempt:RecordAttempt())
        invoice = try await repo.fetchInvoice(id:invoice.id)
        XCTAssertEqual(invoice.amountPaid,100);XCTAssertEqual(invoice.balanceDue,0)
        XCTAssertEqual(invoice.payments?.filter(\.isReversed).count,1)
        await denied { try await repo.action(invoice,"delete") }
        try await second.auth.signOut()
    }

    func test02LostResponsesAndDuplicateTaps() async throws {
        let owner = try await login("owner")
        let attempt = RecordAttempt()
        try await fault("/rest/v1/rpc/save_invoice")
        do { _ = try await draft(owner,amount:17,attempt:attempt) } catch {}
        let invoice = try await draft(owner,amount:999,attempt:attempt)
        XCTAssertEqual(invoice.total,17)
        let saved = try await InvoiceRepository().fetchInvoices()
        XCTAssertEqual(saved.filter { $0.id == attempt.id }.count,1)
        let expenseAttempt = RecordAttempt()
        try await fault("/rest/v1/rpc/create_money_record")
        do { _ = try await expense(22,attempt:expenseAttempt) } catch {}
        let recovered = try await expense(999,attempt:expenseAttempt)
        XCTAssertEqual(recovered.amount,22)
        let readAttempt = RecordAttempt()
        try await fault("/rest/v1/expenses",method:"GET")
        do { _ = try await expense(23,attempt:readAttempt) } catch {}
        let afterRead = try await expense(999,attempt:readAttempt)
        XCTAssertEqual(afterRead.amount,23)
        let tapAttempt = RecordAttempt()
        try await fault("/rest/v1/rpc/create_money_record",mode:"delay")
        async let first = expense(24,attempt:tapAttempt)
        async let second = expense(24,attempt:tapAttempt)
        do { _ = try await first } catch {}
        do { _ = try await second } catch {}
        let all = try await ExpenseRepository().fetchExpenses()
        XCTAssertEqual(all.filter { $0.id == tapAttempt.id }.count,1)
    }

    func test03RolesReviewAndTenantIsolation() async throws {
        let member = try await login("member")
        await denied { _ = try await self.draft(member) }
        var item = try await expense()
        item = try await ExpenseRepository().updateStatus(id:item.id,status:"SUBMITTED",expectedVersion:item.version)
        await denied { _ = try await ExpenseRepository().updateStatus(id:item.id,status:"APPROVED",expectedVersion:item.version) }
        _ = try await login("admin")
        item = try await ExpenseRepository().updateStatus(id:item.id,status:"APPROVED",expectedVersion:item.version)
        XCTAssertEqual(item.status,.approved)
        await denied { try await ExpenseRepository().deleteExpense(id:item.id,expectedVersion:item.version) }
        _ = try await login("outsider")
        await denied { _ = try await ExpenseRepository().fetchExpense(id:item.id) }
        let owner = try await login("owner")
        let invoice = try await draft(owner)
        _ = try await login("member")
        await denied { _ = try await InvoiceRepository().fetchInvoice(id:invoice.id) }
        _ = try await login("outsider")
        await denied { _ = try await InvoiceRepository().fetchInvoice(id:invoice.id) }
        await denied { _ = try await self.login("disabled") }
        _ = try await login("personal")
        let bill = try await BillRepository().createBill(name:"Synthetic rent",payee:"Test payee",amount:75,category:"other",dueDate:due,recurrence:.monthly,notes:nil,currency:"EUR")
        try await BillRepository().action(bill,action:"pay",paidOn:day)
        let paid = try await BillRepository().fetchBill(id:bill.id)
        XCTAssertEqual(paid.status,.paid);XCTAssertEqual(paid.currency,"EUR")
        await denied { try await BillRepository().action(bill,action:"cancel") }
    }

    func test04TimeReservationAndPurchasing() async throws {
        let owner = try await login("owner")
        let entries = try await TimeEntryRepository().fetchUnbilledTimeEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == fixtures.actors["member"]?.timeEntry })
        let attempt = RecordAttempt(), repo = InvoiceRepository()
        try await repo.createFromTime(entries:[entry],clientId:owner.client!,dueDate:due,currency:"USD",attempt:attempt,issueDate:day)
        try await repo.createFromTime(entries:[entry],clientId:owner.client!,dueDate:due,currency:"USD",attempt:attempt,issueDate:day)
        await denied { try await repo.createFromTime(entries:[entry],clientId:owner.client!,dueDate:self.due,currency:"USD",attempt:RecordAttempt(),issueDate:self.day) }
        let reserved = try await TimeEntryRepository().fetchTimeEntries()
        XCTAssertTrue(try XCTUnwrap(reserved.first { $0.id == entry.id }).isReserved)
        let draft = try await repo.fetchInvoice(id:attempt.id)
        XCTAssertEqual(draft.total,125)
        try await repo.action(draft,"delete")
        let released = try await TimeEntryRepository().fetchUnbilledTimeEntries()
        XCTAssertTrue(released.contains { $0.id == entry.id })
        let vendorRepo = VendorRepository()
        let name = "Supplier \(UUID().uuidString)"
        try await vendorRepo.createVendor(name:name)
        let vendors = try await vendorRepo.vendors()
        let vendor = try XCTUnwrap(vendors.first { $0.name == name })
        let billAttempt = RecordAttempt()
        try await vendorRepo.createBill(vendor:vendor.id,number:"B-\(UUID().uuidString.prefix(8))",date:day,due:due,tax:10,currency:"EUR",notes:"Synthetic",lines:[LineItem(description:"Service",quantity:2,rate:50)],attempt:billAttempt)
        let bills = try await vendorRepo.bills()
        let bill = try XCTUnwrap(bills.first { $0.id == billAttempt.id })
        XCTAssertEqual(bill.total,110)
        try await vendorRepo.action(bill,action:"pay",paidOn:day)
        await denied { try await vendorRepo.action(bill,action:"cancel",paidOn:self.day) }
        let poAttempt = RecordAttempt()
        try await vendorRepo.createBill(vendor:vendor.id,number:"PO-\(UUID().uuidString.prefix(8))",date:day,due:due,tax:0,currency:"USD",notes:"Synthetic",lines:[LineItem(description:"Goods",quantity:2,rate:60)],attempt:poAttempt,purchaseOrder:true)
        let orders = try await vendorRepo.purchaseOrders()
        let po = try XCTUnwrap(orders.first { $0.id == poAttempt.id })
        try await vendorRepo.orderAction(po,action:"send")
        await denied { try await vendorRepo.orderAction(po,action:"receive") }
        let sent = try await vendorRepo.purchaseOrders()
        try await vendorRepo.orderAction(try XCTUnwrap(sent.first { $0.id == po.id }),action:"receive")
        let free = try await login("freelancer")
        let freeEntries = try await TimeEntryRepository().fetchUnbilledTimeEntries()
        let freeEntry = try XCTUnwrap(freeEntries.first { $0.id == free.timeEntry })
        XCTAssertEqual(freeEntry.status,.draft)
        try await repo.createFromTime(entries:[freeEntry],clientId:free.client!,dueDate:due,currency:"USD",attempt:RecordAttempt(),issueDate:day)
    }

    func test05PrivateReceiptAndExpiration() async throws {
        _ = try await login("owner")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        let data = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN9kAAAAASUVORK5CYII=")!
        try data.write(to:url);defer { try? FileManager.default.removeItem(at:url) }
        let path = try await ReceiptStorage().upload(url:url)
        let item = try await expense(receiptPath:path)
        let signed = try await ReceiptStorage().signedURL(for:item)
        let (download,response) = try await URLSession.shared.data(from:signed)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200);XCTAssertEqual(download,data)
        _ = try await login("outsider")
        await denied { _ = try await ReceiptStorage().signedURL(for:item) }
        await denied { try await self.client.storage.from("receipts").upload(path,data:data,options:FileOptions(contentType:"image/png",upsert:false)) }
        _ = try await login("owner")
        let short = try await client.storage.from("receipts").createSignedURL(path:path,expiresIn:1)
        try await Task.sleep(nanoseconds:2_100_000_000)
        let (_,expired) = try await URLSession.shared.data(from:short)
        XCTAssertNotEqual((expired as? HTTPURLResponse)?.statusCode,200)
        let fresh = try await ReceiptStorage().signedURL(for:item)
        let (_,valid) = try await URLSession.shared.data(from:fresh)
        XCTAssertEqual((valid as? HTTPURLResponse)?.statusCode,200)
    }

    func test06PaginationExportsPreferencesAndPDF() async throws {
        _ = try await login("bulk")
        let invoices = try await InvoiceRepository().fetchInvoices()
        XCTAssertEqual(invoices.count,1005);XCTAssertEqual(Set(invoices.map(\.id)).count,1005)
        XCTAssertEqual(FinancialRules.sum(invoices.map(\.balanceDue)),502.5)
        XCTAssertEqual(FinancialRules.sum(invoices.filter { $0.currency == "USD" }.map(\.balanceDue)),251.5)
        let exported = try await CSVExportDataSource.fetchRawRows(table:"invoices",headers:DataExportKind.invoices.headers)
        XCTAssertEqual(exported.count,1005)
        await denied { _ = try await CSVExportDataSource.fetchRawRows(table:"users",headers:["id"]) }
        await denied { _ = try await CSVExportDataSource.fetchRawRows(table:"expenses",headers:["receipt_url"]) }
        let csv = CSVExportBuilder.makeCSV(headers:["name"],rows:[["name":"=HYPERLINK(\"https://example.invalid\")"]])
        XCTAssertTrue(csv.contains("\"'=HYPERLINK"))
        let owner = try await login("owner")
        let patch:[String:AnyJSON] = ["default_currency":.string("EUR"),"accounting_basis":.string("accrual"),"fiscal_year_start":.integer(4),"payment_terms":.integer(14)]
        try await client.rpc("set_own_preferences",params:["p_patch":AnyJSON.object(patch)]).execute()
        let user = try await AuthService.shared.getCurrentUser()
        XCTAssertEqual(user.reportingCurrency,"EUR");XCTAssertEqual(user.incomeBasis,"accrual");XCTAssertEqual(user.fiscalStartMonth,4)
        let second = SupabaseClient(supabaseURL:URL(string:"http://127.0.0.1:54321")!,supabaseKey:fixtures.anonKey)
        try await second.auth.signIn(email:owner.email,password:owner.password)
        try await second.rpc("set_own_preferences",params:["p_patch":AnyJSON.object(["default_currency":.string("USD")])]).execute()
        let refreshed = try await AuthService.shared.getCurrentUser()
        XCTAssertEqual(refreshed.reportingCurrency,"USD");XCTAssertEqual(refreshed.fiscalStartMonth,4)
        let invoice = try await draft(owner,lines:45)
        let data = try XCTUnwrap(InvoicePDFGenerator().generatePDF(for:invoice,organization:nil))
        let document = try XCTUnwrap(PDFDocument(data:data))
        XCTAssertGreaterThan(document.pageCount,1)
        XCTAssertTrue(document.string?.contains(invoice.invoiceNumber) == true)
        XCTAssertTrue(document.string?.contains("Balance due") == true)
        try await second.auth.signOut()
    }
    func test07SessionRefreshRestoreAndSignOut() async throws {
        let owner = try await login("owner")
        let before = try XCTUnwrap(client.auth.currentSession)
        let refreshed = try await client.auth.refreshSession()
        XCTAssertEqual(refreshed.user.id, before.user.id)
        let restored = try await AuthService.shared.restoreAuthenticatedState()
        XCTAssertEqual(restored?.user.id.lowercased(), owner.id.lowercased())
        try await AuthService.shared.logout()
        let signedOut = try await AuthService.shared.restoreAuthenticatedState()
        XCTAssertNil(signedOut)
        await denied { _ = try await AuthService.shared.getCurrentUser() }
        // Restore the synthetic owner so the same fixture can be inspected in the UI.
        try await login("owner")
    }

    func test08LoginFormFailureAndRecovery() async throws {
        try await AuthService.shared.logout()
        let owner = try XCTUnwrap(fixtures.actors["owner"])
        let state = AppState()
        let form = LoginViewModel()
        form.email = owner.email
        form.password = "incorrect-local-test-password"
        await form.login(appState: state)
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertFalse(form.isLoading)
        XCTAssertEqual(form.errorMessage, "Could not sign in. Check your credentials and connection, then try again.")
        form.password = owner.password
        await form.login(appState: state)
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertFalse(form.isLoading)
        XCTAssertNil(form.errorMessage)
        XCTAssertEqual(state.currentUser?.id.lowercased(), owner.id.lowercased())
    }

}
