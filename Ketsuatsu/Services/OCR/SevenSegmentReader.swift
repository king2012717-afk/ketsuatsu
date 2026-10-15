import CoreGraphics
import Foundation

/// 8 ビットのグレースケール画像（左上が原点、行優先）。
/// 画像処理を UIKit / Core Image から切り離し、単体テストできるようにするための入れ物。
struct GrayImage: Sendable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "画素数が幅 × 高さと一致しない")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

/// 血圧計の液晶（7 セグメント表示）の数字を、セグメントの点灯パターンから読み取る。
///
/// 汎用の文字認識（Vision）は 7 セグメントの数字を苦手とする。一方、本体に印字された
/// 「SYS」「DIA」「PULSE」などのラベルは普通の文字なので確実に読める。そこで、
///
/// 1. ラベルの位置から、その右側にある液晶の範囲を決める
/// 2. 明るさの局所的な差で数字のセグメントを取り出し、液晶の枠線を取り除く
/// 3. 同じ桁のセグメントをつないで 1 桁ずつに分け、段ごとにまとめる
/// 4. 各桁の 7 か所が点灯しているかで数字を決める
///
/// の順に読む。結果は `OCRTextItem` として返すので、ラベルと一緒に `BPTextParser` へ渡せる。
enum SevenSegmentReader {

    /// - Parameters:
    ///   - image: 写真全体のグレースケール画像
    ///   - labelBoxes: 印字ラベルの位置（Vision の正規化座標。原点は左下）
    /// - Returns: 読み取れた数字の段。座標は Vision と同じ正規化座標。
    static func read(_ image: GrayImage, labelBoxes: [CGRect]) -> [OCRTextItem] {
        guard !labelBoxes.isEmpty, image.width > 0, image.height > 0 else { return [] }

        // ラベルの位置を画素の座標（左上原点）に直す。
        let W = CGFloat(image.width), H = CGFloat(image.height)
        let labels = labelBoxes.map { box in
            CGRect(x: box.minX * W, y: (1 - box.maxY) * H, width: box.width * W, height: box.height * H)
        }
        let labelHeight = labels.map(\.height).reduce(0, +) / CGFloat(labels.count)
        guard labelHeight >= 6 else { return [] }

        // ラベルの右側が液晶。ラベルが画像の右端に寄っている場合は、この配置ではない。
        let labelRight = labels.map(\.maxX).max() ?? 0
        guard labelRight < W * 0.8 else { return [] }
        let top = max(0, (labels.map(\.minY).min() ?? 0) - labelHeight * 2.5)
        let bottom = min(H, (labels.map(\.maxY).max() ?? 0) + labelHeight * 1.5)
        let left = labelRight + labelHeight * 0.3
        let right = min(W, labelRight + labelHeight * 12)
        guard right - left > labelHeight * 2, bottom - top > labelHeight * 2 else { return [] }

        // ラベルの高さが 30 画素前後になるよう縮小して処理する（大きな写真でも速く、条件をそろえるため）。
        let scale = max(1, Int(labelHeight / 30))
        let region = crop(image, x: Int(left), y: Int(top), width: Int(right - left), height: Int(bottom - top), scale: scale)
        let lh = labelHeight / CGFloat(scale)

        let digits = findDigitRows(in: region, labelHeight: lh)
        return digits.map { row in
            // 縮小前・切り出し前の座標へ戻し、Vision と同じ正規化座標にする。
            let x = (CGFloat(row.box.minX) * CGFloat(scale) + left) / W
            let y = (CGFloat(row.box.minY) * CGFloat(scale) + top) / H
            let w = CGFloat(row.box.width) * CGFloat(scale) / W
            let h = CGFloat(row.box.height) * CGFloat(scale) / H
            return OCRTextItem(
                text: row.text,
                boundingBox: CGRect(x: x, y: 1 - y - h, width: w, height: h),
                confidence: 0.8
            )
        }
    }

    // MARK: - 数字の段を探す

    struct DigitRow: Equatable {
        var text: String
        /// 処理用の画像での位置（左上原点、画素）
        var box: CGRect
    }

