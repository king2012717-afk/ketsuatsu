import Foundation
import CoreGraphics

/// OCR で得たテキストから収縮期・拡張期・脈拍を推定する。
///
/// 血圧計の表示は機種ごとにレイアウトが違うため、確度の高い根拠から順に使う。
/// 1. `128/82` のようなスラッシュ区切り
/// 2. `SYS` / `DIA` / `脈拍` などのラベルと同じ行にある数値
/// 3. ラベルだけの行 → 直下・右隣にある数値
/// 4. 位置と文字サイズによる推定（上から 収縮期 → 拡張期 → 脈拍 の並びが一般的）
///
/// 液晶（7 セグメント）の「1」は縦棒だけで幅が狭く、前後に大きなすき間ができる。
/// そのため OCR が「131」を「13」「1」に分けたり、先頭の「1」を落として「117」を「17」と
/// 読んだりする。前者は同じ段の数字をつなぎ直し、後者は条件付きで「1」を補って候補に加える。
///
/// Vision に依存しないので、`OCRTextItem` を組み立てれば単体テストできる。
enum BPTextParser {

    // MARK: - 公開 API

    /// - Parameter aspectRatio: 画像の幅 ÷ 高さ。正規化座標の横と縦の長さを比べるときに使う。
    static func parse(_ items: [OCRTextItem], aspectRatio: CGFloat = 1) -> BPParseResult {
        let lines = items.enumerated()
            .map { Line(item: $1, lineIndex: $0) }
            .filter { !$0.isIgnored }
        guard !lines.isEmpty else { return .empty }

        var context = ParseContext()
        context.pool = mergeSplitDigits(lines.flatMap(\.numbers), aspectRatio: aspectRatio)

        applySlashPairs(lines, to: &context)
        applyInlineLabels(lines, to: &context)
        applyDetachedLabels(lines, to: &context)
        applyGeometry(to: &context)

        return context.makeResult()
    }

    // MARK: - 種類

    enum Field: Hashable, Sendable {
        case systolic
        case diastolic
        case pulse

        var range: ClosedRange<Int> {
            switch self {
            case .systolic: return BPValueRange.systolic
            case .diastolic: return BPValueRange.diastolic
            case .pulse: return BPValueRange.pulse
            }
        }
    }

    struct NumberToken: Equatable, Sendable {
        var id: Int
        var value: Int
        var box: CGRect
        var confidence: Float
        /// 元の数字の並び（「05」のように先頭の 0 も残す）。桁のつなぎ直しと「1」の補完に使う。
        var digits: String = ""
        /// 「128/82」の一部など、隣の数字とつなげてはいけないもの。
        var isMergeable = false
        /// 先頭の「1」を補った候補かどうか（確度を少し下げるため）。
        var isLeadingOneRecovered = false

        /// 数字の描画サイズ。血圧計は収縮期・拡張期を大きく、脈拍を小さく表示することが多い。
        var height: CGFloat { box.height }
        /// Vision 座標は原点が左下なので、値が大きいほど画面の上。
        var verticalPosition: CGFloat { box.midY }
    }

    // MARK: - 解析の途中状態

    private struct ParseContext {
        var systolic: NumberToken?
        var diastolic: NumberToken?
        var pulse: NumberToken?
        /// まだどの項目にも割り当てられていない数値。
        var pool: [NumberToken] = []
        var labelledFields: Set<Field> = []
        var usedSlashPair = false

        mutating func assign(_ token: NumberToken, to field: Field, viaLabel: Bool) {
            switch field {
            case .systolic:
                guard systolic == nil else { return }
                systolic = token
            case .diastolic:
                guard diastolic == nil else { return }
                diastolic = token
            case .pulse:
                guard pulse == nil else { return }
                pulse = token
            }
            if viaLabel { labelledFields.insert(field) }
            pool.removeAll { $0.id == token.id }
        }

        func isAssigned(_ field: Field) -> Bool {
            switch field {
            case .systolic: return systolic != nil
            case .diastolic: return diastolic != nil
            case .pulse: return pulse != nil
            }
        }

