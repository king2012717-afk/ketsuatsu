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

    @discardableResult
    static func create(from draft: BPDraft, context: ModelContext, settings: AppSettings) async -> BPRecord? {
        guard let systolic = draft.systolic, let diastolic = draft.diastolic else { return nil }

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
        try? context.save()

        await syncToHealthKitIfNeeded(record, settings: settings)
        return record
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
