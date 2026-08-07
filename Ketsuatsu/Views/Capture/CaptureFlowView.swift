import SwiftUI
import UIKit

/// 写真から記録するまでの流れをひとつのシートで完結させる。
///
/// 撮影（または選択）→ 読み取り中 → 確認・保存、と 1 枚のシート内で表示を切り替える。
/// シートを重ねて出すと iOS 側の表示競合が起きやすいため、あえて画面を差し替える方式にしている。
/// 写真を複数選んだ場合は、まとめて記録する画面へ進む。
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
        case analyzing(PickedPhoto)
        case review(BPDraft, BPParseResult, [String])
        case batch([PickedPhoto])
        case failed(String)
    }

    var body: some View {
        switch phase {
        case .picking:
            picker
                .ignoresSafeArea()

        case .analyzing(let photo):
            AnalyzingView(image: photo.image) { dismiss() }
                .task { await analyze(photo) }

        case .review(let draft, let result, let lines):
            RecordEditView(
                mode: .create(draft),
                ocrResult: result,
                recognizedLines: lines
            )

        case .batch(let photos):
            BatchImportView(photos: photos, defaultArm: settings.defaultArm)

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
            CameraPicker { photos in
                handle(photos)
            }
        case .photoLibrary:
            PhotoLibraryPicker { photos in
                handle(photos)
            }
        }
    }

    private func handle(_ photos: [PickedPhoto]) {
        switch photos.count {
        case 0:
            dismiss()
        case 1:
            phase = .analyzing(photos[0])
        default:
            phase = .batch(photos)
        }
    }

    private func analyze(_ photo: PickedPhoto) async {
        do {
            let output = try await BPImageRecognizer.recognize(image: photo.image)
            let draft = BPDraft(
                parseResult: output.result,
                photoData: ImageProcessing.jpegData(from: photo.image),
                capturedAt: photo.capturedAt,
                arm: settings.defaultArm
            )
            phase = .review(draft, output.result, output.recognizedLines)
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
