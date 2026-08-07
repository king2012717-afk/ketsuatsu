import Foundation
import Observation
import SwiftData
import UIKit

/// 複数の写真をまとめて読み取り、確認してから一括保存するための状態。
///
/// 写真は 1 枚ずつ順番に解析する（Vision は重いので同時に走らせない）。
/// 解析が終わった写真から一覧に反映されるので、待っている間も内容を確認できる。
@MainActor
@Observable
final class BatchImportModel {

    struct Item: Identifiable {
        let id = UUID()
        /// 解析が終わるまで保持する元画像。終わったら解放する。
        var image: UIImage?
        var thumbnail: UIImage?
        var draft: BPDraft
        var result: BPParseResult?
        /// 一括保存の対象にするか。
        var isIncluded = false
        var isAnalyzed = false

        var capturedAt: Date? { draft.usesPhotoCaptureDate ? draft.measuredAt : nil }
        var canSave: Bool { draft.isValid }
    }

    private(set) var items: [Item]
    private(set) var analyzedCount = 0
    private(set) var isSaving = false

    private let defaultArm: MeasurementArm

    init(photos: [PickedPhoto], defaultArm: MeasurementArm) {
        self.defaultArm = defaultArm
        self.items = photos.map { photo in
            Item(
                image: photo.image,
                draft: BPDraft(measuredAt: photo.capturedAt ?? Date(), arm: defaultArm)
            )
        }
        // 撮影日時が取れた写真は、その日時を測定日時として使う。
        for index in items.indices {
            items[index].draft.source = .photo
            items[index].draft.usesPhotoCaptureDate = photos[index].capturedAt != nil
        }
    }

    var totalCount: Int { items.count }
    var isAnalyzing: Bool { analyzedCount < items.count }
    var progress: Double { totalCount == 0 ? 1 : Double(analyzedCount) / Double(totalCount) }

    var selectedCount: Int { items.filter { $0.isIncluded && $0.canSave }.count }
    var failedCount: Int { items.filter { $0.isAnalyzed && !$0.canSave }.count }

    // MARK: - 解析

    func analyze() async {
        for index in items.indices where !items[index].isAnalyzed {
            guard let image = items[index].image else { continue }

            let thumbnail = ImageProcessing.thumbnail(from: image)
            let photoData = ImageProcessing.jpegData(from: image)
            let output = try? await BPImageRecognizer.recognize(image: image)

            guard index < items.count else { return }
            var draft = items[index].draft
            if let result = output?.result {
                draft.systolic = result.systolic
                draft.diastolic = result.diastolic
                draft.pulse = result.pulse
            }
            draft.photoData = photoData

            items[index].draft = draft
            items[index].result = output?.result
            items[index].thumbnail = thumbnail
            items[index].isAnalyzed = true
            items[index].isIncluded = draft.isValid
            // 大きな画像はここで手放してメモリを抑える。
            items[index].image = nil
            analyzedCount += 1
        }
    }

    // MARK: - 編集

    func update(_ draft: BPDraft, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].draft = draft
        if draft.isValid {
            items[index].isIncluded = true
        }
    }

    func setIncluded(_ isIncluded: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !isIncluded || items[index].canSave else { return }
        items[index].isIncluded = isIncluded
    }

    func toggleIncluded(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        setIncluded(!items[index].isIncluded, for: id)
    }

    func selectAll() {
        for index in items.indices where items[index].canSave {
            items[index].isIncluded = true
        }
    }

    func deselectAll() {
        for index in items.indices {
            items[index].isIncluded = false
        }
    }

    // MARK: - 保存

    /// 選ばれている記録をまとめて保存し、保存できた件数を返す。
    @discardableResult
    func save(context: ModelContext, settings: AppSettings) async -> Int {
        guard !isSaving else { return 0 }
        isSaving = true
        defer { isSaving = false }

        var saved = 0
        for item in items where item.isIncluded && item.canSave {
            if await RecordService.create(from: item.draft, context: context, settings: settings) != nil {
                saved += 1
            }
        }
        return saved
    }
}
