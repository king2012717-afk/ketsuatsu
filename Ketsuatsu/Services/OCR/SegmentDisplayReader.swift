import Foundation

/// 液晶（7 セグメント表示）の数字を、印字ラベルに頼らずに読む。
///
/// `SevenSegmentReader` は「SYS／DIA の印字が液晶の左にある」機種でしか使えない。実際の血圧計は、
/// 印字が右にあるもの、液晶の中に表示されるもの、日本語・中国語のもの、バックライトで光るもの、
/// 数字が斜体のもの、上下の段がほとんどくっついているものがある。ここでは数字の形と並びだけを手がかりにする。
///
/// 1. 写真を何段階かに縮小し、各段階では決まった高さ（22〜46 画素）の数字だけを探す
/// 2. 「インク」＝周りの明るさとの差を求める（影・反射・バックライトのむらに強い）
/// 3. インクの濃い画素を塊にまとめ、数字らしい大きさの塊を横に並べて段にする
/// 4. 段ごとに斜体を補正し、7 か所のインクの濃さ（その桁の中での相対値）で数字を決める
/// 5. 上下に並んだ同じ大きさの 2 段（上の血圧・下の血圧）と、その下の脈拍を選ぶ
///
/// 公開されている実機の写真 19 枚（6 機種）で、上下とも正解 15 枚・誤った値 0 枚・読めず 4 枚（2026-11-21）。
/// 読めないときは nil を返し、誤った値を出さないことを優先している。
enum SegmentDisplayReader {

    struct PixelRect: Equatable, Sendable {
        var x: Double, y: Double, width: Double, height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    /// 読み取れた数字の段。座標は元の画像の画素（左上が原点）。
    struct Row: Equatable, Sendable {
        var text: String
        var box: PixelRect
        /// 数字の高さ（元の画像の画素）。
        var digitHeight: Double
        /// 点灯・消灯の判定の余裕（0〜0.5）。小さいほど、きわどい判定が混じっている。
        var margin: Double
        /// 並びの一部だけを読んだもの（端にアイコンなどが付いていた）。
        var isPartial: Bool

        var value: Int { Int(text) ?? 0 }
    }

    struct Reading: Equatable, Sendable {
        var systolic: Int
        var diastolic: Int
        var pulse: Int?
        /// 上下 2 段の判定の余裕（小さいほうの段の値）。
        var margin: Double = 0
    }

    static func read(_ image: GrayImage) -> Reading? {
        choose(rows(in: image))
    }

    // MARK: - 設定値（実機の写真で決めた）

    /// 各段階で探す数字の高さ。
    private static let bandMin = 22.0, bandMax = 46.0
    /// 縮小後の長辺。隣り合う段階の比を約 1.4 にして、どの大きさの数字もどこかの段階で範囲に入るようにする。
    static let levels = [1200, 860, 615, 440, 315, 225, 160, 115]
    /// 周りの明るさを求める窓（クロージング）の大きさ。数字の線より太く、数字の高さより小さい。
    private static let backgroundWindow = 13
    /// インクとみなす最低の濃さと、近くでいちばん濃いインクに対する割合。
    private static let minimumInk = 12.0, relativeInk = 0.22
    /// セグメントが点灯しているとみなす濃さ（その桁でいちばん濃いセグメントに対する割合）。
    private static let litLevel = 0.5
    /// 影などで薄く写ったセグメント：この濃さ以上で、線としてつながっていれば点灯とみなす。
    private static let faintLitLevel = 0.28, faintCoverage = 0.6
    /// 隣の桁までのすき間の上限（数字の高さに対する割合）。「1」は桁の右に寄るので広く取る。
    private static let digitGap = 0.5, narrowDigitGap = 0.75
    /// 上・下・脈拍の段として採用する最低の判定の余裕。7 セグメントでない文字（普通の書体の数字や文章）を
    /// 無理に数字へ当てはめた段は余裕がほとんどない（実機の写真は 0.06 以上、誤読は 0.03 以下だった）。
    static let minimumMargin = 0.05
    /// 幅がこれより狭い塊は「1」。
    private static let narrowAspect = 0.42

    /// 点灯パターン（a=上, b=右上, c=右下, d=下, e=左下, f=左上, g=中）と数字。
    private static let patterns: [[Bool]: Int] = {
        let table: [(String, Int)] = [
            ("1111110", 0), ("0110000", 1), ("1101101", 2), ("1111001", 3), ("0110011", 4),
            ("1011011", 5), ("1011111", 6), ("0011111", 6), ("1110000", 7), ("1110010", 7),
            ("1111111", 8), ("1111011", 9), ("1110011", 9),
        ]
        return Dictionary(uniqueKeysWithValues: table.map { (Array($0.0).map { $0 == "1" }, $0.1) })
    }()