        func makeResult() -> BPParseResult {
            var systolicValue = systolic?.value
            var diastolicValue = diastolic?.value

            // 上下が入れ替わっていたら直す（ラベルの誤認識のフォロー）。
            if let s = systolicValue, let d = diastolicValue, s < d {
                swap(&systolicValue, &diastolicValue)
            }
            // 血圧としてあり得ない組み合わせなら採用しない。
            if let s = systolicValue, let d = diastolicValue,
               !BPValueRange.isPlausible(systolic: s, diastolic: d) {
                systolicValue = nil
                diastolicValue = nil
            }

            var confidence = 0.0
            var reasons: [String] = []

            if systolicValue != nil && diastolicValue != nil {
                if labelledFields.contains(.systolic) || labelledFields.contains(.diastolic) {
                    confidence = 0.9
                    reasons.append("表示のラベルから読み取りました")
                } else if usedSlashPair {
                    confidence = 0.8
                    reasons.append("「上／下」の表記から読み取りました")
                } else {
                    confidence = 0.6
                    reasons.append("表示の並び順から推定しました")
                }
            } else if systolicValue != nil || diastolicValue != nil {
                confidence = 0.3
                reasons.append("一部の数値しか読み取れませんでした")
            } else {
                reasons.append("数値を読み取れませんでした")
            }

            if systolic?.isLeadingOneRecovered == true, systolicValue != nil {
                confidence *= 0.85
                reasons.append("収縮期の先頭の「1」を補いました")
            }

            if pulse != nil {
                confidence = min(1.0, confidence + 0.05)
                reasons.append(labelledFields.contains(.pulse) ? "脈拍もラベルから取得しました" : "脈拍は位置から推定しました")
            }

            // OCR 自体の信頼度も反映する。
            let ocrConfidences = [systolic, diastolic, pulse].compactMap { $0?.confidence }
            if !ocrConfidences.isEmpty {
                let average = Double(ocrConfidences.reduce(0, +)) / Double(ocrConfidences.count)
                confidence *= (0.7 + 0.3 * min(1.0, max(0.0, average)))
            }

            return BPParseResult(
                systolic: systolicValue,
                diastolic: diastolicValue,
                pulse: pulse?.value,
                confidence: min(1.0, confidence),
                explanation: reasons.joined(separator: "・")
            )
        }
    }

    private struct LabelToken {
        var field: Field
        var box: CGRect
    }

    /// 1 行を語単位に分解したもの。
    private struct Line {
        var numbers: [NumberToken] = []
        var labels: [LabelToken] = []
        var slashPairs: [[NumberToken]] = []
        /// 日付・時刻の行は血圧の数値と紛らわしいため丸ごと無視する。
        var isIgnored = false

        init(item: OCRTextItem, lineIndex: Int) {
            // 日付・時刻の部分だけを空白にする。脈拍と時刻が同じ段に並ぶ機種（「72 0:00」）があるため、
            // 行ごと捨てると脈拍まで消えてしまう。
            let normalized = BPTextParser.maskDateAndTime(BPTextParser.normalize(item.text))
            guard normalized.contains(where: { !$0.isWhitespace }) else {
                isIgnored = true
                return
            }

            let characters = Array(normalized)
            guard !characters.isEmpty else { return }

            var cursor = 0
            for (wordIndex, word) in BPTextParser.words(in: normalized).enumerated() {
                // 元テキスト内の位置から、語のおおよその矩形を割り出す。
                let characterRange = BPTextParser.range(of: word, in: characters, from: &cursor)
                let box = BPTextParser.subBox(
                    of: item.boundingBox,
                    characterRange: characterRange,
                    total: characters.count
                )
                let baseID = lineIndex * 1_000 + wordIndex * 10

                if let field = BPTextParser.field(for: word) {
                    labels.append(LabelToken(field: field, box: box))
                    continue
                }
                if let values = BPTextParser.slashSeparatedValues(in: word) {
                    let tokens = values.enumerated().map { offset, value in
                        NumberToken(id: baseID + offset, value: value, box: box, confidence: item.confidence)
                    }
                    slashPairs.append(tokens)
                    numbers.append(contentsOf: tokens)
                    continue
                }
                if let value = BPTextParser.numericValue(of: word) {
                    numbers.append(
                        NumberToken(
                            id: baseID,
                            value: value,
                            box: box,
                            confidence: item.confidence,
                            digits: BPTextParser.digitString(of: word) ?? String(value),
                            isMergeable: true
                        )
                    )
                }
            }
        }
    }

    // MARK: - ステップ 1: スラッシュ区切り

