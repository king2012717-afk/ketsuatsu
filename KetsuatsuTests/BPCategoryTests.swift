import XCTest
@testable import Ketsuatsu

/// 日本高血圧学会ガイドライン（2019）の区分に沿っているかを確認する。
final class BPCategoryTests: XCTestCase {

    func testHomeStandardBoundaries() {
        XCTAssertEqual(BPCategory.classify(systolic: 110, diastolic: 70, standard: .home), .normal)
        XCTAssertEqual(BPCategory.classify(systolic: 115, diastolic: 70, standard: .home), .elevated)
        XCTAssertEqual(BPCategory.classify(systolic: 125, diastolic: 70, standard: .home), .high)
        XCTAssertEqual(BPCategory.classify(systolic: 110, diastolic: 78, standard: .home), .high)
        XCTAssertEqual(BPCategory.classify(systolic: 135, diastolic: 80, standard: .home), .grade1)
        XCTAssertEqual(BPCategory.classify(systolic: 130, diastolic: 86, standard: .home), .grade1)
        XCTAssertEqual(BPCategory.classify(systolic: 150, diastolic: 88, standard: .home), .grade2)
        XCTAssertEqual(BPCategory.classify(systolic: 165, diastolic: 95, standard: .home), .grade3)
        XCTAssertEqual(BPCategory.classify(systolic: 130, diastolic: 105, standard: .home), .grade3)
    }

    func testOfficeStandardBoundaries() {
        XCTAssertEqual(BPCategory.classify(systolic: 118, diastolic: 76, standard: .office), .normal)
        XCTAssertEqual(BPCategory.classify(systolic: 122, diastolic: 76, standard: .office), .elevated)
        XCTAssertEqual(BPCategory.classify(systolic: 132, diastolic: 76, standard: .office), .high)
        XCTAssertEqual(BPCategory.classify(systolic: 142, diastolic: 88, standard: .office), .grade1)
        XCTAssertEqual(BPCategory.classify(systolic: 165, diastolic: 95, standard: .office), .grade2)
        XCTAssertEqual(BPCategory.classify(systolic: 185, diastolic: 95, standard: .office), .grade3)
    }

    /// 同じ値でも基準が変われば判定は変わる（家庭血圧のほうが 5mmHg 厳しい）。
    func testStandardChangesResult() {
        XCTAssertEqual(BPCategory.classify(systolic: 136, diastolic: 84, standard: .home), .grade1)
        XCTAssertEqual(BPCategory.classify(systolic: 136, diastolic: 84, standard: .office), .high)
    }

    func testLowBloodPressure() {
        XCTAssertEqual(BPCategory.classify(systolic: 85, diastolic: 55, standard: .home), .low)
        XCTAssertFalse(BPCategory.classify(systolic: 85, diastolic: 55, standard: .home).isHypertensive)
    }

    func testHypertensiveFlag() {
        XCTAssertTrue(BPCategory.grade1.isHypertensive)
        XCTAssertTrue(BPCategory.grade3.isHypertensive)
        XCTAssertFalse(BPCategory.high.isHypertensive)
        XCTAssertFalse(BPCategory.normal.isHypertensive)
    }

    func testRecommendedTargets() {
        XCTAssertEqual(BPCategory.hypertensionThreshold(for: .home).systolic, 135)
        XCTAssertEqual(BPCategory.hypertensionThreshold(for: .office).systolic, 140)
    }
}
