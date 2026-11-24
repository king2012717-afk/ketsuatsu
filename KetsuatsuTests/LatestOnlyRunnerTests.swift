import XCTest
@testable import Ketsuatsu

final class LatestOnlyRunnerTests: XCTestCase {

    /// 記録を残す入れ物（処理の中から書き込むため、参照で持つ）。
    private final class Log {
        var entries: [String] = []
    }

    /// 合図があるまで止まる処理を作るための門。
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
    }

    /// 実行中に続けて要求が来たら、実行中のものが終わってから、最後の要求だけを実行する。
    /// 途中の要求は実行しない（最後の要求が最新の状態で作り直すので不要）。
    @MainActor
    func testRunsOneAtATimeAndOnlyTheLatestWaitingRequest() async {
        let runner = LatestOnlyRunner()
        let log = Log(), gate = Gate()

        let first = runner.enqueue {
            log.entries.append("1 開始")
            await gate.wait()
            log.entries.append("1 終了")
        }
        await waitUntil { !log.entries.isEmpty }

        // 1 が動いている間に、2 と 3 が来る。
        let second = runner.enqueue { log.entries.append("2") }
        let third = runner.enqueue {
            log.entries.append("3 開始")
            await Task.yield()
            log.entries.append("3 終了")
        }
        XCTAssertEqual(log.entries, ["1 開始"], "前の実行が終わるまで、次は始まらない")

        gate.open()
        await first.value
        await second.value
        await third.value

        XCTAssertEqual(log.entries, ["1 開始", "1 終了", "3 開始", "3 終了"])
    }

    /// 間を置いた要求は、それぞれ実行する。
    @MainActor
    func testRunsEachRequestWhenNotOverlapping() async {
        let runner = LatestOnlyRunner()
        let log = Log()

        await runner.run { log.entries.append("1") }
        await runner.run { log.entries.append("2") }

        XCTAssertEqual(log.entries, ["1", "2"])
    }

    /// まだ何も始まっていないうちに続けて要求したときは、最後の 1 回だけ実行する。
    @MainActor
    func testCoalescesRequestsMadeBeforeAnyStarts() async {
        let runner = LatestOnlyRunner()
        let log = Log()

        let tasks = (1...5).map { index in runner.enqueue { log.entries.append("\(index)") } }
        for task in tasks { await task.value }

        XCTAssertEqual(log.entries, ["5"])
    }
}