    private static func applySlashPairs(_ lines: [Line], to context: inout ParseContext) {
        for line in lines {
            for pair in line.slashPairs where pair.count >= 2 {
                guard BPValueRange.isPlausible(systolic: pair[0].value, diastolic: pair[1].value) else { continue }
                context.assign(pair[0], to: .systolic, viaLabel: false)
                context.assign(pair[1], to: .diastolic, viaLabel: false)
                context.usedSlashPair = true
                if pair.count >= 3, BPValueRange.pulse.contains(pair[2].value) {
                    context.assign(pair[2], to: .pulse, viaLabel: false)
                }
                return
            }
        }
    }

    // MARK: - ステップ 2: 行内のラベル

    private static func applyInlineLabels(_ lines: [Line], to context: inout ParseContext) {
        for line in lines where !line.labels.isEmpty && !line.numbers.isEmpty {
            let available = line.numbers.filter { token in context.pool.contains { $0.id == token.id } }
            guard !available.isEmpty else { continue }

            if line.labels.count == available.count {
                // 「SYS 128 DIA 82」のように左から順に対応させる。
                let sortedLabels = line.labels.sorted { $0.box.minX < $1.box.minX }
                let sortedNumbers = available.sorted { $0.box.minX < $1.box.minX }
                for (label, number) in zip(sortedLabels, sortedNumbers) {
                    guard !context.isAssigned(label.field),
                          label.field.range.contains(number.value) else { continue }
                    context.assign(number, to: label.field, viaLabel: true)
                }
            } else if line.labels.count == 1 {
                // 「SYS 128 mmHg」のようにラベル 1 つに数値が複数。最も近い数値を採用する。
                let label = line.labels[0]
                guard !context.isAssigned(label.field) else { continue }
                let candidates = available.filter { label.field.range.contains($0.value) }
                if let nearest = candidates.min(by: {
                    abs($0.box.midX - label.box.midX) < abs($1.box.midX - label.box.midX)
                }) {
                    context.assign(nearest, to: label.field, viaLabel: true)
                }
            }
        }
    }

    // MARK: - ステップ 3: 単独のラベル行

    private static func applyDetachedLabels(_ lines: [Line], to context: inout ParseContext) {
        let detached = lines.filter { !$0.labels.isEmpty && $0.numbers.isEmpty }.flatMap(\.labels)
        // SYS／DIA／PULSE が本体に縦に印字されている機種では、数値は「高さがいちばん近いラベル」のもの。
        // 下の段の脈拍を収縮期と取り違えないよう、ほかのラベルの段にある数値は候補から外す。
        let isStacked = labelsAreStacked(detached)
        for label in detached where !context.isAssigned(label.field) {
            // ラベルと同じ段に数字があるなら、その段の数字だけを見る（値が範囲外でもほかの段へは探しに行かない）。
            // 「117」を「17」と読み落としたときに、下の段の脈拍を収縮期として拾わないため。
            let sameRow = context.pool.filter { $0.box.minY <= label.box.midY && label.box.midY <= $0.box.maxY }
            var candidates = (sameRow.isEmpty ? context.pool : sameRow)
                .filter { label.field.range.contains($0.value) }
            if isStacked {
                candidates = candidates.filter { nearestLabel(to: $0, among: detached)?.field == label.field }
            }
            guard !candidates.isEmpty else { continue }

            // ラベルの下 or 右にある数値を優先し、その中で最も近いものを選ぶ。
            let scored = candidates.map { token -> (token: NumberToken, distance: CGFloat) in
                let dx = token.box.midX - label.box.midX
                let dy = label.box.midY - token.box.midY  // 正なら数値がラベルより下
                var distance = (dx * dx + dy * dy).squareRoot()
                if dy < 0 { distance += 0.35 }             // ラベルより上にある数値は優先度を下げる
                if abs(dx) > 0.5 { distance += 0.35 }      // 極端に離れた列も下げる
                return (token, distance)
            }
            if let best = scored.min(by: { $0.distance < $1.distance }) {
                context.assign(best.token, to: label.field, viaLabel: true)
            }
        }
    }

    /// ラベルが別々の段に縦に並んでいるか（同じ行に「SYS DIA」と並ぶ表示とは扱いを分ける）。
    private static func labelsAreStacked(_ labels: [LabelToken]) -> Bool {
        guard Set(labels.map(\.field)).count >= 2 else { return false }
        let centers = labels.map(\.box.midY)
        let tallest = labels.map(\.box.height).max() ?? 0
        guard let top = centers.max(), let bottom = centers.min() else { return false }
        return top - bottom > tallest * 1.5
    }

