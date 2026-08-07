import Foundation
import CoreGraphics

/// Vision が認識した 1 行ぶんのテキスト。
///
/// `boundingBox` は Vision の正規化座標（0〜1、原点は左下）。
/// 解析ロジックを Vision から切り離してテストできるように、この構造体を介してやりとりする。
struct OCRTextItem: Equatable, Sendable {
    var text: String
    var boundingBox: CGRect
    var confidence: Float

    init(text: String, boundingBox: CGRect, confidence: Float = 1.0) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// 写真からの読み取り結果。
struct BPParseResult: Equatable, Sendable {
    var systolic: Int?
    var diastolic: Int?
    var pulse: Int?
    /// 0.0〜1.0。ラベル（SYS/DIA など）を根拠にできたかどうかで大きく変わる。
    var confidence: Double = 0
    /// 解析に使った根拠。デバッグと「読み取り結果の確認」画面での説明に使う。
    var explanation: String = ""

    /// 血圧として記録できる最低限の情報がそろっているか。
    var hasBloodPressure: Bool { systolic != nil && diastolic != nil }

    static let empty = BPParseResult()
}