    // MARK: - 段を探す

    /// すべての段階で読めた段を返す（同じ段が複数の段階で見つかることがある）。
    static func rows(in image: GrayImage) -> [Row] {
        guard image.width >= 40, image.height >= 40 else { return [] }
        // いちばん大きい段階の画像を作り、それより小さい段階はそこから縮小する。
        let base = Plane(image).resized(longSide: levels[0])
        var found: [Row] = []
        for level in levels {
            let longSide = max(base.width, base.height)
            if Double(level) > Double(longSide) * 1.05 { continue }
            let plane = base.resized(longSide: level)
            let ratio = Double(plane.width) / Double(image.width)
            found += rows(at: plane, ratio: ratio)
        }
        return found
    }

    /// 縮小した 1 段階の画像から段を探す。`ratio` は元の画像に対する縮小率。
    static func rows(at gray: Plane, ratio: Double) -> [Row] {
        let ink = inkMap(gray)
        let window = Int(bandMax * 2.5) | 1
        let localMax = ink.extreme(before: window / 2, after: window / 2, takeMax: true)
        var mask = Plane(width: gray.width, height: gray.height, fill: 0)
        for i in 0..<ink.pixels.count {
            let threshold = max(minimumInk, relativeInk * Double(localMax.pixels[i]))
            if Double(ink.pixels[i]) > threshold { mask.pixels[i] = 255 }
        }
        mask = removeLongLines(mask, minLength: Int(bandMax * 1.3))
        // セグメントのすき間を少しだけつなぐ（縦 3・横 2）。
        let merged = mask
            .extreme(before: 0, after: 1, takeMax: true, vertical: false)
            .extreme(before: 1, after: 1, takeMax: true, vertical: true)
            .extreme(before: 1, after: 0, takeMax: false, vertical: false)
            .extreme(before: 1, after: 1, takeMax: false, vertical: true)
        let raw = SevenSegmentReader.connectedComponents(GrayImage(width: merged.width, height: merged.height, pixels: merged.pixels))
            .map { Box(x: $0.minX, y: $0.minY, w: $0.width, h: $0.height) }

        let blobs = digitBlobs(from: raw, ink: ink, mask: mask)
        let chains = digitChains(blobs)

        var out: [Row] = []
        for chain in chains {
            if chain.count <= 3, let row = readRow(chain, mask: mask, ink: ink, ratio: ratio), (20...299).contains(row.value) {
                out.append(row)
                continue
            }
            // 端に余分な塊（アイコン・時刻・枠線）が付いた並び：両端から 2〜3 個を取り出して読む。
            var seen: [[Box]] = []
            for count in [3, 2] where chain.count > count {
                for start in Set([0, chain.count - count]).sorted() {
                    let sub = Array(chain[start..<(start + count)])
                    if seen.contains(sub) { continue }
                    seen.append(sub)
                    if var row = readRow(sub, mask: mask, ink: ink, ratio: ratio), (20...299).contains(row.value) {
                        row.isPartial = true
                        out.append(row)
                    }
                }
            }
        }
        return out
    }

    // MARK: - 塊

    struct Box: Hashable, Sendable {
        var x: Int, y: Int, w: Int, h: Int
        var maxX: Int { x + w }
        var maxY: Int { y + h }
        var isNarrow: Bool { Double(w) < narrowAspect * Double(h) }
    }