    private static func nearestLabel(to token: NumberToken, among labels: [LabelToken]) -> LabelToken? {
        labels.min { abs($0.box.midY - token.box.midY) < abs($1.box.midY - token.box.midY) }
    }

    // MARK: - ステップ 4: 位置と文字サイズによる推定

    /// 脈拍として採用するための最低スコア。無関係な数字を拾いすぎないための下限。
    private static let pulseScoreThreshold = 3.0

    private static func applyGeometry(to context: inout ParseContext) {
        switch (context.systolic, context.diastolic) {
        case (nil, nil):
            var best: (systolic: NumberToken, diastolic: NumberToken, score: Double)?
            for upper in systolicCandidates(context.pool) {
                for lower in context.pool where lower.id != upper.id {
                    guard BPValueRange.isPlausible(systolic: upper.value, diastolic: lower.value),
                          haveComparableSize(upper, lower) else { continue }
                    let score = pairScore(systolic: upper, diastolic: lower)
                    if score > (best?.score ?? -.greatestFiniteMagnitude) {
                        best = (upper, lower, score)
                    }
                }
            }
            if let best {
                context.assign(best.systolic, to: .systolic, viaLabel: false)
                context.assign(best.diastolic, to: .diastolic, viaLabel: false)
            }

        case (nil, .some(let diastolic)):
            // 拡張期だけ分かっている場合、組み合わせて最もそれらしい数値を収縮期とみなす。
            let candidate = systolicCandidates(context.pool)
                .filter { $0.id != diastolic.id && haveComparableSize($0, diastolic) }
                .filter { BPValueRange.isPlausible(systolic: $0.value, diastolic: diastolic.value) }
                .max { pairScore(systolic: $0, diastolic: diastolic) < pairScore(systolic: $1, diastolic: diastolic) }
            if let candidate { context.assign(candidate, to: .systolic, viaLabel: false) }

        case (.some(let systolic), nil):
            let candidate = context.pool
                .filter { haveComparableSize(systolic, $0) }
                .filter { BPValueRange.isPlausible(systolic: systolic.value, diastolic: $0.value) }
                .max { pairScore(systolic: systolic, diastolic: $0) < pairScore(systolic: systolic, diastolic: $1) }
            if let candidate { context.assign(candidate, to: .diastolic, viaLabel: false) }

        case (.some, .some):
            break
        }

        guard context.pulse == nil else { return }
        let reference = context.diastolic ?? context.systolic
        let best = context.pool
            .filter { BPValueRange.pulse.contains($0.value) }
            .max { pulseScore($0, below: reference) < pulseScore($1, below: reference) }
        if let best, pulseScore(best, below: reference) >= pulseScoreThreshold {
            context.assign(best, to: .pulse, viaLabel: false)
        }
    }

    /// 収縮期の候補。2 桁の数字は先頭の「1」を落とした可能性があるため（「117」→「17」）、
    /// 「1」を補った値も加える。補った候補は `pairScore` で減点し、本当に 2 桁の値（98 など）を優先する。
    private static func systolicCandidates(_ pool: [NumberToken]) -> [NumberToken] {
        pool + pool.compactMap { token in
            guard token.isMergeable, token.digits.count == 2, let value = Int("1" + token.digits) else { return nil }
            var recovered = token
            recovered.value = value
            recovered.digits = "1" + token.digits
            recovered.isLeadingOneRecovered = true
            return recovered
        }
    }

    /// 収縮期と拡張期は同じ大きさの数字で表示される。脈拍は小さい（実機の写真では 0.5〜0.6 倍）。
    /// 拡張期を読み落としたときに、小さい脈拍の数字と組ませないための条件。
    private static func haveComparableSize(_ a: NumberToken, _ b: NumberToken) -> Bool {
        guard a.height > 0, b.height > 0 else { return true }
        return min(a.height, b.height) / max(a.height, b.height) >= 0.7
    }

