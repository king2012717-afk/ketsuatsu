import CoreImage
import Foundation
import UIKit
import Vision

/// 写真から血圧計の表示を読み取る。
///
/// 1 回目は元画像のまま、読み取れなければコントラストを強調した画像で再挑戦する。
/// 液晶（セグメント表示）は白飛び・低コントラストで失敗しやすいため。
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

    static func recognize(image: UIImage) async throws -> Output {
        guard let cgImage = image.cgImage ?? image.ciImage.flatMap(render) else {
            throw RecognizerError.invalidImage
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let items = try await textItems(in: cgImage, orientation: orientation)
        let first = BPTextParser.parse(items)
        if first.hasBloodPressure {
            return Output(result: first, recognizedLines: items.map(\.text))
        }

        // 2 回目: コントラストを強調して再挑戦
        guard let enhanced = enhanceForSegmentDisplay(cgImage) else {
            return Output(result: first, recognizedLines: items.map(\.text))
        }
        let retryItems = try await textItems(in: enhanced, orientation: orientation)
        let retry = BPTextParser.parse(retryItems)

        if retry.hasBloodPressure || retry.confidence > first.confidence {
            return Output(result: retry, recognizedLines: retryItems.map(\.text))
        }
        return Output(result: first, recognizedLines: items.map(\.text))
    }

    /// テキスト認識だけを行う（テスト用のフックとしても使える）。
    static func textItems(in cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [OCRTextItem] {
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
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return OCRTextItem(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    // MARK: - 画像処理

    private static let ciContext = CIContext(options: nil)

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

    private static func render(_ ciImage: CIImage) -> CGImage? {
        ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