    static func findDigitRows(in region: GrayImage, labelHeight lh: CGFloat) -> [DigitRow] {
        // 1. 周りより暗い画素をセグメントとして取り出す
        var mask = adaptiveThreshold(boxBlur3(region), block: Int(lh * 1.6) | 1, offset: 8)
        mask = open2x2(mask)
        // 2. 液晶の枠のような長い直線を取り除く（セグメントより十分長いものだけ）
        mask = removeLongLines(mask, minLength: Int(lh * 3.2))

        // 3. 同じ桁のセグメントを縦方向につなぎ、ひとかたまりずつに分ける
        let merged = close(mask, kernelWidth: max(1, Int(lh * 0.05)), kernelHeight: max(3, Int(lh * 0.25)))
        let blobs = connectedComponents(merged).filter { blob in
            CGFloat(blob.height) >= lh * 1.2
                && CGFloat(blob.width) <= CGFloat(blob.height) * 1.1
                && blob.height < mask.height * 6 / 10
        }

        // 4. 高さのそろった塊を、段 → 数値（横に離れていれば別の数値）にまとめる
        var rows: [[Blob]] = []
        for blob in blobs.sorted(by: { $0.minY < $1.minY }) {
            if let index = rows.firstIndex(where: { row in
                let reference = row[0]
                // 高さの差は 15% まで。実機の「1」はほかの数字の 93〜95% の高さで、この範囲に入る。
                // 広げると、脈拍の小窓の枠線のような細い縦線を「1」として取り込んでしまう（「74」→「174」）。
                return abs(reference.centerY - blob.centerY) < 0.35 * CGFloat(reference.height)
                    && abs(CGFloat(reference.height - blob.height)) < 0.15 * CGFloat(reference.height)
            }) {
                rows[index].append(blob)
            } else {
                rows.append([blob])
            }
        }

        var result: [DigitRow] = []
        for row in rows {
            for group in splitByGaps(row.sorted { $0.minX < $1.minX }) where (2...3).contains(group.count) {
                let digits = group.map { classify(mask, $0) }
                guard digits.allSatisfy({ $0 != nil }) else { continue }
                let box = group.map(\.rect).reduce(group[0].rect) { $0.union($1) }
                result.append(DigitRow(text: digits.map { String($0!) }.joined(), box: box))
            }
        }
        return result.sorted { $0.box.minY < $1.box.minY }
    }

    /// 横のすき間が大きいところで、別の数値として分ける（「72」と時刻「0:00」など）。
    /// 7 セグメントの「1」は桁の右側に寄って表示されるため、1 桁ぶん近いすき間までは同じ数値とみなす。
    private static func splitByGaps(_ sorted: [Blob]) -> [[Blob]] {
        var groups: [[Blob]] = []
        for blob in sorted {
            if let last = groups.last?.last, CGFloat(blob.minX - last.maxX) <= CGFloat(last.height) * 0.75 {
                groups[groups.count - 1].append(blob)
            } else {
                groups.append([blob])
            }
        }
        return groups
    }

    // MARK: - 1 桁の判定

    /// a〜g の 7 セグメント（上・右上・右下・下・左下・左上・中央）の点灯パターン。
    private static let patterns: [[Bool]: Int] = [
        [true, true, true, true, true, true, false]: 0,
        [false, true, true, false, false, false, false]: 1,
        [true, true, false, true, true, false, true]: 2,
        [true, true, true, true, false, false, true]: 3,
        [false, true, true, false, false, true, true]: 4,
        [true, false, true, true, false, true, true]: 5,
        [true, false, true, true, true, true, true]: 6,
        [false, false, true, true, true, true, true]: 6,  // 上の横棒がない「6」
        [true, true, true, false, false, false, false]: 7,
        [true, true, true, false, false, true, false]: 7,  // 左上の縦棒もある「7」
        [true, true, true, true, true, true, true]: 8,
        [true, true, true, true, false, true, true]: 9,
        [true, true, true, false, false, true, true]: 9,   // 下の横棒がない「9」
    ]

    static func classify(_ mask: GrayImage, _ blob: Blob) -> Int? {
        // 「1」は縦棒だけなので幅が狭い。
        if blob.isNarrow { return 1 }
        return patterns[segments(mask, blob)]
    }

