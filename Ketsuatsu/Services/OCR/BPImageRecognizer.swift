import CoreImage
import Foundation
import UIKit
import Vision

/// 写真から血圧計の表示を読み取る。
///
/// 液晶（7 セグメント表示）は汎用の文字認識が苦手なため、読み方を変えて何度か読み、
/// 結果を `BPReadingCombiner` でまとめる。
///
/// 1. 元の写真をそのまま読む（2 番目以降の認識候補も使う）
/// 2. 本体に印字された SYS／DIA／PULSE などを手がかりに、7 セグメントの数字を直接読む
/// 3. ここまでで 2 つの読み方が一致しなければ、セグメントをつないだ画像で読み直す
/// 4. それでも一致しなければ、コントラストを強めた画像で読み直す
///
/// 一致した時点でやめるので、読みやすい写真ほど早く終わる。
enum BPImageRecognizer {

    struct Output: Sendable {
        var result: BPParseResult
        /// 認識した生テキスト。うまくいかないときの確認用に画面へ出す。
        var recognizedLines: [String]
    }

    enum RecognizerError: LocalizedError {
        case invalidImage
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "画像を読み込めませんでした。"
            case .recognitionFailed(let message):
                return "文字の読み取りに失敗しました。（\(message)）"
            }
        }
    }

    /// 読み取りに使う画像の長辺。液晶の数字には十分で、大きな写真でも時間がかかりすぎない。
    private static let maxDimension: CGFloat = 2400

    static func recognize(image: UIImage) async throws -> Output {
        // 向きを補正した画像にそろえる（7 セグメントの読み取りと画像の加工は、上が上である前提のため）。
        guard let upright = uprightImage(from: image) else {
            throw RecognizerError.invalidImage
        }
        let aspectRatio = CGFloat(upright.width) / CGFloat(upright.height)
        func parse(_ items: [OCRTextItem]) -> BPParseResult {
            BPTextParser.parse(items, aspectRatio: aspectRatio)
        }

        // 1. 元の写真
        let rawItems = try await textItems(in: upright)
        var results = [parse(rawItems)]
        let alternativeItems = BPTextParser.preferringNumericAlternatives(rawItems)
        if alternativeItems != rawItems {
            // 同じ認識結果から作った読み方なので、上下の値が変わったときだけ別の読み方として数える
            // （同じ値を 2 回数えて「一致した」と扱わないため）。変わったのが脈拍だけなら脈拍を補う。
            let alternative = parse(alternativeItems)
            if alternative.systolic != results[0].systolic || alternative.diastolic != results[0].diastolic {
                results.append(alternative)
            } else if results[0].pulse == nil {
                results[0].pulse = alternative.pulse
            }
        }

        // 2. 印字ラベルを手がかりに 7 セグメントを直接読む
        let labels = BPTextParser.printedLabelItems(in: rawItems)
        if !labels.isEmpty, let gray = GrayImage(cgImage: upright) {
            let digits = SevenSegmentReader.read(gray, labelBoxes: labels.map(\.boundingBox))
            if !digits.isEmpty {
                results.append(parse(labels + digits))
            }
        }

        // 3〜4. 一致するまで、加工した画像で読み直す
        let variants: [(CGImage) -> CGImage?] = [joinSegments, enhanceForSegmentDisplay]
        for variant in variants {
            if BPReadingCombiner.hasAgreement(results) { break }
            guard let processed = variant(upright) else { continue }
            let items = try await textItems(in: processed)
            results.append(parse(items))
        }

        return Output(result: BPReadingCombiner.combine(results), recognizedLines: rawItems.map(\.text))
    }

    /// テキスト認識だけを行う（テスト用のフックとしても使える）。
    static func textItems(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [OCRTextItem] {
        try await withCheckedThrowingContinuation { continuation in
            // Vision の処理は同期的で重いので、専用のキューへ逃がす。
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                // 数字の羅列が多く、辞書補正はむしろ誤読の原因になる。
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US", "ja-JP"]
                request.minimumTextHeight = 0.02

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: RecognizerError.recognitionFailed(error.localizedDescription))
                    return
                }
                let items: [OCRTextItem] = (request.results ?? []).compactMap { observation in
                    // 7 セグメントの数字は 1 番目の候補が数字にならないことがあるので、3 番目まで残す。
                    let candidates = observation.topCandidates(3)
                    guard let candidate = candidates.first else { return nil }
                    return OCRTextItem(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence,
                        alternatives: candidates.dropFirst().map(\.string)
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    // MARK: - 画像処理

    private static let ciContext = CIContext(options: nil)

    /// 向きを補正し、長辺を `maxDimension` 以下にした画像を作る。
    private static func uprightImage(from image: UIImage) -> CGImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let ratio = min(1, maxDimension / max(pixelWidth, pixelHeight))
        let size = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    /// 液晶の暗い数字を太らせて、セグメントのすき間を埋める（数字がつながった線になり、Vision が読みやすくなる）。
    /// 実物の写真での確認では、この処理だけで読める写真が 2/7 から 4/7 に増えた。
    private static func joinSegments(_ cgImage: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        guard let grayscale = CIFilter(name: "CIColorControls"),
              let minimum = CIFilter(name: "CIMorphologyMinimum") else { return nil }
        grayscale.setValue(input, forKey: kCIInputImageKey)
        grayscale.setValue(0.0, forKey: kCIInputSaturationKey)
        minimum.setValue(grayscale.outputImage, forKey: kCIInputImageKey)
        // 太らせる量は画像の大きさに合わせる（長辺の 1/240 ほど）。
        let radius = max(1.0, Double(max(cgImage.width, cgImage.height)) / 240)
        minimum.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = minimum.outputImage?.cropped(to: input.extent) else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }

    /// セグメント液晶を読みやすくする（グレースケール化 + コントラスト強調 + シャープ化）。
    private static func enhanceForSegmentDisplay(_ cgImage: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(input, forKey: kCIInputImageKey)
        controls.setValue(0.0, forKey: kCIInputSaturationKey)
        controls.setValue(2.0, forKey: kCIInputContrastKey)
        controls.setValue(0.05, forKey: kCIInputBrightnessKey)

        var output = controls.outputImage
        if let sharpen = CIFilter(name: "CISharpenLuminance"), let current = output {
            sharpen.setValue(current, forKey: kCIInputImageKey)
            sharpen.setValue(0.8, forKey: "inputSharpness")
            output = sharpen.outputImage ?? current
        }
        guard let output else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }
}
