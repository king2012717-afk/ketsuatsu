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

    func testLooksLikeDateLine() {
        XCTAssertTrue(BPTextParser.looksLikeDateLine("2024/10/25"))
        XCTAssertTrue(BPTextParser.looksLikeDateLine("07:35"))
        XCTAssertTrue(BPTextParser.looksLikeDateLine("10月25日"))
        XCTAssertFalse(BPTextParser.looksLikeDateLine("128/82"), "血圧の表記は日付とみなさない")
        XCTAssertFalse(BPTextParser.looksLikeDateLine("SYS 128"))
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
