import Foundation

/// 写真の読み取りが、実際に保存された値と合っていたか（読み取り精度の計測用）。
///
/// 持つのは「合っていた／直された」などの区分だけで、血圧や脈拍の値そのものは持たない。
/// 脈拍を記録したかどうかも分からない形にしている（読み取った脈拍がそのまま使われたかだけを見る）。
struct PhotoReadingOutcome: Equatable, Sendable {

    /// 読み取りで得られた項目。
    enum ReadResult: String, Sendable {
        /// 上・下・脈拍
        case full
        /// 上・下だけ
        case bloodPressureOnly = "bp_only"
        /// どれか一部だけ
        case partial
        /// 何も読めなかった
        case none
    }

    /// 読み取った脈拍の扱い。
    enum PulseMatch: String, Sendable {
        /// 読み取った値のまま保存された
        case matched = "true"
        /// 読み取った値が直された（または消された）
        case corrected = "false"
        /// 脈拍は読み取れなかった（そのあと手で入れたかどうかは見ない）
        case notRead = "not_read"
    }

    /// 確度の区分。確認の注意書きを出すしきい値（0.85）で分ける。
    enum Confidence: String, Sendable {
        case high
        case low
    }

    var readResult: ReadResult
    /// 読み取った上・下の値が、どちらもそのまま保存されたか。上・下を読めなかったときは false。
    var bloodPressureMatched: Bool
    var pulseMatch: PulseMatch
    var reader: BPParseResult.Reader
    var confidence: Confidence

    /// - Parameters:
    ///   - result: 読み取り結果。読み取り自体に失敗したときは nil
    ///   - systolic: 保存された上の値
    ///   - diastolic: 保存された下の値
    ///   - pulse: 保存された脈拍
    init(result: BPParseResult?, systolic: Int, diastolic: Int, pulse: Int?) {
        let result = result ?? .empty
        if result.hasBloodPressure {
            readResult = result.pulse != nil ? .full : .bloodPressureOnly
        } else if result.systolic != nil || result.diastolic != nil || result.pulse != nil {
            readResult = .partial
        } else {
            readResult = .none
        }
        bloodPressureMatched = result.hasBloodPressure && result.systolic == systolic && result.diastolic == diastolic
        if let read = result.pulse {
            pulseMatch = read == pulse ? .matched : .corrected
        } else {
            pulseMatch = .notRead
        }
        reader = result.reader
        confidence = result.confidence >= Self.highConfidence ? .high : .low
    }

    /// 画面で「値が正しいか確認してください」を出さない確度。
    static let highConfidence = 0.85

    /// 計測へ送るパラメータ。区分の名前だけで、値は含まない。
    var analyticsParameters: [String: String] {
        [
            "read_result": readResult.rawValue,
            "bp_match": bloodPressureMatched ? "true" : "false",
            "pulse_match": pulseMatch.rawValue,
            "reader": reader.rawValue,
            "confidence": confidence.rawValue,
        ]
    }
}