    /// 塊の一覧を、数字 1 桁ぶんの塊に整える（くっついた上下の段を分け、縦に分かれたかけらをつなぐ）。
    private static func digitBlobs(from raw: [Box], ink: Plane, mask: Plane) -> [Box] {
        // 上下の段がくっついた塊（横いっぱいの横棒が上下に並ぶところがある）は、そのすき間で分ける。
        let tall = raw.filter {
            Double($0.h) >= 2 * bandMin && Double($0.h) <= 2.3 * bandMax && Double($0.w) <= 0.75 * Double($0.h)
        }
        var cuts: [(box: Box, y: Int)] = []
        for box in tall {
            if let cut = splitRow(box, ink: ink, mask: mask) { cuts.append((box, box.y + cut)) }
        }
        // 同じ段に並ぶ縦長の塊は、隣が分かれた高さで一緒に分ける（横棒のない数字どうしがくっついた場合）。
        for box in tall where !cuts.contains(where: { $0.box == box }) {
            for other in cuts {
                let c = other.box, ch = Double(c.h)
                guard abs(Double(box.y - c.y)) <= 0.12 * ch, abs(Double(box.h - c.h)) <= 0.15 * ch,
                      abs(Double(box.x - c.x)) <= 2.0 * ch else { continue }
                if Double(box.y) + 0.3 * Double(box.h) < Double(other.y), Double(other.y) < Double(box.y) + 0.7 * Double(box.h) {
                    cuts.append((box, other.y))
                }
                break
            }
        }

        var pieces: [Box] = []
        for box in raw {
            var parts = [box]
            if let cut = cuts.first(where: { $0.box == box }) {
                let offset = cut.y - box.y
                parts = [
                    tight(mask, Box(x: box.x, y: box.y, w: box.w, h: offset)),
                    tight(mask, Box(x: box.x, y: cut.y, w: box.w, h: box.h - offset)),
                ]
            }
            for part in parts where part.h >= 4 && Double(part.h) <= bandMax * 1.1 && part.w >= 2 && Double(part.w) <= bandMax {
                pieces.append(part)
            }
        }
        return joinVerticalPieces(pieces)
            .filter { Double($0.h) >= bandMin * 0.5 && Double($0.h) <= bandMax * 1.1 && $0.w >= 2 && Double($0.w) <= 0.85 * Double($0.h) }
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    /// くっついた 2 段を分ける行（塊の上端からの位置）を返す。
    /// 中央付近で、上下を横棒（幅いっぱいの行）にはさまれた谷を探す。
    private static func splitRow(_ box: Box, ink: Plane, mask: Plane) -> Int? {
        var count = [Int](repeating: 0, count: box.h)
        var profile = [Int](repeating: 0, count: box.h)
        for dy in 0..<box.h {
            let base = (box.y + dy) * mask.width + box.x
            for dx in 0..<box.w {
                if mask.pixels[base + dx] > 0 { count[dy] += 1 }
                profile[dy] += Int(ink.pixels[base + dx])
            }
        }
        let low = Int(0.35 * Double(box.h)), high = Int(0.65 * Double(box.h))
        guard low < high else { return nil }
        var y = low
        for candidate in low..<high where profile[candidate] < profile[y] { y = candidate }
        let span = max(2, Int(0.1 * Double(box.h)))
        let above = max(0, y - span)..<y, below = (y + 1)..<min(box.h, y + 1 + span)
        guard !above.isEmpty, !below.isEmpty else { return nil }
        let full = 0.75 * Double(box.w)
        guard Double(count[above].max() ?? 0) >= full, Double(count[below].max() ?? 0) >= full else { return nil }
        let peak = min(profile[above].max() ?? 0, profile[below].max() ?? 0)
        guard Double(profile[y]) <= 0.7 * Double(peak) else { return nil }
        return y
    }

    /// 範囲の中で、マスクの画素がある部分だけに詰める。
    private static func tight(_ mask: Plane, _ box: Box) -> Box {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in box.y..<box.maxY {
            let base = y * mask.width
            for x in box.x..<box.maxX where mask.pixels[base + x] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return box }
        return Box(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
    }

    /// 縦に分かれたかけらをつなぐ：「1」の上下の棒、影で切れた「7」の右下の棒。
    static func joinVerticalPieces(_ input: [Box]) -> [Box] {
        var blobs = input
        var i = 0
        while i < blobs.count {
            var merged = false
            let upper = blobs[i]
            for j in blobs.indices where j != i {
                let lower = blobs[j]
                guard lower.y > upper.y else { continue }
                let height = Double(lower.maxY - upper.y)
                guard height >= bandMin, height <= bandMax * 1.1 else { continue }
                let gap = Double(lower.y - upper.maxY)
                guard gap >= -1, gap <= max(2, 0.12 * height) else { continue }
                let x0 = min(upper.x, lower.x), x1 = max(upper.maxX, lower.maxX)
                guard Double(x1 - x0) <= 0.85 * height, Double(lower.w) < narrowAspect * height,
                      Double(lower.h) >= 0.2 * height, Double(upper.h) >= 0.3 * height else { continue }
                let overlap = min(upper.maxX, lower.maxX) - max(upper.x, lower.x)
                let bothNarrow = Double(upper.w) < narrowAspect * height
                    && Double(overlap) >= 0.5 * Double(min(upper.w, lower.w))
                let rightLeg = Double(upper.w) >= narrowAspect * height
                    && Double(lower.x) >= Double(upper.x) + 0.4 * Double(upper.w)
                    && lower.maxX <= upper.maxX + 2
                guard bothNarrow || rightLeg else { continue }
                blobs[i] = Box(x: x0, y: upper.y, w: x1 - x0, h: lower.maxY - upper.y)
                blobs.remove(at: j)
                if j < i { i -= 1 }
                merged = true
                break
            }
            if !merged { i += 1 }   // つないだときは、同じ塊にさらにつながるかけらがないか見直す
        }
        return blobs
    }

    // MARK: - 並び

    /// 左から右へ、同じ高さで近くに並ぶ塊をつないで並びにする。`blobs` は左から順に並んでいること。
    static func digitChains(_ blobs: [Box]) -> [[Box]] {
        var used = [Bool](repeating: false, count: blobs.count)
        var chains: [[Box]] = []
        for (i, first) in blobs.enumerated() where !used[i] && Double(first.h) >= bandMin {
            var chain = [first]
            var lastIndex = i
            used[i] = true
            while chain.count < 5 {
                let last = chain[chain.count - 1]
                let referenceHeight = Double(chain.map(\.h).max() ?? 0)
                let top = chain.map(\.y).min() ?? 0, bottom = chain.map(\.maxY).max() ?? 0
                var next: Int?
                var j = lastIndex + 1
                while j < blobs.count {
                    defer { j += 1 }
                    let c = blobs[j]
                    if used[j] || c.x <= last.x { continue }
                    let gap = Double(c.x - last.maxX)
                    if gap > narrowDigitGap * referenceHeight { break }   // 左から順なので、これより先はもっと遠い
                    if gap < -2 { continue }
                    let shared = Double(min(bottom, c.maxY) - max(top, c.y))
                    if shared < 0.7 * min(Double(c.h), referenceHeight) { continue }
                    if Double(c.h) < 0.8 * referenceHeight || Double(c.h) > 1.25 * referenceHeight { continue }
                    if gap > (c.isNarrow ? narrowDigitGap : digitGap) * referenceHeight { continue }
                    next = j
                    break
                }
                guard let found = next else { break }
                chain.append(blobs[found])
                used[found] = true
                lastIndex = found
            }
            if chain.count == 1 {
                used[i] = false   // 1 個だけの並びは、あとで先頭の「1」として使えるよう戻す
            } else {
                chains.append(chain)
            }
        }
        // 先頭の「1」は背が低く表示される機種がある。2 桁の並びの左隣にある細い塊を「1」として加える。
        for index in chains.indices where chains[index].count == 2 {
            let first = chains[index][0], second = chains[index][1]
            let referenceHeight = Double(max(first.h, second.h))
            // 段が傾いて写っていることがあるので、2 桁の傾きから「1」があるはずの高さを求める。
            let slope = Double(second.maxY - first.maxY) / Double(max(1, second.x - first.x))
            for (j, c) in blobs.enumerated() where !used[j] {
                let gap = Double(first.x - c.maxX)
                guard gap >= 0, gap <= digitGap * referenceHeight, c.isNarrow,
                      Double(c.h) >= 0.5 * referenceHeight, Double(c.h) <= 1.25 * referenceHeight else { continue }
                let shift = slope * Double(c.maxX - first.maxX)
                guard abs(Double(c.maxY) - (Double(first.maxY) + shift)) <= 0.2 * referenceHeight,
                      Double(c.y) >= Double(first.y) + shift - 0.2 * referenceHeight else { continue }
                chains[index].insert(c, at: 0)
                used[j] = true
                break
            }
        }
        return chains
    }

    // MARK: - 数字の判定

    /// 並びを数字として読む。読めない桁があれば nil。
    private static func readRow(_ chain: [Box], mask: Plane, ink: Plane, ratio: Double) -> Row? {
        // 斜体の補正：桁の幅の合計がいちばん小さくなる傾きを選ぶ。
        var bestShear = 0.0
        var bestWidth: Int?
        for shear in [-0.1, 0.0, 0.1, 0.2] {
            var total = 0
            for box in chain {
                let range = Cell(mask, box, shear: shear).inkColumns
                total += range.count
            }
            if bestWidth == nil || Double(total) < Double(bestWidth!) - 0.5 {
                bestShear = shear
                bestWidth = total
            }
        }
        // 点灯していないセグメントがうっすら写ることがある。段の中で極端に薄い桁は数字として扱わない。
        let strengths = chain.map { percentile90(ink, $0) }
        guard let strongest = strengths.max(), let weakest = strengths.min(), weakest >= 0.45 * strongest else { return nil }

        var text = ""
        var margin = 1.0
        for box in chain {
            let maskCell = Cell(mask, box, shear: bestShear)
            let columns = maskCell.inkColumns
            let inkCell = Cell(ink, box, shear: bestShear)
            let narrow = Double(columns.count) < narrowAspect * Double(box.h)
            guard let (digit, digitMargin) = classify(ink: inkCell, mask: maskCell, columns: columns, narrow: narrow) else {
                return nil
            }
            text += String(digit)
            margin = min(margin, digitMargin)
        }
        if chain.count < 3, text.allSatisfy({ $0 == "1" }) { return nil }   // 「11」は枠線や目盛りの見間違いが多い

        let x0 = chain.map(\.x).min()!, y0 = chain.map(\.y).min()!
        let x1 = chain.map(\.maxX).max()!, y1 = chain.map(\.maxY).max()!
        return Row(
            text: text,
            box: PixelRect(x: Double(x0) / ratio, y: Double(y0) / ratio, width: Double(x1 - x0) / ratio, height: Double(y1 - y0) / ratio),
            digitHeight: Double(chain.map(\.h).max()!) / ratio,
            margin: margin,
            isPartial: false
        )
    }

    /// 1 桁ぶんの切り出し（斜体をまっすぐにしたもの）。
    struct Cell {
        var width: Int
        var height: Int
        var values: [UInt8]

        /// x' = x + shear × (y − 中央)。行ごとに整数だけずらす。
        init(_ plane: Plane, _ box: Box, shear: Double) {
            let pad = Int(abs(shear) * Double(box.h) / 2) + 1
            width = box.w + 2 * pad
            height = box.h
            values = [UInt8](repeating: 0, count: width * height)
            for y in 0..<box.h {
                let shift = Int((shear * (Double(y) - Double(box.h - 1) / 2)).rounded(.toNearestOrEven))
                let source = (box.y + y) * plane.width + box.x
                let target = y * width + pad + shift
                for x in 0..<box.w { values[target + x] = plane.pixels[source + x] }
            }
        }

        /// 画素のある列の範囲。
        var inkColumns: Range<Int> {
            var first: Int?, last = 0
            for x in 0..<width {
                var any = false
                for y in 0..<height where values[y * width + x] > 0 { any = true; break }
                if any {
                    if first == nil { first = x }
                    last = x
                }
            }
            guard let start = first else { return 0..<width }
            return start..<(last + 1)
        }
    }

    /// 7 か所それぞれで、いちばん濃い線（行または列の平均）の濃さを返す。`binary` のときは画素の有無（0〜1）で数える。
    static func segmentValues(_ cell: Cell, columns: Range<Int>, binary: Bool) -> [Double] {
        let w = Double(columns.count), h = Double(cell.height)
        func value(_ x: Int, _ y: Int) -> Double {
            let v = cell.values[y * cell.width + columns.lowerBound + x]
            return binary ? (v > 0 ? 1 : 0) : Double(v)
        }
        func span(_ from: Double, _ to: Double, _ size: Double) -> Range<Int> {
            let start = Int(from * size)
            return start..<min(Int(size), max(Int(to * size), start + 1))
        }
        func horizontal(_ y0: Double, _ y1: Double) -> Double {
            let xs = span(0.3, 0.7, w), ys = span(y0, y1, h)
            guard !xs.isEmpty, !ys.isEmpty else { return 0 }
            var best = 0.0
            for y in ys {
                var sum = 0.0
                for x in xs { sum += value(x, y) }
                best = max(best, sum / Double(xs.count))
            }
            return best
        }
        func vertical(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Double {
            let xs = span(x0, x1, w), ys = span(y0, y1, h)
            guard !xs.isEmpty, !ys.isEmpty else { return 0 }
            var best = 0.0
            for x in xs {
                var sum = 0.0
                for y in ys { sum += value(x, y) }
                best = max(best, sum / Double(ys.count))
            }
            return best
        }
        return [
            horizontal(0.0, 0.2), vertical(0.6, 1.0, 0.14, 0.42), vertical(0.6, 1.0, 0.58, 0.86), horizontal(0.8, 1.0),
            vertical(0.0, 0.4, 0.58, 0.86), vertical(0.0, 0.4, 0.14, 0.42), horizontal(0.38, 0.62),
        ]
    }

    private static func classify(ink: Cell, mask: Cell, columns: Range<Int>, narrow: Bool) -> (Int, Double)? {
        if narrow { return (1, 0.25) }
        let values = segmentValues(ink, columns: columns, binary: false)
        guard let top = values.max(), top > 0 else { return nil }
        let relative = values.map { $0 / top }
        let coverage = segmentValues(mask, columns: columns, binary: true)
        var lit: [Bool] = []
        var margin = 1.0
        for (level, covered) in zip(relative, coverage) {
            // 点灯とみなす条件：十分に濃い、または、やや薄いが線としてつながっている。
            // 余裕は、判定が逆になるまでにどれだけ離れているか。
            let faint = min(level - faintLitLevel, covered - faintCoverage)
            let distance = max(level - litLevel, faint)
            lit.append(distance >= 0)
            margin = min(margin, abs(distance))
        }
        guard let digit = patterns[lit] else { return nil }
        return (digit, margin)
    }

    /// 塊の中のインクの濃さの 90 パーセンタイル（線形補間）。
    private static func percentile90(_ ink: Plane, _ box: Box) -> Double {
        var values: [UInt8] = []
        values.reserveCapacity(box.w * box.h)
        for y in box.y..<box.maxY {
            let base = y * ink.width
            values.append(contentsOf: ink.pixels[(base + box.x)..<(base + box.maxX)])
        }
        guard !values.isEmpty else { return 0 }
        values.sort()
        let position = 0.9 * Double(values.count - 1)
        let lower = Int(position), upper = min(values.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return Double(values[lower]) * (1 - fraction) + Double(values[upper]) * fraction
    }

    // MARK: - 上・下・脈拍を選ぶ

    /// 上下に並んだ 2 段（上の血圧・下の血圧）と、その下の脈拍を選ぶ。大きく、はっきり読めた組を優先する。
    static func choose(_ rows: [Row]) -> Reading? {
        var best: (score: Double, upper: Row, lower: Row)?
        for upper in rows where upper.margin >= minimumMargin {
            for lower in rows where lower.margin >= minimumMargin && isStacked(upper, lower) {
                let systolic = upper.value, diastolic = lower.value
                guard (60...280).contains(systolic), (30...180).contains(diastolic), systolic > diastolic else { continue }
                // 上にもう 1 段、同じ大きさの段があるなら、この組の上の段は「上の血圧」ではない
                // （先頭の「1」を読み落とした段を飛ばして、下の血圧と脈拍を上下と取り違えないため）。
                if rows.contains(where: { $0 != upper && $0 != lower && isStacked($0, upper) }) { continue }
                var score = (upper.digitHeight + lower.digitHeight) / 2 * quality(upper) * quality(lower)
                if (90...200).contains(systolic) { score *= 1.15 }
                if (50...110).contains(diastolic) { score *= 1.15 }
                if (20...100).contains(systolic - diastolic) { score *= 1.1 }
                if best == nil || score > best!.score { best = (score, upper, lower) }
            }
        }
        guard let (_, upper, lower) = best else { return nil }

        var pulse: (score: Double, row: Row)?
        for row in rows where row != upper && row != lower && overlap(row, upper) <= 0.1 && overlap(row, lower) <= 0.1 {
            // 脈拍も、判定がきわどい段は採用しない（誤った脈拍を出すより、空欄にして手で入れてもらう）。
            guard row.margin >= minimumMargin,
                  row.box.y >= lower.box.y + 0.6 * lower.box.height,
                  row.box.y - lower.box.maxY <= lower.box.height,
                  row.digitHeight <= 1.15 * lower.digitHeight, row.digitHeight >= 0.35 * lower.digitHeight,
                  row.box.maxX >= lower.box.x, row.box.x <= lower.box.maxX + lower.digitHeight,
                  (30...220).contains(row.value) else { continue }
            let score = row.digitHeight * quality(row)
            if pulse == nil || score > pulse!.score { pulse = (score, row) }
        }
        return Reading(
            systolic: upper.value, diastolic: lower.value, pulse: pulse?.row.value,
            margin: min(upper.margin, lower.margin)
        )
    }

    /// `upper` のすぐ下に、同じ大きさで右端のそろった `lower` がある。
    private static func isStacked(_ upper: Row, _ lower: Row) -> Bool {
        guard upper != lower, overlap(upper, lower) <= 0.1 else { return false }
        guard lower.box.y > upper.box.y + 0.6 * upper.box.height,
              lower.box.y - upper.box.maxY <= 0.9 * upper.box.height else { return false }
        guard min(upper.digitHeight, lower.digitHeight) / max(upper.digitHeight, lower.digitHeight) >= 0.78 else { return false }
        let height = (upper.digitHeight + lower.digitHeight) / 2
        return abs(upper.box.maxX - lower.box.maxX) <= 0.9 * height
    }

    private static func overlap(_ a: Row, _ b: Row) -> Double {
        let width = max(0, min(a.box.maxX, b.box.maxX) - max(a.box.x, b.box.x))
        let height = max(0, min(a.box.maxY, b.box.maxY) - max(a.box.y, b.box.y))
        return width * height / max(1e-6, min(a.box.width * a.box.height, b.box.width * b.box.height))
    }

    private static func quality(_ row: Row) -> Double {
        (1 + min(row.margin, 0.4)) * (row.isPartial ? 0.85 : 1)
    }

    // MARK: - 画像処理

    /// 処理用の 8 ビット画像。`GrayImage` と同じ並びだが、添字の検査を省いて速く回すために分けている。
    struct Plane: Sendable {
        var width: Int
        var height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int, fill: UInt8) {
            self.width = width
            self.height = height
            pixels = [UInt8](repeating: fill, count: width * height)
        }

        init(_ image: GrayImage) {
            width = image.width
            height = image.height
            pixels = image.pixels
        }

        /// 長辺が `longSide` になるよう、面積平均で縮小する（拡大はしない）。
        func resized(longSide: Int) -> Plane {
            let ratio = Double(longSide) / Double(max(width, height))
            guard ratio < 1 else { return self }
            let newWidth = max(1, Int((Double(width) * ratio).rounded()))
            let newHeight = max(1, Int((Double(height) * ratio).rounded()))

            // 横方向
            var rowsOut = [Float](repeating: 0, count: newWidth * height)
            let xTaps = Plane.areaTaps(from: width, to: newWidth)
            pixels.withUnsafeBufferPointer { source in
                rowsOut.withUnsafeMutableBufferPointer { target in
                    for y in 0..<height {
                        let base = y * width
                        for (x, taps) in xTaps.enumerated() {
                            var sum: Float = 0
                            for tap in taps { sum += Float(source[base + tap.index]) * tap.weight }
                            target[y * newWidth + x] = sum
                        }
                    }
                }
            }
            // 縦方向
            var out = Plane(width: newWidth, height: newHeight, fill: 0)
            let yTaps = Plane.areaTaps(from: height, to: newHeight)
            rowsOut.withUnsafeBufferPointer { source in
                out.pixels.withUnsafeMutableBufferPointer { target in
                    for (y, taps) in yTaps.enumerated() {
                        for x in 0..<newWidth {
                            var sum: Float = 0
                            for tap in taps { sum += source[tap.index * newWidth + x] * tap.weight }
                            target[y * newWidth + x] = UInt8(max(0, min(255, sum.rounded())))
                        }
                    }
                }
            }
            return out
        }

        /// 縮小後の各画素が、元のどの画素をどの重みで平均するか。
        private static func areaTaps(from source: Int, to target: Int) -> [[(index: Int, weight: Float)]] {
            let scale = Double(source) / Double(target)
            return (0..<target).map { i in
                let start = Double(i) * scale, end = min(Double(source), Double(i + 1) * scale)
                var taps: [(index: Int, weight: Float)] = []
                var index = Int(start)
                while index < source, Double(index) < end {
                    let covered = min(end, Double(index + 1)) - max(start, Double(index))
                    if covered > 1e-9 { taps.append((index, Float(covered / (end - start)))) }
                    index += 1
                }
                return taps
            }
        }

        /// 窓（手前 `before` 画素〜先 `after` 画素）の中の最大値または最小値。画像の外は数えない。
        /// `vertical` を省くと横・縦の両方向にかける。
        func extreme(before: Int, after: Int, takeMax: Bool, vertical: Bool? = nil) -> Plane {
            guard let vertical else {
                return extreme(before: before, after: after, takeMax: takeMax, vertical: false)
                    .extreme(before: before, after: after, takeMax: takeMax, vertical: true)
            }
            guard before > 0 || after > 0 else { return self }
            var out = self
            let lineCount = vertical ? width : height
            let length = vertical ? height : width
            let step = vertical ? width : 1
            // 単調な待ち行列で、窓の中の最大（最小）を 1 画素あたり一定の手間で求める。
            var queue = [Int](repeating: 0, count: length)
            pixels.withUnsafeBufferPointer { source in
                out.pixels.withUnsafeMutableBufferPointer { target in
                    queue.withUnsafeMutableBufferPointer { queue in
                        for line in 0..<lineCount {
                            let base = vertical ? line : line * width
                            var head = 0, tail = 0, next = 0
                            for i in 0..<length {
                                let last = min(length - 1, i + after)
                                while next <= last {
                                    let value = source[base + next * step]
                                    while tail > head {
                                        let back = source[base + queue[tail - 1] * step]
                                        if takeMax ? back <= value : back >= value { tail -= 1 } else { break }
                                    }
                                    queue[tail] = next
                                    tail += 1
                                    next += 1
                                }
                                while queue[head] < i - before { head += 1 }
                                target[base + i * step] = source[base + queue[head] * step]
                            }
                        }
                    }
                }
            }
            return out
        }
    }

    /// インク＝周りの明るさ（グレースケールのクロージング）との差。暗い線ほど大きい。
    static func inkMap(_ gray: Plane) -> Plane {
        let smooth = boxBlur3(gray)
        let radius = backgroundWindow / 2
        let background = smooth
            .extreme(before: radius, after: radius, takeMax: true)
            .extreme(before: radius, after: radius, takeMax: false)
        var ink = Plane(width: gray.width, height: gray.height, fill: 0)
        for i in 0..<ink.pixels.count {
            let difference = Int(background.pixels[i]) - Int(smooth.pixels[i])
            ink.pixels[i] = UInt8(max(0, difference))
        }
        return ink
    }

    private static func boxBlur3(_ plane: Plane) -> Plane {
        let w = plane.width, h = plane.height
        // 横の 3 画素の和 → 縦の 3 行の和。端は入っている画素だけで平均する。
        var sums = [UInt16](repeating: 0, count: w * h)
        for y in 0..<h {
            let base = y * w
            for x in 0..<w {
                var sum = UInt16(plane.pixels[base + x])
                if x > 0 { sum += UInt16(plane.pixels[base + x - 1]) }
                if x + 1 < w { sum += UInt16(plane.pixels[base + x + 1]) }
                sums[base + x] = sum
            }
        }
        var out = plane
        for y in 0..<h {
            let rows = (y > 0 ? 1 : 0) + 1 + (y + 1 < h ? 1 : 0)
            for x in 0..<w {
                var sum = Int(sums[y * w + x])
                if y > 0 { sum += Int(sums[(y - 1) * w + x]) }
                if y + 1 < h { sum += Int(sums[(y + 1) * w + x]) }
                let columns = (x > 0 ? 1 : 0) + 1 + (x + 1 < w ? 1 : 0)
                out.pixels[y * w + x] = UInt8((Double(sum) / Double(rows * columns)).rounded())
            }
        }
        return out
    }

    /// 横または縦に `minLength` 画素以上続く線（液晶の枠など）を、少し太らせてから取り除く。
    private static func removeLongLines(_ mask: Plane, minLength: Int) -> Plane {
        let w = mask.width, h = mask.height
        var lines = Plane(width: w, height: h, fill: 0)
        for y in 0..<h {
            var x = 0
            while x < w {
                guard mask.pixels[y * w + x] > 0 else { x += 1; continue }
                let start = x
                while x < w, mask.pixels[y * w + x] > 0 { x += 1 }
                if x - start >= minLength {
                    for xx in start..<x { lines.pixels[y * w + xx] = 255 }
                }
            }
        }
        for x in 0..<w {
            var y = 0
            while y < h {
                guard mask.pixels[y * w + x] > 0 else { y += 1; continue }
                let start = y
                while y < h, mask.pixels[y * w + x] > 0 { y += 1 }
                if y - start >= minLength {
                    for yy in start..<y { lines.pixels[yy * w + x] = 255 }
                }
            }
        }
        let grown = lines.extreme(before: 1, after: 1, takeMax: true)
        var out = mask
        for i in 0..<out.pixels.count where grown.pixels[i] > 0 { out.pixels[i] = 0 }
        return out
    }
}

extension BPParseResult {
    /// 液晶の数字の形と並びから読んだ結果。
    ///
    /// 確度は、印字ラベルつきで文字認識がはっきり読めた場合（0.9 以上）より低く、
    /// 文字認識があやふやな場合（0.8 前後以下）より高くしている。7 セグメントの数字は文字認識の誤読が多く、
    /// 食い違ったときは形から読んだほうが当たりやすいため。脈拍まで読めれば 3 段の並びがそろっているので少し上げ、
    /// 点灯・消灯の判定がきわどい桁があれば下げる。
    init(_ reading: SegmentDisplayReader.Reading) {
        var confidence = 0.8
        var reasons = ["液晶の数字の形から読み取りました"]
        if reading.pulse != nil {
            confidence += 0.05
            reasons.append("脈拍は位置から推定しました")
        }
        if reading.margin < 0.12 {
            confidence -= 0.1
        }
        self.init(
            systolic: reading.systolic,
            diastolic: reading.diastolic,
            pulse: reading.pulse,
            confidence: confidence,
            explanation: reasons.joined(separator: "・")
        )
    }
}
