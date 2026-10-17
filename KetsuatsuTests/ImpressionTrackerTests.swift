import CoreGraphics
import XCTest
@testable import Ketsuatsu

final class ImpressionTrackerTests: XCTestCase {

    func testLogsOnlyWhenHalfVisible() {
        var tracker = ImpressionTracker()

        XCTAssertFalse(tracker.update(id: "book", visibleFraction: 0.3), "半分未満では送らない")
        XCTAssertTrue(tracker.update(id: "book", visibleFraction: 0.5))
        XCTAssertFalse(tracker.update(id: "book", visibleFraction: 1.0), "前面にいる間は 1 回まで")
    }

    func testScrollingAwayAndBackDoesNotLogAgain() {
        var tracker = ImpressionTracker()
        _ = tracker.update(id: "book", visibleFraction: 1.0)

        XCTAssertFalse(tracker.update(id: "book", visibleFraction: 0))
        XCTAssertFalse(tracker.update(id: "book", visibleFraction: 1.0))
    }

    func testCountsAgainAfterReturningFromBackground() {
        var tracker = ImpressionTracker()
        _ = tracker.update(id: "book", visibleFraction: 1.0)
        _ = tracker.update(id: "neko", visibleFraction: 0.8)
        _ = tracker.update(id: "neko", visibleFraction: 0)   // 画面から外れた

        tracker.didEnterBackground()
        XCTAssertEqual(tracker.didBecomeActive(), ["book"], "前面に戻った時点で見えている行だけを送る")
        XCTAssertEqual(tracker.didBecomeActive(), [], "続けて呼んでも重ねて送らない")
        XCTAssertTrue(tracker.update(id: "neko", visibleFraction: 1.0), "見えていなかった行は、見えたときに送る")
    }

    func testVisibleFraction() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)

        XCTAssertEqual(ImpressionTracker.visibleFraction(of: CGRect(x: 0, y: 100, width: 400, height: 60), in: screen), 1)
        XCTAssertEqual(ImpressionTracker.visibleFraction(of: CGRect(x: 0, y: 770, width: 400, height: 60), in: screen), 0.5)
        XCTAssertEqual(ImpressionTracker.visibleFraction(of: CGRect(x: 0, y: 900, width: 400, height: 60), in: screen), 0)
        XCTAssertEqual(ImpressionTracker.visibleFraction(of: CGRect(x: 0, y: 100, width: 400, height: 0), in: screen), 0)
    }
}
