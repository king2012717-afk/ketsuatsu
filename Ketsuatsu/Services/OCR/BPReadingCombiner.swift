import Foundation

/// 同じ写真を複数の方法で読んだ結果から、最終的な値を選ぶ。
///
/// 元の写真・セグメントをつないだ画像・7 セグメントの読み取り、のように読み方を変えると、
/// 得意な表示がそれぞれ違う。複数の読み方で一致した値は信頼でき、
/// 一致しなければ確度の高いほうを選ぶ。
enum BPReadingCombiner {

    static func combine(_ results: [BPParseResult]) -> BPParseResult {
        let candidates = results.filter { $0.systolic != nil || $0.diastolic != nil || $0.pulse != nil }
        guard !candidates.isEmpty else { return results.first ?? .empty }

        var chosen = chooseBloodPressure(from: candidates)
        if let pulse = choosePulse(from: candidates, preferred: chosen) {
            chosen.pulse = pulse
        }
        return chosen
    }

    /// 液晶の数字の形から読んだ結果（`shape`）を、ほかの読み方より優先してよければ、最終結果として返す。
    ///
    /// 文字認識は 7 セグメントの数字を読めないとき、近くに印字された目盛りの数字（「85」「135」など）を値として
    /// 拾うことがある。読み直してもしばしば同じ誤りになるので、「複数の読み方で一致」だけでは防げない
    /// （2026-11-21、上 120・下 70 の表示を 120／85 と読んだ）。形から読んだ結果は、上・下・脈拍の 3 段が
    /// そろい、判定に余裕があるときだけ高い確度になるので、そのときは優先する。
    ///
    /// ただし、文字認識がラベルつきで 3 つの値をはっきり読み、違う値を出しているときは優先しない
    /// （7 セグメントでない表示の機種。通常どおり読み比べる）。
    static func preferringShapeReading(_ shape: BPParseResult, over others: [BPParseResult]) -> BPParseResult? {
        guard shape.hasBloodPressure, shape.confidence >= shapeTrustThreshold else { return nil }
        let pair = Pair(shape)
        let complete = others.filter(\.hasBloodPressure)
        if complete.contains(where: { Pair($0) != pair && $0.confidence >= strongTextThreshold }) { return nil }
        var result = shape
        if complete.contains(where: { Pair($0) == pair }) {
            result.confidence = min(1.0, result.confidence + 0.05)
            result.explanation += "・複数の読み方で一致しました"
        }
        return result
    }

    /// 形から読んだ結果を優先する確度（上・下・脈拍がそろい、判定に余裕があるときの値）。
    static let shapeTrustThreshold = 0.9
    /// 文字認識がラベルつきで 3 つの値をはっきり読めたとみなす確度。
    static let strongTextThreshold = 0.93

    /// 2 つ以上の読み方で、上下の値が一致しているか（これ以上読み直す必要がないかの判断に使う）。
    static func hasAgreement(_ results: [BPParseResult]) -> Bool {
        let pairs = results.filter(\.hasBloodPressure).map(Pair.init)
        return Set(pairs).count < pairs.count
    }

    // MARK: - 上下の値

    private static func chooseBloodPressure(from results: [BPParseResult]) -> BPParseResult {
        let complete = results.filter(\.hasBloodPressure)

        // 2 つ以上の読み方で同じ上下の値になったものを最優先する。
        var votes: [Pair: [BPParseResult]] = [:]
        for result in complete {
            votes[Pair(result), default: []].append(result)
        }
        if let (_, agreeing) = votes.filter({ $0.value.count >= 2 }).max(by: { $0.value.count < $1.value.count }),
           var best = agreeing.max(by: { $0.confidence < $1.confidence }) {
            best.confidence = min(1.0, best.confidence + 0.1)
            best.explanation += "・複数の読み方で一致しました"
            return best
        }
        if let best = complete.max(by: { $0.confidence < $1.confidence }) {
            return best
        }

        // 上下がそろった結果がない場合は、片方ずつ確度の高いものを使う（組み合わせて矛盾しない場合だけ）。
        let bySystolic = results.filter { $0.systolic != nil }.max { $0.confidence < $1.confidence }
        let byDiastolic = results.filter { $0.diastolic != nil }.max { $0.confidence < $1.confidence }
        var partial = [bySystolic, byDiastolic].compactMap { $0 }.max { $0.confidence < $1.confidence }
            ?? results.max { $0.confidence < $1.confidence }!
        if let s = bySystolic?.systolic, let d = byDiastolic?.diastolic,
           BPValueRange.isPlausible(systolic: s, diastolic: d) {
            partial.systolic = s
            partial.diastolic = d
        }
        return partial
    }

    private struct Pair: Hashable {
        var systolic: Int
        var diastolic: Int

        init(_ result: BPParseResult) {
            systolic = result.systolic ?? 0
            diastolic = result.diastolic ?? 0
        }
    }

    // MARK: - 脈拍

    /// 多くの読み方で一致した脈拍を選ぶ。同数なら、上下の値を選んだ結果の脈拍を優先する。
    private static func choosePulse(from results: [BPParseResult], preferred: BPParseResult) -> Int? {
        var counts: [Int: Int] = [:]
        for pulse in results.compactMap(\.pulse) {
            counts[pulse, default: 0] += 1
        }
        guard let top = counts.values.max() else { return nil }
        let leaders = counts.filter { $0.value == top }.map(\.key)
        if let pulse = preferred.pulse, leaders.contains(pulse) { return pulse }
        return results
            .filter { $0.pulse.map(leaders.contains) == true }
            .max { $0.confidence < $1.confidence }?
            .pulse
    }
}
