import Foundation
import SwiftData

/// 記録の保存・削除と、それに伴うヘルスケア連携をまとめる。
/// 画面側から永続化とヘルスケアの手順が見えないようにするのが目的。
@MainActor
enum RecordService {

    struct ImportSummary: Equatable {
        var imported: Int
        var skipped: Int
    }

    // MARK: - 作成・更新・削除

    /// 1 件を記録する（手入力・写真 1 枚）。
    /// 分析イベントは、永続保存（`context.save()`）に成功した場合だけ送る。
    @discardableResult
    static func create(from draft: BPDraft, context: ModelContext, settings: AppSettings) async -> BPRecord? {
        guard let result = await insert(draft, context: context, settings: settings) else { return nil }
        if result.persisted {
            logEntryCompleted(method: draft.source.rawValue, persistedCount: 1)
        }
        return result.record
    }

    /// 写真のまとめて記録で、選ばれた記録を順に保存し、永続保存できた件数を返す。
    /// 分析イベントは 1 回のまとめて記録につき 1 回だけ送る（件数は record_count）。
    @discardableResult
    static func createBatch(from drafts: [BPDraft], context: ModelContext, settings: AppSettings) async -> Int {
        var persistedCount = 0
        for draft in drafts {
            if let result = await insert(draft, context: context, settings: settings), result.persisted {
                persistedCount += 1
            }
        }
        if persistedCount > 0 {
            logEntryCompleted(method: AnalyticsService.EntryMethod.photoBatch, persistedCount: persistedCount)
        }
        return persistedCount
    }

    /// 記録を追加して保存する。`persisted` は `context.save()` が成功したかどうか。
    /// 失敗してもコンテキストには残る（従来どおり画面には表示され、自動保存の対象になる）。
    private static func insert(
        _ draft: BPDraft,
        context: ModelContext,
        settings: AppSettings
    ) async -> (record: BPRecord, persisted: Bool)? {
        guard let systolic = draft.systolic, let diastolic = draft.diastolic else { return nil }

        // 3 件目の判定に使う件数を、この記録を加える前の状態から引き継ぐ（初回のみ）。
        EntryMilestoneTracker().migrateIfNeeded {
            existingEntryCount(context: context)
        }

        let record = BPRecord(
            measuredAt: draft.measuredAt,
            systolic: systolic,
            diastolic: diastolic,
            pulse: draft.pulse,
            slot: draft.slot,
            arm: draft.arm,
            source: draft.source,
            note: draft.note,
            tookMedication: draft.tookMedication,
            photoData: settings.savePhotoWithRecord ? draft.photoData : nil
        )
        context.insert(record)

        let persisted: Bool
        do {
            try context.save()
            persisted = true
        } catch {
            persisted = false
            #if DEBUG
            print("RecordService: 記録の保存に失敗しました: \(error)")
            #endif
        }

        await syncToHealthKitIfNeeded(record, settings: settings)
        return (record, persisted)
    }

