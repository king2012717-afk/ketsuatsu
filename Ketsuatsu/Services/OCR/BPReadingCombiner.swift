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
