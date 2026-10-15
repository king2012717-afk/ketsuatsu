import CoreGraphics
import XCTest
@testable import Ketsuatsu

/// 血圧計の表示レイアウトを模した OCR 結果で、読み取りロジックを検証する。
final class BPTextParserTests: XCTestCase {

    // MARK: - ヘルパー

    /// 画面の上からの位置（0 = 一番上）で行を作る。Vision の座標は原点が左下なので変換する。
    private func line(
        _ text: String,
        top: CGFloat,
        height: CGFloat = 0.12,
        x: CGFloat = 0.1,
        width: CGFloat = 0.8,
        confidence: Float = 0.9
    ) -> OCRTextItem {
        OCRTextItem(
            text: text,
            boundingBox: CGRect(x: x, y: 1 - top - height, width: width, height: height),
            confidence: confidence
        )
    }

    // MARK: - ラベルつきの表示

    func testParsesLabeledDisplay() {
        let items = [
            line("SYS 128", top: 0.10),
            line("DIA 82", top: 0.35),
            line("PULSE 70", top: 0.60, height: 0.08)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
        XCTAssertEqual(result.pulse, 70)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testParsesJapaneseLabels() {
        let items = [
            line("最高 135", top: 0.10),
            line("最低 88", top: 0.35),
            line("脈拍 62", top: 0.60, height: 0.08)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 135)
        XCTAssertEqual(result.diastolic, 88)
        XCTAssertEqual(result.pulse, 62)
    }

    /// ラベルだけの行と数値だけの行が分かれている表示。
    func testParsesLabelsOnSeparateLine() {
        let items = [
            line("SYS DIA", top: 0.10, height: 0.06),
            line("128  82", top: 0.25, height: 0.20)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
    }

    /// ラベルが取り違えられていても、上下の大小関係で補正する。
    func testSwapsWhenLabelsAreInverted() {
        let items = [
            line("SYS 82", top: 0.10),
            line("DIA 128", top: 0.35)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
    }

    // MARK: - ラベルなしの表示

    func testParsesNumbersByLayout() {
        let items = [
            line("128", top: 0.10, height: 0.20),
            line("82", top: 0.35, height: 0.20),
            line("70", top: 0.65, height: 0.10)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
        XCTAssertEqual(result.pulse, 70)
    }

    func testParsesSlashNotation() {
        let result = BPTextParser.parse([line("128/82", top: 0.2)])

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
        XCTAssertNil(result.pulse)
    }

    func testParsesSlashNotationWithPulse() {
        let result = BPTextParser.parse([line("128/82/70", top: 0.2)])

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
        XCTAssertEqual(result.pulse, 70)
    }

    // MARK: - 紛らわしい表示

    func testIgnoresDateAndTime() {
        let items = [
            line("2024/10/25", top: 0.02, height: 0.05),
            line("07:35", top: 0.09, height: 0.05),
            line("128", top: 0.25, height: 0.20),
            line("82", top: 0.50, height: 0.20)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
        XCTAssertNil(result.pulse, "日付や時刻の数字を脈拍として拾ってはいけない")
    }

    func testIgnoresUnitSuffix() {
        let items = [
            line("SYS 128 mmHg", top: 0.10),
            line("DIA 82 mmHg", top: 0.35)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
    }

    func testRejectsImplausibleValues() {
        let items = [
            line("999", top: 0.10, height: 0.20),
            line("888", top: 0.40, height: 0.20)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertFalse(result.hasBloodPressure)
        XCTAssertEqual(result.confidence, 0)
    }

    func testEmptyInput() {
        XCTAssertEqual(BPTextParser.parse([]), .empty)
    }

    // MARK: - 文字の解釈

    func testNumericValueHandlesConfusedCharacters() {
        XCTAssertEqual(BPTextParser.numericValue(of: "128"), 128)
        XCTAssertEqual(BPTextParser.numericValue(of: "L28"), 128)
        XCTAssertEqual(BPTextParser.numericValue(of: "1O5"), 105)
        XCTAssertEqual(BPTextParser.numericValue(of: "128MMHG"), 128)
        XCTAssertNil(BPTextParser.numericValue(of: "SOS"), "数字を含まない語は数値にしない")
        XCTAssertNil(BPTextParser.numericValue(of: "1234"), "4 桁は血圧の値として扱わない")
    }

    func testNormalizeConvertsFullWidth() {
        XCTAssertEqual(BPTextParser.normalize("１２８"), "128")
        XCTAssertEqual(BPTextParser.normalize("sys"), "SYS")
    }

    func testSlashSeparatedValues() {
        XCTAssertEqual(BPTextParser.slashSeparatedValues(in: "128/82"), [128, 82])
        XCTAssertNil(BPTextParser.slashSeparatedValues(in: "128"))
        XCTAssertNil(BPTextParser.slashSeparatedValues(in: "AB/CD"))
    }

    func testMasksDateAndTime() {
        func isBlank(_ text: String) -> Bool { BPTextParser.maskDateAndTime(text).allSatisfy(\.isWhitespace) }
        XCTAssertTrue(isBlank("2024/10/25"))
        XCTAssertTrue(isBlank("07:35"))
        XCTAssertTrue(isBlank("10月25日"))
        XCTAssertTrue(isBlank("10/25"))
        XCTAssertEqual(BPTextParser.maskDateAndTime("128/82"), "128/82", "血圧の表記は日付とみなさない")
        XCTAssertEqual(BPTextParser.maskDateAndTime("SYS 128"), "SYS 128")
        XCTAssertEqual(BPTextParser.maskDateAndTime("72 0:00"), "72     ", "時刻だけを消し、文字の位置は保つ")
        XCTAssertEqual(BPTextParser.maskDateAndTime("72BPM"), "72BPM", "BPM の PM を午後と取り違えない")
    }

    // MARK: - 実機の表示で起きやすいこと

    /// 脈拍と時刻が同じ段に並ぶ機種（Omron M7 など）。行ごと捨てると脈拍が消える。
    func testKeepsPulseOnSameLineAsClock() {
        let items = [
            line("SYS", top: 0.27, height: 0.04, x: 0.02, width: 0.1),
            line("105", top: 0.22, height: 0.20, x: 0.3, width: 0.4),
            line("DIA", top: 0.46, height: 0.04, x: 0.02, width: 0.1),
            line("72", top: 0.44, height: 0.12, x: 0.38, width: 0.2),
            line("PULSE", top: 0.67, height: 0.04, x: 0.0, width: 0.15),
            line("74 0:00", top: 0.64, height: 0.08, x: 0.33, width: 0.45)
        ]

        let result = BPTextParser.parse(items, aspectRatio: 0.75)

        XCTAssertEqual(result.systolic, 105)
        XCTAssertEqual(result.diastolic, 72)
        XCTAssertEqual(result.pulse, 74)
    }

    /// 本体に印字されたラベルが縦に並ぶ表示で、収縮期と拡張期が読めなかった場合。
    /// 脈拍の段の数値を収縮期として拾ってはいけない。
    func testStackedLabelsDoNotTakeNumbersFromOtherRows() {
        let items = [
            line("SYS", top: 0.27, height: 0.04, x: 0.02, width: 0.1),
            line("DIA", top: 0.48, height: 0.04, x: 0.02, width: 0.1),
            line("PULSE", top: 0.71, height: 0.04, x: 0.0, width: 0.15),
            line("65", top: 0.68, height: 0.12, x: 0.4, width: 0.2)
        ]

        let result = BPTextParser.parse(items, aspectRatio: 0.75)

        XCTAssertNil(result.systolic)
        XCTAssertNil(result.diastolic)
        XCTAssertEqual(result.pulse, 65)
    }

    /// 7 セグメントの「1」の前後にすき間があり、OCR が「13」「1」に分けた場合。
    func testMergesDigitsSplitAroundOne() {
        let items = [
            line("13", top: 0.20, height: 0.15, x: 0.30, width: 0.20),
            line("1", top: 0.20, height: 0.15, x: 0.58, width: 0.04),
            line("88", top: 0.40, height: 0.15, x: 0.40, width: 0.22),
            line("77", top: 0.60, height: 0.08, x: 0.50, width: 0.12)
        ]

        let result = BPTextParser.parse(items, aspectRatio: 0.75)

        XCTAssertEqual(result.systolic, 131)
        XCTAssertEqual(result.diastolic, 88)
        XCTAssertEqual(result.pulse, 77)
    }

    /// 別々の値が横に並ぶ表示はつなげない。
    func testDoesNotMergeSeparateValuesOnSameRow() {
        let items = [line("128 82", top: 0.30, height: 0.15)]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
    }

    /// 先頭の「1」が読み落とされて「117」が「17」になった場合。脈拍と組ませず「1」を補う。
    func testRecoversMissingLeadingOne() {
        let items = [
            line("17", top: 0.20, height: 0.18, x: 0.45, width: 0.2),
            line("81", top: 0.42, height: 0.18, x: 0.40, width: 0.25),
            line("56", top: 0.68, height: 0.09, x: 0.40, width: 0.15)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 117)
        XCTAssertEqual(result.diastolic, 81)
        XCTAssertEqual(result.pulse, 56)
        XCTAssertTrue(result.explanation.contains("1"), "補ったことを説明に含める")
    }

    /// 本当に 2 桁の収縮期（低めの血圧）は、そのまま読む。
    func testKeepsGenuineTwoDigitSystolic() {
        let items = [
            line("98", top: 0.20, height: 0.18, x: 0.40, width: 0.25),
            line("62", top: 0.42, height: 0.18, x: 0.40, width: 0.25),
            line("70", top: 0.68, height: 0.09, x: 0.40, width: 0.15)
        ]

        let result = BPTextParser.parse(items)

        XCTAssertEqual(result.systolic, 98)
        XCTAssertEqual(result.diastolic, 62)
    }

    func testFieldDetection() {
        XCTAssertEqual(BPTextParser.field(for: "SYS"), .systolic)
        XCTAssertEqual(BPTextParser.field(for: "SYSTOLIC"), .systolic)
        XCTAssertEqual(BPTextParser.field(for: "DIA"), .diastolic)
        XCTAssertEqual(BPTextParser.field(for: "PULSE"), .pulse)
        XCTAssertEqual(BPTextParser.field(for: "脈拍"), .pulse)
        XCTAssertNil(BPTextParser.field(for: "128"))
    }
}
