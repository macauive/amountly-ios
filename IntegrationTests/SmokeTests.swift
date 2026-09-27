import XCTest
@testable import alpha

@MainActor
final class SmokeTests: XCTestCase {
    func testLocalConfigurationIsRequired() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_LOCAL_TESTING"] == "1", "Run scripts/run-integration-tests.py against the local stack.")
        XCTAssertTrue(["http://127.0.0.1:54321", "http://127.0.0.1:54331"].contains(ProcessInfo.processInfo.environment["AMOUNTLY_LOCAL_URL"] ?? ""))
    }
}