    /// 桁の中の 7 か所それぞれが点灯しているか（a〜g の順）。
    static func segments(_ mask: GrayImage, _ blob: Blob) -> [Bool] {
        let w = CGFloat(blob.width), h = CGFloat(blob.height)
        func lit(_ y0: CGFloat, _ y1: CGFloat, _ x0: CGFloat, _ x1: CGFloat) -> Bool {
            let top = blob.minY + Int(y0 * h), bottom = max(blob.minY + Int(y1 * h), top + 1)
            let left = blob.minX + Int(x0 * w), right = max(blob.minX + Int(x1 * w), left + 1)
            var on = 0, total = 0
            for y in top..<min(bottom, mask.height) {
                for x in left..<min(right, mask.width) {
                    total += 1
                    if mask[x, y] > 0 { on += 1 }
                }
            }
            return total > 0 && Double(on) / Double(total) > 0.3
        }
        return [
            lit(0.00, 0.15, 0.3, 0.7),  // a 上
            lit(0.15, 0.42, 0.7, 1.0),  // b 右上
            lit(0.58, 0.85, 0.7, 1.0),  // c 右下
            lit(0.85, 1.00, 0.3, 0.7),  // d 下
            lit(0.58, 0.85, 0.0, 0.3),  // e 左下
            lit(0.15, 0.42, 0.0, 0.3),  // f 左上
            lit(0.42, 0.58, 0.3, 0.7),  // g 中央
        ]
    }

    // MARK: - 画像処理の部品

    /// 切り出しと縮小（scale × scale 画素の平均）を同時に行う。
    static func crop(_ image: GrayImage, x: Int, y: Int, width: Int, height: Int, scale: Int) -> GrayImage {
        let outW = max(1, width / scale), outH = max(1, height / scale)
        var out = [UInt8](repeating: 0, count: outW * outH)
        for oy in 0..<outH {
            for ox in 0..<outW {
                var sum = 0, count = 0
                for dy in 0..<scale {
                    let sy = y + oy * scale + dy
                    guard sy >= 0, sy < image.height else { continue }
                    for dx in 0..<scale {
                        let sx = x + ox * scale + dx
                        guard sx >= 0, sx < image.width else { continue }
                        sum += Int(image[sx, sy])
                        count += 1
                    }
                }
                out[oy * outW + ox] = count > 0 ? UInt8(sum / count) : 255
            }
        }
        return GrayImage(width: outW, height: outH, pixels: out)
    }