    /// 収縮期・拡張期の組み合わせらしさ。
    private static func pairScore(systolic: NumberToken, diastolic: NumberToken) -> Double {
        var score = 0.0
        if systolic.isLeadingOneRecovered { score -= 1.5 }

        // 一般的な血圧計は収縮期を上に表示する。
        if systolic.verticalPosition > diastolic.verticalPosition { score += 3 }
        // 同じくらいの文字サイズで並んでいるか。
        if systolic.height > 0, diastolic.height > 0 {
            let ratio = min(systolic.height, diastolic.height) / max(systolic.height, diastolic.height)
            score += Double(ratio) * 2
        }
        // よくある値の範囲に近いほど加点。
        if (90...200).contains(systolic.value) { score += 2 }
        if (50...110).contains(diastolic.value) { score += 2 }
        // 脈圧が生理的な範囲か。
        if (20...80).contains(systolic.value - diastolic.value) { score += 1.5 }
        if systolic.value >= 100 { score += 0.5 }
        score += Double(systolic.confidence + diastolic.confidence) * 0.5

        return score
    }

    /// 脈拍らしさ。血圧の数値より下に、小さい文字で表示されることが多い。
    private static func pulseScore(_ token: NumberToken, below reference: NumberToken?) -> Double {
        var score = 0.5
        if (40...120).contains(token.value) { score += 2 }
        if let reference {
            if token.verticalPosition < reference.verticalPosition { score += 2 }
            if token.height <= reference.height { score += 1 }
        }
        score += Double(token.confidence)
        return score
    }

    // MARK: - テキストの前処理

