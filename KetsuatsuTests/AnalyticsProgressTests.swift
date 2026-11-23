import XCTest
@testable import Ketsuatsu

/// 共通設計 v2 の判定ロジックのテスト。先行アプリで起きた不具合（遡及発火・削除後の再発火・二重送信）を再現しないことを確かめる。
final class AnalyticsProgressTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "analytics-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func progress(_ milestones: [Int]) -> AnalyticsProgress {
        AnalyticsProgress(name: "test", milestones: milestones, defaults: defaults)
    }

    // MARK: - 新規ユーザー

    func testNewUserReachesEachMilestoneOnce() {
        let p = progress([1, 2])
        p.establishBaseline(existingCount: 0)
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 1).reached, [1])
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 2).reached, [2])
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 3).reached, [])
        XCTAssertEqual(p.hadExistingData, false)
    }

    // MARK: - 既存ユーザー（遡及発火しない）

    func testExistingUserPastMilestoneNeverFires() {
        let p = progress([3])
        p.establishBaseline(existingCount: 10)
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 11).reached, [])
        XCTAssertEqual(p.hadExistingData, true)
    }

    func testExistingUserBelowMilestoneFiresWhenActuallyReached() {
        let p = progress([3])
        p.establishBaseline(existingCount: 2)
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 3).reached, [3])
    }

    func testBaselineIsRecordedOnlyOnce() {
        let p = progress([3])
        XCTAssertTrue(p.establishBaseline(existingCount: 0))
        // 次回起動時（データが増えていても）基準値は変わらない
        XCTAssertFalse(p.establishBaseline(existingCount: 5))
        XCTAssertEqual(p.count, 0)
    }

    func testMissingBaselineFallsBackToTotalBeforeThisSave() {
        let p = progress([3])
        // 基準値が無いまま保存された：保存後 5 件 → 既存 4 件とみなし、3 は到達済み
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 5).reached, [])
        XCTAssertEqual(p.count, 5)
    }

    // MARK: - 削除・再登録・再起動

    func testDeletionDoesNotRefire() {
        let p = progress([1, 2])
        p.establishBaseline(existingCount: 0)
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 1).reached, [1])
        // 削除して 0 件に戻っても、通算は減らない
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 1).reached, [2])
        XCTAssertEqual(p.recordSuccess(totalAfterSave: 1).reached, [])
    }

    func testSameUnitIsCountedOnce() {
        let p = progress([1, 2])
        p.establishBaseline(existingCount: 0)
        XCTAssertEqual(p.recordSuccess(unit: "isbn-a", totalAfterSave: 1).reached, [1])
        // 同じ本を削除して登録し直しても 2 冊目にはならない
        let again = p.recordSuccess(unit: "isbn-a", totalAfterSave: 1)
        XCTAssertFalse(again.counted)
        XCTAssertEqual(again.reached, [])
        XCTAssertEqual(p.recordSuccess(unit: "isbn-b", totalAfterSave: 2).reached, [2])
    }

    func testExistingUnitsAtBaselineAreNotCountedAgain() {
        let p = progress([3])
        // 今日すでに引いていた既存ユーザーが、同じ日に引き直した
        p.establishBaseline(existingCount: 2, existingUnits: ["2026-10-07"])
        XCTAssertEqual(p.recordSuccess(unit: "2026-10-07", totalAfterSave: 2).reached, [])
        XCTAssertEqual(p.recordSuccess(unit: "2026-10-08", totalAfterSave: 3).reached, [3])
    }

    func testStateSurvivesNewInstance() {
        // 再起動の代わりに、同じ保存先から作り直す
        progress([2]).establishBaseline(existingCount: 0)
        XCTAssertEqual(progress([2]).recordSuccess(totalAfterSave: 1).reached, [])
        XCTAssertEqual(progress([2]).recordSuccess(totalAfterSave: 2).reached, [2])
        XCTAssertEqual(progress([2]).recordSuccess(totalAfterSave: 3).reached, [])
    }

    func testUnitMemoryIsBounded() {
        let p = AnalyticsProgress(name: "bounded", milestones: [100], unitMemory: 2, defaults: defaults)
        p.establishBaseline(existingCount: 0)
        _ = p.recordSuccess(unit: "a", totalAfterSave: 1)
        _ = p.recordSuccess(unit: "b", totalAfterSave: 2)
        _ = p.recordSuccess(unit: "c", totalAfterSave: 3)
        // "a" は記憶から押し出されているので、また数える
        _ = p.recordSuccess(unit: "a", totalAfterSave: 4)
        XCTAssertEqual(p.count, 4)
    }

    // MARK: - 一度だけ

    func testOncePerformsOnlyOnce() {
        var calls = 0
        XCTAssertTrue(AnalyticsOnce.perform("x", defaults: defaults) { calls += 1 })
        XCTAssertFalse(AnalyticsOnce.perform("x", defaults: defaults) { calls += 1 })
        XCTAssertEqual(calls, 1)
    }

    func testOnceMarkDoneSuppresses() {
        AnalyticsOnce.markDone("y", defaults: defaults)
        var called = false
        XCTAssertFalse(AnalyticsOnce.perform("y", defaults: defaults) { called = true })
        XCTAssertFalse(called)
    }

    // MARK: - 購入

    func testTransactionIsClaimedOnce() {
        XCTAssertTrue(AnalyticsTransactionLedger.claim("1000", defaults: defaults))
        XCTAssertFalse(AnalyticsTransactionLedger.claim("1000", defaults: defaults))
        XCTAssertTrue(AnalyticsTransactionLedger.claim("1001", defaults: defaults))
    }
}
