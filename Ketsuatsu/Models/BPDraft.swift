import Foundation

/// 入力途中の測定値。新規作成・編集・写真からの読み取りで共通して使う。
struct BPDraft: Equatable {
    var measuredAt: Date = Date()
    var systolic: Int?
    var diastolic: Int?
    var pulse: Int?
    var slot: MeasurementSlot = MeasurementSlot.inferred(from: Date())
    var arm: MeasurementArm = .unspecified
    var note: String = ""
    var tookMedication: Bool = false
    var source: RecordSource = .manual
    var photoData: Data?

    /// 保存できる状態かどうか。
    var isValid: Bool {
        guard let systolic, let diastolic else { return false }
        return BPValueRange.isPlausible(systolic: systolic, diastolic: diastolic)
    }

    var validationMessage: String? {
        guard let systolic else { return "収縮期（上）を入力してください。" }
        guard let diastolic else { return "拡張期（下）を入力してください。" }
        guard BPValueRange.systolic.contains(systolic) else { return "収縮期の値を確認してください。" }
        guard BPValueRange.diastolic.contains(diastolic) else { return "拡張期の値を確認してください。" }
        guard systolic > diastolic else { return "収縮期は拡張期より大きい値を入力してください。" }
        return nil
    }

    init(measuredAt: Date = Date(), arm: MeasurementArm = .unspecified) {
        self.measuredAt = measuredAt
        self.slot = MeasurementSlot.inferred(from: measuredAt)
        self.arm = arm
    }

    /// 既存の記録を編集するための下書きを作る。
    init(record: BPRecord) {
        measuredAt = record.measuredAt
        systolic = record.systolic
        diastolic = record.diastolic
        pulse = record.pulse
        slot = record.slot
        arm = record.arm
        note = record.note
        tookMedication = record.tookMedication
        source = record.source
        photoData = record.photoData
    }

    /// 写真の読み取り結果から下書きを作る。
    init(parseResult: BPParseResult, photoData: Data?, measuredAt: Date = Date(), arm: MeasurementArm = .unspecified) {
        self.measuredAt = measuredAt
        self.slot = MeasurementSlot.inferred(from: measuredAt)
        self.arm = arm
        self.systolic = parseResult.systolic
        self.diastolic = parseResult.diastolic
        self.pulse = parseResult.pulse
        self.source = .photo
        self.photoData = photoData
    }
}
