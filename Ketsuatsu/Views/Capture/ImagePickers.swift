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
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: ([PickedPhoto]) -> Void

        init(onCapture: @escaping ([PickedPhoto]) -> Void) {
            self.onCapture = onCapture
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
