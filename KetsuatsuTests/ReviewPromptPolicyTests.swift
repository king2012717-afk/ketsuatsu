import XCTest
@testable import Ketsuatsu

final class ReviewPromptPolicyTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makePolicy(version: String = "1.3") -> ReviewPromptPolicy {
        ReviewPromptPolicy(defaults: defaults, appVersion: version)
    }

    func testNotBeforeFiveEntries() {
        let policy = makePolicy()
        XCTAssertFalse(policy.shouldRequest(completedEntries: 0, now: start))
        XCTAssertFalse(policy.shouldRequest(completedEntries: 4, now: start))
        XCTAssertTrue(policy.shouldRequest(completedEntries: 5, now: start))
    }

    func testOncePerVersion() {
        let policy = makePolicy()
        policy.markRequested(now: start)
        XCTAssertFalse(policy.shouldRequest(completedEntries: 50, now: start.addingTimeInterval(400 * day)))
    }

    func testNewVersionNeedsInterval() {
        makePolicy(version: "1.3").markRequested(now: start)
        let next = makePolicy(version: "1.4")
        XCTAssertFalse(next.shouldRequest(completedEntries: 10, now: start.addingTimeInterval(119 * day)))
        XCTAssertTrue(next.shouldRequest(completedEntries: 10, now: start.addingTimeInterval(121 * day)))
    }

    func testAtMostThreeTimes() {
        for (index, version) in ["1.3", "1.4", "1.5"].enumerated() {
            makePolicy(version: version).markRequested(now: start.addingTimeInterval(Double(index) * 200 * day))
        }
        let policy = makePolicy(version: "1.6")
        XCTAssertEqual(policy.requestCount, 3)
        XCTAssertFalse(policy.shouldRequest(completedEntries: 100, now: start.addingTimeInterval(1000 * day)))
    }
}
