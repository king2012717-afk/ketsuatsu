import XCTest
@testable import Ketsuatsu
#if canImport(UIKit)
import UIKit
#endif

final class SegmentDisplayReaderTests: XCTestCase {

    // MARK: - 合成した液晶表示

    /// 印字ラベルのない血圧計の表示を描く。明るさ・斜体・大きさを変えられる。
    private struct Canvas {
        var size: Int
        var pixels: [UInt8]
        var digit: UInt8 = 50
        /// 斜体の傾き（上へ行くほど右へずれる量。高さに対する割合）。
        var slant = 0.0

        /// - Parameters:
        ///   - scale: 600 画素四方を 1 とした大きさ
        init(scale: Double = 1, body: UInt8 = 225, display: UInt8 = 175) {
            size = Int(600 * scale)
            pixels = [UInt8](repeating: body, count: size * size)
            self.scale = scale
            fill(x: 180, y: 40, width: 320, height: 520, value: display)
        }

        private var scale: Double

        private func scaled(_ value: Int) -> Int { Int((Double(value) * scale).rounded()) }

        /// 600 画素四方の座標で長方形を塗る。
        mutating func fill(x: Int, y: Int, width: Int, height: Int, value: UInt8, slantFrom bottom: Int? = nil) {
            let x0 = scaled(x), y0 = scaled(y), x1 = scaled(x + width), y1 = scaled(y + height)
            for yy in max(0, y0)..<min(size, y1) {
                let shift = bottom.map { Int((slant * Double(scaled($0) - yy)).rounded()) } ?? 0
                for xx in max(0, x0 + shift)..<min(size, x1 + shift) {
                    pixels[yy * size + xx] = value
                }
            }
        }

        /// 右端をそろえて数字を描く。`shortLeadingOne` のときは、先頭の「1」を低く、離して描く。
        mutating func draw(_ text: String, rightEdge: Int, top: Int, height h: Int, shortLeadingOne: Bool = false) {
            let cell = Int(Double(h) * 0.55), spacing = Int(Double(h) * 0.25)
            var x = rightEdge - text.count * cell - (text.count - 1) * spacing
            for (index, character) in text.enumerated() {
                if shortLeadingOne, index == 0, character == "1" {
                    let short = Int(Double(h) * 0.8)
                    drawDigit(1, x: x - spacing / 2, y: top + (h - short) / 2, cell: cell, height: short)
                } else {
                    drawDigit(Int(String(character))!, x: x, y: top, cell: cell, height: h)
                }
                x += cell + spacing
            }
        }

        /// 実機の液晶に近づけるため、縦のセグメントは中央で切れ目を入れる。
        private mutating func drawDigit(_ digit: Int, x: Int, y: Int, cell: Int, height h: Int) {
            let t = max(3, h * 12 / 100), gap = max(1, h * 3 / 100), half = h / 2
            let on: [Int: String] = [0: "abcdef", 1: "bc", 2: "abdeg", 3: "abcdg", 4: "bcfg",
                                     5: "acdfg", 6: "acdefg", 7: "abc", 8: "abcdefg", 9: "abcdfg"]
            let vertical = half - 2 * gap, bottom = y + h
            for segment in on[digit]! {
                switch segment {
                case "a": fill(x: x + t / 2, y: y, width: cell - t, height: t, value: self.digit, slantFrom: bottom)
                case "b": fill(x: x + cell - t, y: y + gap, width: t, height: vertical, value: self.digit, slantFrom: bottom)
                case "c": fill(x: x + cell - t, y: y + half + gap, width: t, height: vertical, value: self.digit, slantFrom: bottom)
                case "d": fill(x: x + t / 2, y: y + h - t, width: cell - t, height: t, value: self.digit, slantFrom: bottom)
                case "e": fill(x: x, y: y + half + gap, width: t, height: vertical, value: self.digit, slantFrom: bottom)
                case "f": fill(x: x, y: y + gap, width: t, height: vertical, value: self.digit, slantFrom: bottom)
                default: fill(x: x + t + 1, y: y + half - t / 2, width: cell - 2 * t - 2, height: t, value: self.digit, slantFrom: bottom)
                }
            }
        }

