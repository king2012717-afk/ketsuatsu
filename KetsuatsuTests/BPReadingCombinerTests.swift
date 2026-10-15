import XCTest
@testable import Ketsuatsu

final class BPReadingCombinerTests: XCTestCase {

    private func result(_ s: Int?, _ d: Int?, _ p: Int? = nil, confidence: Double) -> BPParseResult {
        BPParseResult(systolic: s, diastolic: d, pulse: p, confidence: confidence, explanation: "")
    }

    func testPrefersValuesThatAgreeAcrossReadings() {
        let combined = BPReadingCombiner.combine([
            result(171, 81, confidence: 0.9),
            result(117, 81, 56, confidence: 0.6),
            result(117, 81, confidence: 0.8)
        ])

        XCTAssertEqual(combined.systolic, 117)
        XCTAssertEqual(combined.diastolic, 81)
        XCTAssertEqual(combined.pulse, 56)
        XCTAssertGreaterThan(combined.confidence, 0.8)
    }

    func testFallsBackToMostConfidentCompleteReading() {
        let combined = BPReadingCombiner.combine([
            result(131, 88, confidence: 0.85),
            result(nil, nil, 77, confidence: 0.0),
            result(31, nil, confidence: 0.3)
        ])

        XCTAssertEqual(combined.systolic, 131)
        XCTAssertEqual(combined.diastolic, 88)
        XCTAssertEqual(combined.pulse, 77)
    }

    func testCombinesPartialReadingsWhenConsistent() {
        let combined = BPReadingCombiner.combine([
            result(117, nil, 56, confidence: 0.3),
            result(nil, 81, confidence: 0.25)
        ])

        XCTAssertEqual(combined.systolic, 117)
        XCTAssertEqual(combined.diastolic, 81)
        XCTAssertEqual(combined.pulse, 56)
    }

    func testDoesNotCombineInconsistentPartialReadings() {
        let combined = BPReadingCombiner.combine([
            result(70, nil, confidence: 0.3),
            result(nil, 81, confidence: 0.25)
        ])

        XCTAssertFalse(combined.hasBloodPressure, "上が下より小さい組み合わせは作らない")
    }

    func testDetectsAgreement() {
        XCTAssertTrue(BPReadingCombiner.hasAgreement([
            result(117, 81, confidence: 0.5), result(nil, nil, confidence: 0), result(117, 81, 56, confidence: 0.9)
        ]))
        XCTAssertFalse(BPReadingCombiner.hasAgreement([
            result(117, 81, confidence: 0.5), result(171, 81, confidence: 0.9)
        ]))
        XCTAssertFalse(BPReadingCombiner.hasAgreement([result(117, 81, confidence: 0.5)]))
    }

    func testEmptyReadings() {
        XCTAssertEqual(BPReadingCombiner.combine([.empty, .empty]), .empty)
        XCTAssertEqual(BPReadingCombiner.combine([]), .empty)
    }
}