    /// 全角を半角にそろえ、大文字に統一する。
    static func normalize(_ text: String) -> String {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidth
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "／", with: "/")
            .uppercased()
    }

    /// 日付・時刻の部分を同じ文字数の空白に置き換える（語の位置がずれないようにするため）。
    /// 「128/82」のような血圧の表記は残す。
    static func maskDateAndTime(_ normalized: String) -> String {
        let patterns = [
            "(?<!\\d)(19|20)\\d{2}\\s*[/.\\-年]\\s*\\d{1,2}\\s*[/.\\-月]\\s*\\d{1,2}\\s*日?",
            "\\d{1,2}\\s*月\\s*\\d{1,2}\\s*日?",
            "\\d{1,4}\\s*[年月日]",
            "\\d{1,2}:\\d{2}(:\\d{2})?",
            "午前|午後|\\bAM\\b|\\bPM\\b",
            "(?<!\\d)(19|20)\\d{2}(?!\\d)",
        ]
        var text = normalized
        for pattern in patterns {
            text = blank(pattern, in: text)
        }
        // 「10/25」のように日付として成り立つ組み合わせ
        return blank("(?<![\\d/])\\d{1,2}/\\d{1,2}(?![\\d/])", in: text) { match in
            let parts = match.split(separator: "/").compactMap { Int($0) }
            return parts.count == 2 && (1...12).contains(parts[0]) && (1...31).contains(parts[1])
        }
    }

    private static func blank(
        _ pattern: String,
        in text: String,
        where shouldBlank: (Substring) -> Bool = { _ in true }
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matched = result[range]
            guard shouldBlank(matched) else { continue }
            result.replaceSubrange(range, with: String(repeating: " ", count: matched.count))
        }
        return result
    }

    /// 空白と記号で語に分ける（`/` と `.` は数値表記に使われるため残す）。
    static func words(in normalized: String) -> [String] {
        normalized
            .split { !($0.isLetter || $0.isNumber || $0 == "/" || $0 == ".") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static let unitNoise = ["MMHG", "MM/HG", "MMH", "BPM", "/MIN", "MIN", "HG"]

    /// OCR で誤読しやすい英字を数字に読み替える対応表。
    private static let confusions: [Character: Character] = [
        "O": "0", "Q": "0", "D": "0",
        "I": "1", "L": "1", "|": "1",
        "Z": "2", "S": "5", "B": "8", "G": "6", "T": "7"
    ]

    /// 語を数値として解釈する。`128`、`l28`、`128MMHG` などに対応。
    static func numericValue(of word: String) -> Int? {
        digitString(of: word).flatMap { Int($0) }
    }

    /// 語を数字の並びとして解釈する。先頭の 0 も残す（`05` → `"05"`）。
    static func digitString(of word: String) -> String? {
        var cleaned = word
        for noise in unitNoise {
            cleaned = cleaned.replacingOccurrences(of: noise, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        guard !cleaned.isEmpty, cleaned.count <= 3 else { return nil }
        // 文字だけの語（SOS など）を数字と誤認しないよう、最低 1 文字は数字であることを求める。
        guard cleaned.contains(where: { $0.isNumber }) else { return nil }

        let mapped = cleaned.map { confusions[$0] ?? $0 }
        guard mapped.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return String(mapped)
    }

    /// `128/82` のような表記を数値の並びに分解する。
    static func slashSeparatedValues(in word: String) -> [Int]? {
        guard word.contains("/") else { return nil }
        let parts = word.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let values = parts.compactMap { numericValue(of: $0) }
        guard values.count == parts.count else { return nil }
        return values
    }

    /// ラベル語かどうかを判定する。
    static func field(for word: String) -> Field? {
        if word == "P" { return .pulse }
        for keyword in ["PULSE", "PULS", "PUL", "脈拍", "脈", "HR", "BPM"] where word.contains(keyword) {
            return .pulse
        }
        for keyword in ["SYS", "最高", "収縮", "上"] where word.contains(keyword) {
            return .systolic
        }
        for keyword in ["DIA", "最低", "拡張", "下"] where word.contains(keyword) {
            return .diastolic
        }
        return nil
    }

    // MARK: - 分かれた数字のつなぎ直し

    /// 同じ段で横に並んだ数字の断片をつなぐ（「13」「1」→「131」、「1」「17」→「117」）。
    /// 7 セグメントの「1」は幅が狭く前後のすき間が大きいため、OCR が別の語に分けてしまう。
    static func mergeSplitDigits(_ tokens: [NumberToken], aspectRatio: CGFloat) -> [NumberToken] {
        var result = tokens
        var didMerge = true
        while didMerge {
            didMerge = false
            search: for i in result.indices {
                for j in result.indices where i != j {
                    let left = result[i]
                    let right = result[j]
                    guard canMerge(left, right, aspectRatio: aspectRatio),
                          let value = Int(left.digits + right.digits) else { continue }
                    var merged = left
                    merged.value = value
                    merged.digits = left.digits + right.digits
                    merged.box = left.box.union(right.box)
                    merged.confidence = min(left.confidence, right.confidence)
                    result[i] = merged
                    result.remove(at: j)
                    didMerge = true
                    break search
                }
            }
        }
        return result
    }

    private static func canMerge(_ left: NumberToken, _ right: NumberToken, aspectRatio: CGFloat) -> Bool {
        guard left.isMergeable, right.isMergeable,
              left.digits.count + right.digits.count <= 3 else { return false }
        // 「1」だけの断片が絡むときに限る。「128 82」のように別の値が横に並ぶ表示をつなげないため。
        guard left.digits.allSatisfy({ $0 == "1" }) || right.digits.allSatisfy({ $0 == "1" }) else { return false }

        let taller = max(left.box.height, right.box.height)
        let shorter = min(left.box.height, right.box.height)
        guard taller > 0, shorter / taller >= 0.6 else { return false }
        let overlap = min(left.box.maxY, right.box.maxY) - max(left.box.minY, right.box.minY)
        guard overlap >= shorter * 0.6 else { return false }

        // 正規化座標は縦横で尺度が違うので、横のすき間を高さと同じ尺度にそろえて比べる。
        let gap = (right.box.minX - left.box.maxX) * aspectRatio
        return gap >= -0.2 * taller && gap <= 0.9 * taller
    }

    // MARK: - 座標の按分

    /// 行全体の矩形から、文字位置に応じた語の矩形をおおよそ求める。
    private static func subBox(of lineBox: CGRect, characterRange: Range<Int>, total: Int) -> CGRect {
        guard total > 0 else { return lineBox }
        let start = CGFloat(characterRange.lowerBound) / CGFloat(total)
        let width = CGFloat(characterRange.count) / CGFloat(total)
        return CGRect(
            x: lineBox.minX + lineBox.width * start,
            y: lineBox.minY,
            width: max(lineBox.width * width, 0.0001),
            height: lineBox.height
        )
    }

    /// `words(in:)` が返した語が元テキストのどこにあったかを順に求める。
    private static func range(of word: String, in characters: [Character], from cursor: inout Int) -> Range<Int> {
        let target = Array(word)
        var start = cursor
        while start + target.count <= characters.count {
            if Array(characters[start..<(start + target.count)]) == target {
                cursor = start + target.count
                return start..<(start + target.count)
            }
            start += 1
        }
        cursor = characters.count
        return 0..<characters.count
    }
}
