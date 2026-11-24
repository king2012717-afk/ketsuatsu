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

    // MARK: - SDK の再初期化

    func testDoesNotRetryInitializationWithoutFailure() {
        XCTAssertFalse(AdInitializationRetry().shouldRetry(at: Date()))
    }

    /// 失敗の直後は見送り、決めた時間が空いてから再初期化する。
    func testRetriesInitializationAfterBackoff() {
        let failedAt = Date(timeIntervalSince1970: 1_000_000)
        var retry = AdInitializationRetry()
        retry.recordFailure(at: failedAt)

        XCTAssertFalse(retry.shouldRetry(at: failedAt.addingTimeInterval(AdRetryPolicy.delays[0] - 1)))
        XCTAssertTrue(retry.shouldRetry(at: failedAt.addingTimeInterval(AdRetryPolicy.delays[0])))
    }

    /// 失敗を重ねるほど待ち時間が延び、上限に達したらそれ以上は試さない。
    func testInitializationRetryBacksOffAndStopsAtLimit() {
        var date = Date(timeIntervalSince1970: 1_000_000)
        var retry = AdInitializationRetry()
        for delay in AdRetryPolicy.delays {
            retry.recordFailure(at: date)
            XCTAssertFalse(retry.shouldRetry(at: date.addingTimeInterval(delay - 1)))
            XCTAssertTrue(retry.shouldRetry(at: date.addingTimeInterval(delay)))
            date = date.addingTimeInterval(delay)
        }
        retry.recordFailure(at: date)

        XCTAssertFalse(retry.shouldRetry(at: date.addingTimeInterval(24 * 60 * 60)), "上限に達したら再初期化しない")
    }
}
