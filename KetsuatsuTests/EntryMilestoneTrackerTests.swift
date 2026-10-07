import XCTest
@testable import Ketsuatsu

final class EntryMilestoneTrackerTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "EntryMilestoneTrackerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeTracker() -> EntryMilestoneTracker {
        EntryMilestoneTracker(defaults: defaults)
    }

    // MARK: - 新規インストール

    func testNewInstallFiresOnlyOnThirdEntry() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 0 }

        XCTAssertFalse(tracker.addCompletedEntries())
        XCTAssertFalse(tracker.addCompletedEntries())
        XCTAssertTrue(tracker.addCompletedEntries())
        XCTAssertFalse(tracker.addCompletedEntries())
        XCTAssertFalse(tracker.addCompletedEntries())
        XCTAssertEqual(tracker.completedEntries, 5)
    }

    func testRestartDoesNotFireAgain() {
        let first = makeTracker()
        first.migrateIfNeeded { 0 }
        for _ in 0..<3 { _ = first.addCompletedEntries() }

        // 再起動を想定して作り直す。保存先が同じなら状態は引き継がれる。
        let second = makeTracker()
        second.migrateIfNeeded { 0 }
        XCTAssertFalse(second.addCompletedEntries())
        XCTAssertTrue(second.isThirdEntrySent)
    }

    func testDeleteAndReRegisterDoesNotFireAgain() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 0 }
        for _ in 0..<3 { _ = tracker.addCompletedEntries() }

        // 削除しても件数は減らさないので、登録し直しても送らない。
        XCTAssertFalse(tracker.addCompletedEntries())
        XCTAssertFalse(tracker.addCompletedEntries())
    }

    // MARK: - 既存ユーザー（アップデート）

    func testExistingUserWithThreeOrMoreRecordsNeverFires() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 10 }

        XCTAssertTrue(tracker.isThirdEntrySent)
        XCTAssertFalse(tracker.addCompletedEntries())
        XCTAssertEqual(tracker.completedEntries, 11)
    }

    func testExistingUserWithFewerRecordsContinuesCounting() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 2 }

        XCTAssertFalse(tracker.isThirdEntrySent)
        XCTAssertTrue(tracker.addCompletedEntries())
        XCTAssertFalse(tracker.addCompletedEntries())
    }

    func testMigrationRunsOnlyOnce() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 1 }

        var called = false
        tracker.migrateIfNeeded {
            called = true
            return 100
        }
        XCTAssertFalse(called)
        XCTAssertEqual(tracker.completedEntries, 1)
    }

    func testAlreadySentWithLegacyKeyIsRespected() {
        defaults.set(true, forKey: EntryMilestoneTracker.Key.thirdEntrySent)
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 0 }

        for _ in 0..<5 {
            XCTAssertFalse(tracker.addCompletedEntries())
        }
    }

    // MARK: - まとめて記録

    func testBatchCrossingThresholdFiresOnce() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 1 }

        XCTAssertTrue(tracker.addCompletedEntries(5))
        XCTAssertFalse(tracker.addCompletedEntries(5))
        XCTAssertEqual(tracker.completedEntries, 11)
    }

    func testZeroCountIsIgnored() {
        let tracker = makeTracker()
        tracker.migrateIfNeeded { 2 }

        XCTAssertFalse(tracker.addCompletedEntries(0))
        XCTAssertEqual(tracker.completedEntries, 2)
        XCTAssertFalse(tracker.isThirdEntrySent)
    }
}
