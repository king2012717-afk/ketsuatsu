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

/// 広告 SDK の初期化に失敗したあと、いつ再初期化してよいかを決める（仕様書 1-10：上限付きバックオフ）。
///
/// 再初期化は、アプリが前面に出たときにだけ試す（背面では試さない）。前回の失敗から
/// `AdRetryPolicy.delays` の時間が空いていなければ見送り、上限回数に達したらそれ以上は試さない
/// （アプリを起動し直すと数え直す）。
struct AdInitializationRetry: Equatable, Sendable {
    private(set) var failures = 0
    private(set) var lastFailureAt: Date?

    /// 初期化に失敗したときに呼ぶ。
    mutating func recordFailure(at date: Date = Date()) {
        failures += 1
        lastFailureAt = date
    }

    /// いま再初期化してよいか。失敗していなければ false（初回の起動は別の経路で行う）。
    func shouldRetry(at date: Date = Date()) -> Bool {
        guard let lastFailureAt, failures > 0, failures <= AdRetryPolicy.delays.count else { return false }
        return date.timeIntervalSince(lastFailureAt) >= AdRetryPolicy.delays[failures - 1]
    }
}
