import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 選んだ 1 枚の写真と、そこから分かった撮影日時。
struct PickedPhoto: Identifiable {
    let id = UUID()
    var image: UIImage
    /// Exif の撮影日時。取れなかった場合は nil。
    var capturedAt: Date?
}

/// カメラで 1 枚撮影する。血圧計の表示を撮る用途なので編集は許可しておく（トリミングで精度が上がる）。
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: ([PickedPhoto]) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = true
        controller.delegate = context.coordinator

        // 撮影の目安の枠とコツを常に出しておく。検出による警告ではないので、出過ぎて撮れなくなることはない。
        let hint = CameraHintOverlayView(frame: Self.screenBounds)
        controller.cameraOverlayView = hint
        context.coordinator.observeCaptureSession(hint: hint)
        return controller
    }

    private static var screenBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: ([PickedPhoto]) -> Void
        private var sessionObservers: [NSObjectProtocol] = []

        init(onCapture: @escaping ([PickedPhoto]) -> Void) {
            self.onCapture = onCapture
        }

        deinit {
            for observer in sessionObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        /// 撮影すると、撮った写真の確認（移動と拡大縮小）の画面に変わり、カメラの映像が止まる。
        /// そのあいだは枠と注意書きを隠し、「再撮影」で映像が戻ったら再び出す。
        func observeCaptureSession(hint: UIView) {
            let center = NotificationCenter.default
            sessionObservers = [
                center.addObserver(forName: .AVCaptureSessionDidStopRunning, object: nil, queue: .main) { [weak hint] _ in
                    UIView.animate(withDuration: 0.15) { hint?.alpha = 0 }
                },
                center.addObserver(forName: .AVCaptureSessionDidStartRunning, object: nil, queue: .main) { [weak hint] _ in
                    UIView.animate(withDuration: 0.15) { hint?.alpha = 1 }
                },
            ]
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) else {
                onCapture([])
                return
            }
            // 撮ったばかりなので撮影日時は「いま」。
            onCapture([PickedPhoto(image: image, capturedAt: Date())])
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture([])
        }
    }
}

/// カメラの画面に重ねる、撮影の目安の枠と一言。
///
/// - 枠：撮った写真は確認画面で正方形に切り取られ、その正方形が読み取りに使われる（`allowsEditing`）。
///   正方形はカメラの映像（縦長 3:4）の中央にあるので、その内側に一回り小さい枠を出し、
///   血圧計の表示部分と「最高・最低・脈拍」などの文字を大きく収めてもらう（遠くて小さいと読み取りにくい）。
/// - 一言：反射やぼやけを検出して警告するのではなく、常に同じ内容を出す（出過ぎて撮れなくなるのを避ける）。
/// - 触っても下のカメラの操作（シャッター・フラッシュなど）の邪魔にならないよう、タップは受け取らない。
final class CameraHintOverlayView: UIView {
    static let message = "数字と「最高・最低・脈拍」の文字を枠に収めてください。\n反射が入るときは、少し斜めから撮ると読み取りやすくなります。"

    /// 標準のカメラ画面で、上端のフラッシュなどのボタンが並ぶ列の高さ（この下からカメラの映像が始まる）。
    private static let topControlsHeight: CGFloat = 44
    /// 切り取られる正方形（映像の幅いっぱい）に対する、目安の枠の大きさ。
    private static let guideScale: CGFloat = 0.8

    private let guideShadow = CAShapeLayer()
    private let guideLine = CAShapeLayer()
    private let label = UILabel()
    private let background = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // 明るい背景でも暗い背景でも見えるよう、黒い縁取りの上に白い線を重ねる。
        for (shape, color, width) in [(guideShadow, UIColor.black.withAlphaComponent(0.35), CGFloat(5)),
                                      (guideLine, UIColor.white.withAlphaComponent(0.9), CGFloat(2))] {
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = color.cgColor
            shape.lineWidth = width
            layer.addSublayer(shape)
        }

        label.text = Self.message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white

        background.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        background.layer.cornerRadius = Theme.controlCornerRadius
        background.layer.cornerCurve = .continuous
        background.addSubview(label)
        addSubview(background)
        isAccessibilityElement = true
        accessibilityLabel = Self.message
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使わない")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let guide = Self.guideRect(in: bounds, safeAreaTop: safeAreaInsets.top)
        let path = UIBezierPath(roundedRect: guide, cornerRadius: Theme.cardCornerRadius).cgPath
        for shape in [guideShadow, guideLine] {
            shape.frame = bounds
            shape.path = path
        }

        // 一言は枠のすぐ下（カメラの映像の中）に置く。上端のボタンの列やシャッターと重ならないようにするため。
        let width = bounds.width - 32
        let fitting = label.sizeThatFits(CGSize(width: width - 24, height: .greatestFiniteMagnitude))
        background.frame = CGRect(x: 16, y: guide.maxY + 12, width: width, height: ceil(fitting.height) + 16)
        label.frame = background.bounds.insetBy(dx: 12, dy: 8)
    }

    /// 目安の枠の位置。カメラの映像（幅いっぱい・縦長 3:4）の中央に、幅の 8 割の正方形を置く。
    static func guideRect(in bounds: CGRect, safeAreaTop: CGFloat) -> CGRect {
        let previewWidth = bounds.width
        let previewHeight = previewWidth * 4 / 3
        let centerY = safeAreaTop + topControlsHeight + previewHeight / 2
        let side = previewWidth * guideScale
        return CGRect(x: (bounds.width - side) / 2, y: centerY - side / 2, width: side, height: side)
    }
}

/// 写真ライブラリから選ぶ。PHPicker なので写真へのフルアクセス許可は不要。
///
/// `UIImage` ではなく元データを読み込むのは、Exif の撮影日時を取り出すため
/// （`UIImage` にすると metadata が落ちてしまう）。
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    /// まとめて記録できるように複数選択に対応する。0 は無制限だが、
    /// 読み取りの待ち時間とメモリを考えて上限を設けている。
    var selectionLimit: Int = 20
    var onPick: ([PickedPhoto]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: ([PickedPhoto]) -> Void

        init(onPick: @escaping ([PickedPhoto]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onPick([])
                return
            }
            let providers = results.map(\.itemProvider)
            let handler = onPick

            Task {
                var photos: [PickedPhoto] = []
                for provider in providers {
                    if let photo = await Self.loadPhoto(from: provider) {
                        photos.append(photo)
                    }
                }
                await MainActor.run { handler(photos) }
            }
        }

        /// まず元データとして読み込み、撮影日時も取り出す。だめなら `UIImage` として読み込む。
        private static func loadPhoto(from provider: NSItemProvider) async -> PickedPhoto? {
            if let data = await loadData(from: provider), let image = UIImage(data: data) {
                return PickedPhoto(image: image, capturedAt: PhotoCaptureDate.extract(from: data))
            }
            if let image = await loadImage(from: provider) {
                return PickedPhoto(image: image, capturedAt: nil)
            }
            return nil
        }

        private static func loadData(from provider: NSItemProvider) async -> Data? {
            let identifier = UTType.image.identifier
            guard provider.hasItemConformingToTypeIdentifier(identifier) else { return nil }
            return await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }

        private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
            return await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}
