import Foundation

/// 広告の読み込みに失敗したときの再試行の間隔（仕様書 1-10：上限付きバックオフ）。
///
/// 間隔を少しずつ延ばし、上限回数に達したらそれ以上は試さない。
/// 読み込みに成功したら `reset()` で数え直す。
struct AdRetryPolicy: Equatable, Sendable {
    /// 再試行までの待ち時間（秒）。この回数を超えたら諦める。
    static let delays: [TimeInterval] = [10, 30, 60, 120, 300]

    private(set) var attempts = 0

    /// 次に再試行するまでの秒数。上限に達していれば nil。
    mutating func nextDelay() -> TimeInterval? {
        guard attempts < Self.delays.count else { return nil }
        defer { attempts += 1 }
        return Self.delays[attempts]
    }

    mutating func reset() {
        attempts = 0
    }
}
