import XCTest
@testable import Ketsuatsu

final class PhotoReadingOutcomeTests: XCTestCase {

    private func result(
        _ systolic: Int?, _ diastolic: Int?, _ pulse: Int? = nil,
        confidence: Double = 0.9, reader: BPParseResult.Reader = .text
    ) -> BPParseResult {
        BPParseResult(systolic: systolic, diastolic: diastolic, pulse: pulse, confidence: confidence, explanation: "", reader: reader)
    }

    /// 読み取った値のまま保存された。
    func testUnchangedReadingMatches() {
        let outcome = PhotoReadingOutcome(result: result(120, 70, 60, reader: .shape), systolic: 120, diastolic: 70, pulse: 60)

        XCTAssertEqual(outcome.readResult, .full)
        XCTAssertTrue(outcome.bloodPressureMatched)
        XCTAssertEqual(outcome.pulseMatch, .matched)
        XCTAssertEqual(outcome.reader, .shape)
        XCTAssertEqual(outcome.confidence, .high)
    }

    /// 下の値を手で直して保存した（目盛りの 85 を拾った実例）。
    func testCorrectedBloodPressureDoesNotMatch() {
        let outcome = PhotoReadingOutcome(result: result(120, 85, 60, confidence: 0.83), systolic: 120, diastolic: 70, pulse: 60)

        XCTAssertEqual(outcome.readResult, .full)
        XCTAssertFalse(outcome.bloodPressureMatched)
        XCTAssertEqual(outcome.pulseMatch, .matched)
        XCTAssertEqual(outcome.reader, .text)
        XCTAssertEqual(outcome.confidence, .low)
    }

    func testPulseCorrectedOrRemoved() {
        XCTAssertEqual(PhotoReadingOutcome(result: result(120, 70, 33), systolic: 120, diastolic: 70, pulse: 60).pulseMatch, .corrected)
        XCTAssertEqual(PhotoReadingOutcome(result: result(120, 70, 33), systolic: 120, diastolic: 70, pulse: nil).pulseMatch, .corrected)
    }

    /// 脈拍を読めなかったときは、あとで手で入れたかどうかを区別しない（脈拍を記録したかどうかを送らないため）。
    func testUnreadPulseDoesNotRevealWhetherPulseWasEntered() {
        let entered = PhotoReadingOutcome(result: result(120, 70), systolic: 120, diastolic: 70, pulse: 60)
        let empty = PhotoReadingOutcome(result: result(120, 70), systolic: 120, diastolic: 70, pulse: nil)

        XCTAssertEqual(entered.readResult, .bloodPressureOnly)
        XCTAssertEqual(entered.pulseMatch, .notRead)
        XCTAssertEqual(entered, empty)
    }

    func testPartialAndFailedReadings() {
        let partial = PhotoReadingOutcome(result: result(120, nil, confidence: 0.3), systolic: 120, diastolic: 70, pulse: nil)
        XCTAssertEqual(partial.readResult, .partial)
        XCTAssertFalse(partial.bloodPressureMatched)

        // 読み取り自体に失敗した（結果なし）場合と、何も読めなかった場合は同じ扱い。
        let failed = PhotoReadingOutcome(result: nil, systolic: 120, diastolic: 70, pulse: 60)
        XCTAssertEqual(failed.readResult, .none)
        XCTAssertFalse(failed.bloodPressureMatched)
        XCTAssertEqual(failed.pulseMatch, .notRead)
        XCTAssertEqual(failed.confidence, .low)
        XCTAssertEqual(failed, PhotoReadingOutcome(result: .empty, systolic: 120, diastolic: 70, pulse: 60))
    }

    /// 計測へ送るのは区分の名前だけ。血圧・脈拍の値はどのパラメータにも入らない。
    func testAnalyticsParametersContainOnlyCategories() {
        let outcome = PhotoReadingOutcome(result: result(137, 91, 64, reader: .shape), systolic: 142, diastolic: 93, pulse: 58)
        let parameters = outcome.analyticsParameters

        XCTAssertEqual(parameters, [
            "read_result": "full",
            "bp_match": "false",
            "pulse_match": "false",
            "reader": "shape",
            "confidence": "high",
        ])
        let allowed: Set<String> = ["full", "bp_only", "partial", "none", "true", "false", "not_read", "shape", "text", "high", "low"]
        XCTAssertTrue(parameters.values.allSatisfy(allowed.contains))
        for value in ["137", "91", "64", "142", "93", "58"] {
            XCTAssertFalse(parameters.values.contains { $0.contains(value) })
        }
    }

    /// 形から読んだ結果には、その印が付く（どちらの読み方が当たっているかを分けて見るため）。
    func testShapeReadingIsMarked() {
        let shape = BPParseResult(SegmentDisplayReader.Reading(systolic: 120, diastolic: 70, pulse: 60, margin: 0.25))
        XCTAssertEqual(shape.reader, .shape)
        XCTAssertEqual(BPParseResult.empty.reader, .text)
        // 優先して採用したときも、印は残る。
        let preferred = BPReadingCombiner.preferringShapeReading(shape, over: [result(120, 85, 60, confidence: 0.83)])
        XCTAssertEqual(preferred?.reader, .shape)
    }
}
