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

    // MARK: - 形から読んだ結果の優先

    /// 文字認識が目盛りの数字を値として拾い、読み直しても同じ誤りをした場合（2026-11-21 の実例）。
    func testPrefersCleanShapeReadingOverRepeatedTextMisreading() {
        let shape = result(120, 70, 60, confidence: 0.9)
        let preferred = BPReadingCombiner.preferringShapeReading(shape, over: [
            result(120, 85, 60, confidence: 0.83),
            result(120, 85, 60, confidence: 0.8)
        ])

        XCTAssertEqual(preferred?.systolic, 120)
        XCTAssertEqual(preferred?.diastolic, 70)
        XCTAssertEqual(preferred?.pulse, 60)
    }

    func testShapeReadingGainsConfidenceWhenTextAgrees() {
        let shape = result(120, 70, 60, confidence: 0.9)
        let preferred = BPReadingCombiner.preferringShapeReading(shape, over: [result(120, 70, confidence: 0.6)])

        XCTAssertEqual(preferred?.confidence ?? 0, 0.95, accuracy: 0.001)
    }

    /// 脈拍が読めなかった・判定がきわどいなど、確度が低いときは優先しない（通常どおり読み比べる）。
    func testDoesNotPreferUncertainShapeReading() {
        XCTAssertNil(BPReadingCombiner.preferringShapeReading(result(120, 70, confidence: 0.82), over: []))
    }

    /// 文字認識がラベルつきで 3 つともはっきり読み、違う値を出しているときは優先しない。
    func testDoesNotPreferShapeReadingOverStrongTextReading() {
        let shape = result(120, 70, 60, confidence: 0.9)
        XCTAssertNil(BPReadingCombiner.preferringShapeReading(shape, over: [result(126, 78, 60, confidence: 0.95)]))
        XCTAssertNotNil(BPReadingCombiner.preferringShapeReading(shape, over: [result(120, 70, 60, confidence: 0.95)]))
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