    static func boxBlur3(_ image: GrayImage) -> GrayImage {
        var out = image.pixels
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum = 0, count = 0
                for dy in -1...1 {
                    let yy = y + dy
                    guard yy >= 0, yy < image.height else { continue }
                    for dx in -1...1 {
                        let xx = x + dx
                        guard xx >= 0, xx < image.width else { continue }
                        sum += Int(image[xx, yy])
                        count += 1
                    }
                }
                out[y * image.width + x] = UInt8(sum / count)
            }
        }
        return GrayImage(width: image.width, height: image.height, pixels: out)
    }

    /// 周囲（block × block）の平均より `offset` 以上暗い画素を 255、それ以外を 0 にする。
    static func adaptiveThreshold(_ image: GrayImage, block: Int, offset: Int) -> GrayImage {
        let w = image.width, h = image.height
        // 積分画像で周囲の平均を素早く求める。
        var integral = [Int](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var rowSum = 0
            for x in 0..<w {
                rowSum += Int(image[x, y])
                integral[(y + 1) * (w + 1) + (x + 1)] = integral[y * (w + 1) + (x + 1)] + rowSum
            }
        }
        let radius = max(1, block / 2)
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - radius), y1 = min(h, y + radius + 1)
            for x in 0..<w {
                let x0 = max(0, x - radius), x1 = min(w, x + radius + 1)
                let sum = integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1]
                    - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0]
                let mean = sum / ((y1 - y0) * (x1 - x0))
                if Int(image[x, y]) < mean - offset { out[y * w + x] = 255 }
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    /// 2 × 2 のオープニング（小さな点のノイズを消す）。
    static func open2x2(_ mask: GrayImage) -> GrayImage {
        dilate(erode(mask, kernelWidth: 2, kernelHeight: 2), kernelWidth: 2, kernelHeight: 2)
    }

    static func close(_ mask: GrayImage, kernelWidth: Int, kernelHeight: Int) -> GrayImage {
        erode(dilate(mask, kernelWidth: kernelWidth, kernelHeight: kernelHeight), kernelWidth: kernelWidth, kernelHeight: kernelHeight)
    }

    static func dilate(_ mask: GrayImage, kernelWidth: Int, kernelHeight: Int) -> GrayImage {
        morph(mask, kernelWidth: kernelWidth, kernelHeight: kernelHeight, takeMax: true)
    }

    static func erode(_ mask: GrayImage, kernelWidth: Int, kernelHeight: Int) -> GrayImage {
        morph(mask, kernelWidth: kernelWidth, kernelHeight: kernelHeight, takeMax: false)
    }

    /// 長方形の窓での最大値（膨張）・最小値（収縮）。横と縦に分けて計算する。
    /// 画像の外は結果に影響しないものとして扱う。
    private static func morph(_ mask: GrayImage, kernelWidth: Int, kernelHeight: Int, takeMax: Bool) -> GrayImage {
        let w = mask.width, h = mask.height
        func pass(_ src: [UInt8], length: Int, horizontal: Bool) -> [UInt8] {
            guard length > 1 else { return src }
            let before = (length - 1) / 2, after = length / 2
            var dst = src
            for y in 0..<h {
                for x in 0..<w {
                    var value: UInt8 = takeMax ? 0 : 255
                    // 偶数の窓では、収縮と膨張で向きを反転させて位置がずれないようにする。
                    for d in (takeMax ? -after...before : -before...after) {
                        let xx = horizontal ? x + d : x
                        let yy = horizontal ? y : y + d
                        guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                        let v = src[yy * w + xx]
                        value = takeMax ? max(value, v) : min(value, v)
                    }
                    dst[y * w + x] = value
                }
            }
            return dst
        }
        let horizontal = pass(mask.pixels, length: kernelWidth, horizontal: true)
        return GrayImage(width: w, height: h, pixels: pass(horizontal, length: kernelHeight, horizontal: false))
    }

    /// 横または縦に `minLength` 画素以上続く線（液晶の枠など）を、少し太らせてから取り除く。
    static func removeLongLines(_ mask: GrayImage, minLength: Int) -> GrayImage {
        let w = mask.width, h = mask.height
        var lines = [UInt8](repeating: 0, count: w * h)
        // 横の線
        for y in 0..<h {
            var x = 0
            while x < w {
                guard mask[x, y] > 0 else { x += 1; continue }
                let start = x
                while x < w, mask[x, y] > 0 { x += 1 }
                if x - start >= minLength {
                    for xx in start..<x { lines[y * w + xx] = 255 }
                }
            }
        }
        // 縦の線
        for x in 0..<w {
            var y = 0
            while y < h {
                guard mask[x, y] > 0 else { y += 1; continue }
                let start = y
                while y < h, mask[x, y] > 0 { y += 1 }
                if y - start >= minLength {
                    for yy in start..<y { lines[yy * w + x] = 255 }
                }
            }
        }
        let grown = dilate(GrayImage(width: w, height: h, pixels: lines), kernelWidth: 5, kernelHeight: 5)
        var out = mask.pixels
        for i in out.indices where grown.pixels[i] > 0 { out[i] = 0 }
        return GrayImage(width: w, height: h, pixels: out)
    }

    struct Blob: Equatable {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var centerY: CGFloat { CGFloat(minY + maxY) / 2 }
        /// 縦棒だけの「1」のように幅が狭い塊。
        var isNarrow: Bool { CGFloat(width) < CGFloat(height) * 0.45 }
        var rect: CGRect { CGRect(x: minX, y: minY, width: width, height: height) }
    }

    /// 8 近傍でつながった画素の塊を求める。
    static func connectedComponents(_ mask: GrayImage) -> [Blob] {
        let w = mask.width, h = mask.height
        var visited = [Bool](repeating: false, count: w * h)
        var blobs: [Blob] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where mask.pixels[start] > 0 && !visited[start] {
            var blob = Blob(minX: start % w, minY: start / w, maxX: start % w, maxY: start / w)
            visited[start] = true
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % w, y = index / w
                blob.minX = min(blob.minX, x); blob.maxX = max(blob.maxX, x)
                blob.minY = min(blob.minY, y); blob.maxY = max(blob.maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                        let next = yy * w + xx
                        if mask.pixels[next] > 0 && !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            blobs.append(blob)
        }
        return blobs
    }
}