    /// ヘルスケアから取り込んだものを除いた、保存済みの記録件数。
    private static func existingEntryCount(context: ModelContext) -> Int {
        let healthKitRaw = RecordSource.healthKit.rawValue
        let descriptor = FetchDescriptor<BPRecord>(
            predicate: #Predicate<BPRecord> { $0.sourceRaw != healthKitRaw }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 保存に成功した記録について、完了イベントと 3 件目の到達イベントを送る。
    /// 送るのは記録方法と件数だけで、血圧値・脈拍・メモなどの内容は含めない。
    private static func logEntryCompleted(method: String, persistedCount: Int) {
        var parameters: [String: Any] = ["entry_method": method]
        if method == AnalyticsService.EntryMethod.photoBatch {
            parameters["record_count"] = persistedCount
        }
        AnalyticsService.log("blood_pressure_entry_completed", parameters: parameters)
        AnalyticsService.mainActionCompleted(action: "blood_pressure_entry")

        if EntryMilestoneTracker().addCompletedEntries(persistedCount) {
            AnalyticsService.log("third_entry_completed")
        }
    }

    static func update(_ record: BPRecord, with draft: BPDraft, context: ModelContext, settings: AppSettings) async {
        guard let systolic = draft.systolic, let diastolic = draft.diastolic else { return }

        record.measuredAt = draft.measuredAt
        record.systolic = systolic
        record.diastolic = diastolic
        record.pulse = draft.pulse
        record.slot = draft.slot
        record.arm = draft.arm
        record.note = draft.note
        record.tookMedication = draft.tookMedication
        record.photoData = settings.savePhotoWithRecord ? draft.photoData : nil
        record.touch()
        try? context.save()

        // ヘルスケア側は更新できないので、書き出し済みなら消して書き直す。
        if let uuid = record.healthKitUUID {
            try? await HealthKitService.shared.delete(uuidString: uuid)
            record.healthKitUUID = nil
        }
        await syncToHealthKitIfNeeded(record, settings: settings)
        try? context.save()
    }

    static func delete(_ record: BPRecord, context: ModelContext) async {
        if let uuid = record.healthKitUUID {
            try? await HealthKitService.shared.delete(uuidString: uuid)
        }
        context.delete(record)
        try? context.save()
    }

    static func deleteAll(context: ModelContext) async {
        let descriptor = FetchDescriptor<BPRecord>()
        guard let records = try? context.fetch(descriptor) else { return }
        for record in records {
            if let uuid = record.healthKitUUID {
                try? await HealthKitService.shared.delete(uuidString: uuid)
            }
            context.delete(record)
        }
        try? context.save()
    }

    // MARK: - ヘルスケア

    private static func syncToHealthKitIfNeeded(_ record: BPRecord, settings: AppSettings) async {
        guard settings.healthKitSyncEnabled, HealthKitService.shared.canWrite else { return }
        let uuid = try? await HealthKitService.shared.save(
            systolic: record.systolic,
            diastolic: record.diastolic,
            pulse: record.pulse,
            date: record.measuredAt
        )
        record.healthKitUUID = uuid
    }

    /// 書き出しが済んでいない記録をまとめてヘルスケアへ送る。
    @discardableResult
    static func exportPendingToHealthKit(context: ModelContext, settings: AppSettings) async -> Int {
        guard HealthKitService.shared.canWrite else { return 0 }
        let descriptor = FetchDescriptor<BPRecord>(
            predicate: #Predicate<BPRecord> { $0.healthKitUUID == nil },
            sortBy: [SortDescriptor(\.measuredAt)]
        )
        guard let records = try? context.fetch(descriptor) else { return 0 }

        var exported = 0
        for record in records where record.source != .healthKit {
            if let uuid = try? await HealthKitService.shared.save(
                systolic: record.systolic,
                diastolic: record.diastolic,
                pulse: record.pulse,
                date: record.measuredAt
            ) {
                record.healthKitUUID = uuid
                exported += 1
            }
        }
        try? context.save()
        return exported
    }

    /// ヘルスケアの血圧データを取り込む。すでに同じ内容がある場合は飛ばす。
    static func importFromHealthKit(
        context: ModelContext,
        since startDate: Date,
        settings: AppSettings
    ) async throws -> ImportSummary {
        let readings = try await HealthKitService.shared.importReadings(since: startDate)
        guard !readings.isEmpty else { return ImportSummary(imported: 0, skipped: 0) }

        let existing = (try? context.fetch(FetchDescriptor<BPRecord>())) ?? []
        let existingUUIDs = Set(existing.compactMap(\.healthKitUUID))

        var imported = 0
        var skipped = 0

        for reading in readings {
            let identifier = reading.id.uuidString
            if existingUUIDs.contains(identifier) {
                skipped += 1
                continue
            }
            // UUID が違っても、ほぼ同時刻で同じ値なら重複とみなす。
            let isDuplicate = existing.contains { record in
                abs(record.measuredAt.timeIntervalSince(reading.date)) < 60
                    && record.systolic == reading.systolic
                    && record.diastolic == reading.diastolic
            }
            if isDuplicate {
                skipped += 1
                continue
            }

            let record = BPRecord(
                measuredAt: reading.date,
                systolic: reading.systolic,
                diastolic: reading.diastolic,
                pulse: reading.pulse,
                arm: settings.defaultArm,
                source: .healthKit,
                healthKitUUID: identifier
            )
            context.insert(record)
            imported += 1
        }

        try? context.save()
        return ImportSummary(imported: imported, skipped: skipped)
    }
}
