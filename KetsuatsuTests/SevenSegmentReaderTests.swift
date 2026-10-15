import CoreGraphics
import XCTest
@testable import Ketsuatsu
#if canImport(UIKit)
import UIKit
#endif

final class SevenSegmentReaderTests: XCTestCase {

    // MARK: - 合成した液晶表示

    /// 液晶の 7 セグメント表示を描く。セグメント同士は実機と同じく少しすき間をあける。
    private struct DisplayCanvas {
        static let size = 600
        var pixels = [UInt8](repeating: 225, count: size * size)  // 本体（明るい）
        var labelBoxes: [CGRect] = []

        init() {
            fill(x: 180, y: 40, width: 320, height: 520, value: 175)  // 液晶の面
        }

        mutating func fill(x: Int, y: Int, width: Int, height: Int, value: UInt8) {
            for yy in max(0, y)..<min(Self.size, y + height) {
                for xx in max(0, x)..<min(Self.size, x + width) {
                    pixels[yy * Self.size + xx] = value
                }
            }
        }

        /// 本体に印字されたラベルの位置（Vision の正規化座標）を加える。
        mutating func addLabel(top: Int) {
            let box = (x: 40, width: 80, height: 30)
            labelBoxes.append(CGRect(
                x: CGFloat(box.x) / CGFloat(Self.size),
                y: 1 - CGFloat(top + box.height) / CGFloat(Self.size),
                width: CGFloat(box.width) / CGFloat(Self.size),
                height: CGFloat(box.height) / CGFloat(Self.size)
            ))
        }

        /// 右端をそろえて数字を描く。
        mutating func draw(_ text: String, rightEdge: Int, top: Int, height h: Int) {
            let cell = Int(Double(h) * 0.55), spacing = Int(Double(h) * 0.25)
            var x = rightEdge - text.count * cell - (text.count - 1) * spacing
            for character in text {
                drawDigit(Int(String(character))!, x: x, y: top, cell: cell, height: h)
                x += cell + spacing
            }
        }

        /// 実機の液晶に近づけるため、縦のセグメントは中央で切れ目を入れ、上下の端近くまで伸ばす。
        /// 横のセグメントは縦のセグメントの端に重ね、中央の横棒だけは縦と 1 画素離す。
        private mutating func drawDigit(_ digit: Int, x: Int, y: Int, cell: Int, height h: Int) {
            let t = max(3, h * 12 / 100), gap = max(1, h * 3 / 100), half = h / 2
            let on: [Int: String] = [0: "abcdef", 1: "bc", 2: "abdeg", 3: "abcdg", 4: "bcfg",
                                     5: "acdfg", 6: "acdefg", 7: "abc", 8: "abcdefg", 9: "abcdfg"]
            let vertical = half - 2 * gap
            for segment in on[digit]! {
                switch segment {
                case "a": fill(x: x + t / 2, y: y, width: cell - t, height: t, value: 50)
                case "b": fill(x: x + cell - t, y: y + gap, width: t, height: vertical, value: 50)
                case "c": fill(x: x + cell - t, y: y + half + gap, width: t, height: vertical, value: 50)
                case "d": fill(x: x + t / 2, y: y + h - t, width: cell - t, height: t, value: 50)
                case "e": fill(x: x, y: y + half + gap, width: t, height: vertical, value: 50)
                case "f": fill(x: x, y: y + gap, width: t, height: vertical, value: 50)
                default: fill(x: x + t + 1, y: y + half - t / 2, width: cell - 2 * t - 2, height: t, value: 50)
                }
            }
        }

        var image: GrayImage { GrayImage(width: Self.size, height: Self.size, pixels: pixels) }
    }

    private func labelItems(_ canvas: DisplayCanvas, _ names: [String]) -> [OCRTextItem] {
        zip(names, canvas.labelBoxes).map { OCRTextItem(text: $0, boundingBox: $1) }
    }

    func testReadsSyntheticDisplay() {
        var canvas = DisplayCanvas()
        canvas.draw("128", rightEdge: 470, top: 90, height: 120)
        canvas.draw("82", rightEdge: 470, top: 250, height: 120)
        canvas.draw("70", rightEdge: 470, top: 420, height: 70)
        canvas.addLabel(top: 135)
        canvas.addLabel(top: 295)
        canvas.addLabel(top: 440)

        let rows = SevenSegmentReader.read(canvas.image, labelBoxes: canvas.labelBoxes)
        XCTAssertEqual(rows.map(\.text), ["128", "82", "70"])

        let result = BPTextParser.parse(labelItems(canvas, ["SYS", "DIA", "PULSE"]) + rows)
        XCTAssertEqual(result.systolic, 128)
        XCTAssertEqual(result.diastolic, 82)
        XCTAssertEqual(result.pulse, 70)
    }

    /// 「1」は縦棒だけで前後のすき間が大きいが、同じ数値として読む。
    func testReadsNarrowOnes() {
        var canvas = DisplayCanvas()
        canvas.draw("117", rightEdge: 470, top: 90, height: 120)
        canvas.draw("81", rightEdge: 470, top: 250, height: 120)
        canvas.addLabel(top: 135)
        canvas.addLabel(top: 295)

        let rows = SevenSegmentReader.read(canvas.image, labelBoxes: canvas.labelBoxes)

        XCTAssertEqual(rows.map(\.text), ["117", "81"])
    }

    func testReadsEveryDigit() {
        var canvas = DisplayCanvas()
        canvas.draw("234", rightEdge: 470, top: 90, height: 120)
        canvas.draw("567", rightEdge: 470, top: 250, height: 120)
        canvas.draw("890", rightEdge: 470, top: 410, height: 120)
        canvas.addLabel(top: 135)
        canvas.addLabel(top: 295)
        canvas.addLabel(top: 455)

        let rows = SevenSegmentReader.read(canvas.image, labelBoxes: canvas.labelBoxes)

        XCTAssertEqual(rows.map(\.text), ["234", "567", "890"])
    }

    func testReturnsNothingWithoutLabels() {
        var canvas = DisplayCanvas()
        canvas.draw("128", rightEdge: 470, top: 90, height: 120)

        XCTAssertTrue(SevenSegmentReader.read(canvas.image, labelBoxes: []).isEmpty)
    }

    // MARK: - 実物の写真

    #if canImport(UIKit)
    /// 汎用の文字認識では 1 桁も読めなかった実物の表示（Fixtures/README.md 参照）。
    func testReadsRealDisplayPhoto() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "boots_display_131_88_77", withExtension: "jpg"))
        let cgImage = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let image = try XCTUnwrap(GrayImage(cgImage: cgImage))
        let labels = [
            OCRTextItem(text: "SYS", boundingBox: CGRect(x: 0.1708, y: 0.6385, width: 0.1292, height: 0.0677)),
            OCRTextItem(text: "DIA", boundingBox: CGRect(x: 0.1738, y: 0.4231, width: 0.1200, height: 0.0677)),
            OCRTextItem(text: "PULSE", boundingBox: CGRect(x: 0.0969, y: 0.2046, width: 0.1969, height: 0.0631))
        ]

        let rows = SevenSegmentReader.read(image, labelBoxes: labels.map(\.boundingBox))
        let result = BPTextParser.parse(labels + rows)

        XCTAssertEqual(result.systolic, 131)
        XCTAssertEqual(result.diastolic, 88)
    }
    #endif
}
