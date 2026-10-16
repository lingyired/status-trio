import Foundation
import XCTest
@testable import StatusTrioCore

final class PowerHelperReplyTests: XCTestCase {
    func testUnresponsiveRequestCompletesAtItsDeadline() async {
        do {
            let _: Bool = try await withCheckedThrowingContinuation { continuation in
                _ = OneShotReply(
                    continuation: continuation,
                    connection: NSXPCConnection(machServiceName: "test.unused"),
                    timeout: 0.01,
                    queue: DispatchQueue(label: "test.helper.deadline")
                )
            }
            XCTFail("A request without a reply must time out")
        } catch {
            XCTAssertTrue(error is LowPowerModeClientError)
        }
    }

    func testReplyWinsOverLaterFailureAndDeadline() async throws {
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            let reply = OneShotReply(
                continuation: continuation,
                connection: NSXPCConnection(machServiceName: "test.unused"),
                timeout: 0.01,
                queue: DispatchQueue(label: "test.helper.reply")
            )
            reply.resolve(.success(true))
            reply.resolve(.failure(LowPowerModeClientError.helperUnavailable))
        }
        XCTAssertTrue(result)
        try await Task.sleep(for: .milliseconds(30))
    }
}
