import CoreGraphics
import Foundation

/// おすすめアプリの表示（`recommended_app_impression`）を、いつ送るかを決める（仕様書 4-8、共通設計 v2）。
///
/// - 行の **半分以上** が画面に入ったときだけ送る。読み込んだだけ・画面外の行では送らない
/// - 同じ行は、アプリが前面にいる間 1 回まで
/// - アプリが背面に回ったら数え直す。前面に戻った時点で見えている行は、改めて 1 回送る
struct ImpressionTracker: Equatable, Sendable {
    static let visibleThreshold = 0.5

    private(set) var logged: Set<String> = []
    private(set) var visible: Set<String> = []

    /// 行の見えている割合が変わったとき。今回送るべきなら true を返し、送信済みとして記録する。
    mutating func update(id: String, visibleFraction: Double) -> Bool {
        guard visibleFraction >= Self.visibleThreshold else {
            visible.remove(id)
            return false
        }
        visible.insert(id)
        return logged.insert(id).inserted
    }

    /// アプリが背面に回ったとき。
    mutating func didEnterBackground() {
        logged.removeAll()
    }

    /// アプリが前面に戻ったとき。見えている行のうち、まだ送っていないものを返す（送信済みとして記録する）。
    mutating func didBecomeActive() -> [String] {
        let pending = visible.subtracting(logged).sorted()
        logged.formUnion(pending)
        return pending
    }

    /// `frame` のうち `bounds`（画面）に入っている高さの割合。
    static func visibleFraction(of frame: CGRect, in bounds: CGRect) -> Double {
        guard frame.height > 0, !bounds.isEmpty else { return 0 }
        let overlap = frame.intersection(bounds)
        guard !overlap.isNull else { return 0 }
        return Double(overlap.height / frame.height)
    }
}
