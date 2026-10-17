import XCTest
@testable import Ketsuatsu

final class AdRetryPolicyTests: XCTestCase {

    func testDelaysGrowAndStopAtLimit() {
        var policy = AdRetryPolicy()
        var delays: [TimeInterval] = []
        while let delay = policy.nextDelay() {
            delays.append(delay)
        }

        XCTAssertEqual(delays, AdRetryPolicy.delays)
        XCTAssertEqual(delays, delays.sorted(), "待ち時間は短い順に延びていく")
        XCTAssertNil(policy.nextDelay(), "上限に達したら再試行しない（無限に繰り返さない）")
    }

    func testResetAfterSuccessfulLoad() {
        var policy = AdRetryPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()

        policy.reset()

        XCTAssertEqual(policy.nextDelay(), AdRetryPolicy.delays.first)
    }
}
