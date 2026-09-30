import XCTest
import SwiftUI
@testable import alpha

// Only the isolated XCTest host can enable this inspection. No production
// debug switches, auth bypasses, credentials, or mock code enter the app target.
final class AIInspectionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"result":{"description":"Design work","quantity":2,"rate":75,"amount":150,"reason":"Two hours at 75 per hour"},"safety":{"redacted":false}}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private struct AICaptureInspection: View {
    let client: AIClient
    @State private var text = "Design work: 2 hours at $75 per hour."
    @State private var applied = "No suggestion applied"
    var body: some View {
        NavigationStack {
            Form {
                AICaptureSection<AILine>(title: "Smart invoice line", text: $text, task: .line, apply: { applied = "Applied: \($0.description) · \($0.amount.formatted())" }, client: client)
                Section("Editable form preview") { Text(applied) }
            }.navigationTitle("AI Capture Verification")
        }
    }
}

@MainActor
final class AICaptureInspectionTests: XCTestCase {
    func testInspectNativeSuggestionAndApply() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_AI_UI_INSPECTION"] == "1", "Opt-in manual simulator inspection.")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let previous = window.rootViewController
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AIInspectionProtocol.self]
        let client = AIClient(configuration: config) { AISession(userID: "synthetic", token: "synthetic_token_000000000000") }
        window.rootViewController = UIHostingController(rootView: AICaptureInspection(client: client).environmentObject(AppState()))
        window.makeKeyAndVisible()
        defer { window.rootViewController = previous }
        try await Task.sleep(for: .seconds(55))
    }
}
