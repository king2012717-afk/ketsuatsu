import SwiftUI
import UIKit

/// 写真から記録するまでの流れをひとつのシートで完結させる。
///
/// 撮影（または選択）→ 読み取り中 → 確認・保存、と 1 枚のシート内で表示を切り替える。
/// シートを重ねて出すと iOS 側の表示競合が起きやすいため、あえて画面を差し替える方式にしている。
struct CaptureFlowView: View {
    enum Source: Identifiable {
        case camera
        case photoLibrary

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let source: Source

    @State private var phase: Phase = .picking

    private enum Phase {
        case picking
        case analyzing(UIImage)
        case review(UIImage, BPParseResult, [String])
        case failed(String)
    }

    var body: some View {
        switch phase {
        case .picking:
            picker
                .ignoresSafeArea()

        case .analyzing(let image):
            AnalyzingView(image: image) { dismiss() }
                .task { await analyze(image) }

        case .review(let image, let result, let lines):
            RecordEditView(
                mode: .create(
                    BPDraft(
                        parseResult: result,
                        photoData: Self.jpegData(from: image),
                        arm: settings.defaultArm
                    )
                ),
                ocrResult: result,
                recognizedLines: lines
            )

        case .failed(let message):
            FailureView(message: message) {
                dismiss()
            } retry: {
                phase = .picking
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        switch source {
        case .camera:
            CameraPicker { image in
                handle(image)
            }
        case .photoLibrary:
            PhotoLibraryPicker { image in
                handle(image)
            }
        }
    }

    private func handle(_ image: UIImage?) {
        guard let image else {
            dismiss()
            return
        }
        phase = .analyzing(image)
    }

    private func analyze(_ image: UIImage) async {
        do {
            let output = try await BPImageRecognizer.recognize(image: image)
            phase = .review(image, output.result, output.recognizedLines)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 保存用に長辺 1600px 程度へ縮小した JPEG を作る。
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) }

        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// 読み取り中の表示。
private struct AnalyzingView: View {
    let image: UIImage
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .strokeBorder(Theme.brand.opacity(0.4), lineWidth: 2)
                    )

                ProgressView()
                    .controlSize(.large)
                Text("血圧計の表示を読み取っています…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("読み取り中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }
            }
        }
    }
}

/// 読み取りに失敗したときの表示。
private struct FailureView: View {
    let message: String
    var onClose: () -> Void
    var retry: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("読み取れませんでした", systemImage: "camera.metering.unknown")
            } description: {
                Text(message)
            } actions: {
                Button("もう一度撮影する", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onClose)
                }
            }
        }
    }
}