        /// 上 128・下 82・脈拍 70 の標準的な並び。
        mutating func drawStandardReading() {
            draw("128", rightEdge: 470, top: 90, height: 120)
            draw("82", rightEdge: 470, top: 250, height: 120)
            draw("70", rightEdge: 470, top: 420, height: 70)
        }

        /// 画像の下側 `fraction` を影にする（明るさを `factor` 倍）。
        mutating func shade(below fraction: Double, factor: Double) {
            for y in Int(Double(size) * fraction)..<size {
                for x in 0..<size {
                    pixels[y * size + x] = UInt8(Double(pixels[y * size + x]) * factor)
                }
            }
        }

        var image: GrayImage { GrayImage(width: size, height: size, pixels: pixels) }
    }

    private func reading(_ systolic: Int, _ diastolic: Int, _ pulse: Int?) -> [Int?] {
        [systolic, diastolic, pulse]
    }

    private func values(_ reading: SegmentDisplayReader.Reading?) -> [Int?]? {
        reading.map { [$0.systolic, $0.diastolic, $0.pulse] }
    }

    /// 印字ラベルがまったくなくても、数字の並びだけで上・下・脈拍を読む。
    func testReadsDisplayWithoutLabels() {
        var canvas = Canvas()
        canvas.drawStandardReading()

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(128, 82, 70))
    }

    func testReadsEveryDigit() {
        var canvas = Canvas()
        canvas.draw("234", rightEdge: 470, top: 90, height: 120)
        canvas.draw("156", rightEdge: 470, top: 250, height: 120)
        canvas.draw("89", rightEdge: 470, top: 420, height: 70)
        let texts = Set(SegmentDisplayReader.rows(in: canvas.image).map(\.text))
        XCTAssertTrue(texts.isSuperset(of: ["234", "156", "89"]), "\(texts)")

        var second = Canvas()
        second.draw("107", rightEdge: 470, top: 90, height: 120)
        second.draw("70", rightEdge: 470, top: 250, height: 120)
        XCTAssertEqual(values(SegmentDisplayReader.read(second.image)), reading(107, 70, nil))
    }

    /// 写真の中で表示が小さくても大きくても読める（縮小の段階を変えて探すため）。
    func testReadsDisplaysOfDifferentSizes() {
        for scale in [0.5, 1.0, 2.5] {
            var canvas = Canvas(scale: scale)
            canvas.drawStandardReading()
            XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(128, 82, 70), "倍率 \(scale)")
        }
    }

    /// バックライトで光る液晶（本体が暗く、液晶が明るい）。
    func testReadsBacklitDisplay() {
        var canvas = Canvas(body: 45, display: 235)
        canvas.digit = 70
        canvas.drawStandardReading()

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(128, 82, 70))
    }

    /// コントラストの低い液晶（数字が薄い）。
    func testReadsLowContrastDisplay() {
        var canvas = Canvas(body: 200, display: 150)
        canvas.digit = 105
        canvas.drawStandardReading()

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(128, 82, 70))
    }

    /// 数字が斜体の機種。
    func testReadsItalicDigits() {
        var canvas = Canvas()
        canvas.slant = 0.12
        canvas.draw("136", rightEdge: 450, top: 90, height: 120)
        canvas.draw("90", rightEdge: 450, top: 250, height: 120)
        canvas.draw("61", rightEdge: 450, top: 420, height: 70)

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(136, 90, 61))
    }

    /// 表示の途中から影がかかっている写真。
    func testReadsThroughShadow() {
        var canvas = Canvas()
        canvas.drawStandardReading()
        canvas.shade(below: 0.52, factor: 0.45)

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(128, 82, 70))
    }

    /// 先頭の「1」だけ背が低く、離れて表示される機種。「1」を落として下の血圧と脈拍を上下と取り違えない。
    func testReadsShortLeadingOne() {
        var canvas = Canvas()
        canvas.draw("136", rightEdge: 470, top: 90, height: 120, shortLeadingOne: true)
        canvas.draw("90", rightEdge: 470, top: 250, height: 120)
        canvas.draw("61", rightEdge: 470, top: 410, height: 100)

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(136, 90, 61))
    }

    /// 上下の段がほとんどくっついている機種（すき間は数字の高さの 5%）。
    func testReadsRowsThatAlmostTouch() {
        var canvas = Canvas()
        canvas.draw("128", rightEdge: 470, top: 90, height: 120)
        canvas.draw("97", rightEdge: 470, top: 216, height: 120)
        canvas.draw("70", rightEdge: 470, top: 370, height: 80)

        XCTAssertEqual(values(SegmentDisplayReader.read(canvas.image)), reading(128, 97, 70))
    }

    func testReturnsNothingForBlankOrTinyImages() {
        XCTAssertNil(SegmentDisplayReader.read(Canvas().image))
        XCTAssertNil(SegmentDisplayReader.read(GrayImage(width: 20, height: 20, pixels: [UInt8](repeating: 128, count: 400))))
    }

    /// 1 段しかない表示（体温計・時計など）は血圧として読まない。
    func testReturnsNothingForSingleRow() {
        var canvas = Canvas()
        canvas.draw("128", rightEdge: 470, top: 90, height: 120)

        XCTAssertNil(SegmentDisplayReader.read(canvas.image))
    }

    // MARK: - 段の選び方

    private func row(_ text: String, x: Double = 100, y: Double, height: Double = 100, margin: Double = 0.25) -> SegmentDisplayReader.Row {
        let width = Double(text.count) * height * 0.7
        return SegmentDisplayReader.Row(
            text: text,
            box: .init(x: x + 300 - width, y: y, width: width, height: height),
            digitHeight: height, margin: margin, isPartial: false
        )
    }

    func testChoosesStackedRowsAndPulseBelow() {
        let chosen = SegmentDisplayReader.choose([
            row("70", y: 360, height: 60), row("82", y: 230), row("128", y: 100),
        ])
        XCTAssertEqual(values(chosen), reading(128, 82, 70))
    }

    /// 上の段の先頭の「1」を読み落として「36」になったとき、その下の 90 と 61 を上下として出さない。
    func testDoesNotSkipAnUnreadableTopRow() {
        let chosen = SegmentDisplayReader.choose([
            row("36", y: 100), row("90", y: 230), row("61", y: 360, height: 82),
        ])
        XCTAssertNil(chosen)
    }

    /// 判定がきわどい段（7 セグメントでない文字を無理に当てはめたもの）は採用しない。
    func testIgnoresRowsWithoutMargin() {
        let chosen = SegmentDisplayReader.choose([
            row("116", y: 100), row("38", y: 230, margin: 0.02),
        ])
        XCTAssertNil(chosen)
    }

    func testRejectsImplausiblePairs() {
        XCTAssertNil(SegmentDisplayReader.choose([row("82", y: 100), row("128", y: 230)]))   // 上下が逆
        XCTAssertNil(SegmentDisplayReader.choose([row("128", y: 100), row("82", y: 500)]))   // 離れすぎ
        XCTAssertNil(SegmentDisplayReader.choose([row("128", y: 100), row("82", y: 230, height: 50)]))   // 大きさが違う
    }

    func testResultConfidenceReflectsPulseAndMargin() {
        let full = BPParseResult(SegmentDisplayReader.Reading(systolic: 128, diastolic: 82, pulse: 70, margin: 0.25))
        let withoutPulse = BPParseResult(SegmentDisplayReader.Reading(systolic: 128, diastolic: 82, pulse: nil, margin: 0.25))
        let borderline = BPParseResult(SegmentDisplayReader.Reading(systolic: 128, diastolic: 82, pulse: 70, margin: 0.06))

        XCTAssertEqual(full.systolic, 128)
        XCTAssertEqual(full.diastolic, 82)
        XCTAssertEqual(full.pulse, 70)
        XCTAssertGreaterThanOrEqual(full.confidence, 0.85)   // 確認の注意書きを出さない確度
        XCTAssertLessThan(withoutPulse.confidence, 0.85)
        XCTAssertLessThan(borderline.confidence, 0.85)
    }

    /// 文字認識が誤読しても、形から読んだ値と読み直しの値が一致すればそちらを採用する。
    func testCombinerPrefersAgreementWithShapeReading() {
        let misread = BPParseResult(systolic: 181, diastolic: 88, pulse: nil, confidence: 0.9, explanation: "")
        let shape = BPParseResult(SegmentDisplayReader.Reading(systolic: 131, diastolic: 88, pulse: 77, margin: 0.25))
        let retry = BPParseResult(systolic: 131, diastolic: 88, pulse: nil, confidence: 0.6, explanation: "")

        let combined = BPReadingCombiner.combine([misread, shape, retry])

        XCTAssertEqual(combined.systolic, 131)
        XCTAssertEqual(combined.diastolic, 88)
        XCTAssertEqual(combined.pulse, 77)
    }

    // MARK: - 画像処理の部品

    func testSlidingExtremeMatchesBruteForce() {
        var generator = SystemRandomNumberGenerator()
        let width = 37, height = 23
        var plane = SegmentDisplayReader.Plane(width: width, height: height, fill: 0)
        for i in plane.pixels.indices { plane.pixels[i] = UInt8.random(in: 0...255, using: &generator) }

        for (before, after, takeMax) in [(2, 2, true), (6, 6, false), (1, 0, true), (0, 1, false), (40, 40, true)] {
            let fast = plane.extreme(before: before, after: after, takeMax: takeMax)
            for y in 0..<height {
                for x in 0..<width {
                    var expected: UInt8 = takeMax ? 0 : 255
                    for yy in max(0, y - before)...min(height - 1, y + after) {
                        for xx in max(0, x - before)...min(width - 1, x + after) {
                            let value = plane.pixels[yy * width + xx]
                            expected = takeMax ? max(expected, value) : min(expected, value)
                        }
                    }
                    XCTAssertEqual(fast.pixels[y * width + x], expected, "(\(x), \(y)) 窓 \(before)/\(after)")
                }
            }
        }
    }

    func testResizeAveragesAreas() {
        // 左半分が 0、右半分が 200 の 8 × 4 を、長辺 4 に縮める。
        var plane = SegmentDisplayReader.Plane(width: 8, height: 4, fill: 0)
        for y in 0..<4 { for x in 4..<8 { plane.pixels[y * 8 + x] = 200 } }

        let small = plane.resized(longSide: 4)

        XCTAssertEqual(small.width, 4)
        XCTAssertEqual(small.height, 2)
        XCTAssertEqual(small.pixels, [0, 0, 200, 200, 0, 0, 200, 200])
        XCTAssertEqual(plane.resized(longSide: 100).pixels, plane.pixels)   // 拡大はしない
    }

    func testJoinsVerticalPiecesOfOne() {
        // 「1」の上下の棒（すき間 2 画素）は 1 つの塊にする。離れた塊はそのまま。
        let pieces = [
            SegmentDisplayReader.Box(x: 50, y: 10, w: 5, h: 14),
            SegmentDisplayReader.Box(x: 50, y: 26, w: 5, h: 14),
            SegmentDisplayReader.Box(x: 120, y: 10, w: 5, h: 14),
        ]

        let joined = SegmentDisplayReader.joinVerticalPieces(pieces)

        XCTAssertEqual(joined.count, 2)
        XCTAssertTrue(joined.contains(SegmentDisplayReader.Box(x: 50, y: 10, w: 5, h: 30)))
    }

    // MARK: - 実物の写真

    #if canImport(UIKit)
    private func fixture(_ name: String) throws -> GrayImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"))
        let cgImage = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        return try XCTUnwrap(GrayImage(cgImage: cgImage))
    }

    /// 印字ラベルの位置を渡さなくても読める（Fixtures/README.md 参照）。
    func testReadsRealDisplayPhotoWithoutLabels() throws {
        let reading = SegmentDisplayReader.read(try fixture("boots_display_131_88_77"))

        XCTAssertEqual(values(reading), self.reading(131, 88, 77))
    }

    /// バックライトで光り、SYS／DIA が液晶の中に表示され、上に時計がある機種。
    func testReadsRealBacklitDisplayPhoto() throws {
        let reading = SegmentDisplayReader.read(try fixture("backlit_display_126_81_81"))

        XCTAssertEqual(values(reading), self.reading(126, 81, 81))
    }
    #endif
}
