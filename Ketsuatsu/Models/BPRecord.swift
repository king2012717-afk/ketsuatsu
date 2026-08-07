import Foundation
import SwiftData

/// 血圧の 1 回分の測定記録。
///
/// enum はそのまま永続化せず raw value で保持している。SwiftData の `#Predicate` は
/// String 比較のほうが素直に書けるため、外向きには計算プロパティで enum を公開する。
@Model
final class BPRecord {
    var measuredAt: Date = Date()
    var systolic: Int = 0
    var diastolic: Int = 0
    var pulse: Int?
    var slotRaw: String = MeasurementSlot.other.rawValue
    var armRaw: String = MeasurementArm.unspecified.rawValue
    var sourceRaw: String = RecordSource.manual.rawValue
    var note: String = ""
    var tookMedication: Bool = false
    /// ヘルスケアへ書き出したサンプルの UUID。削除の同期と重複取り込みの防止に使う。
    var healthKitUUID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// 読み取り元の写真（JPEG）。本体 DB を膨らませないよう外部ファイルに保存する。
    @Attribute(.externalStorage) var photoData: Data?

    init(
        measuredAt: Date = Date(),
        systolic: Int,
        diastolic: Int,
        pulse: Int? = nil,
        slot: MeasurementSlot? = nil,
        arm: MeasurementArm = .unspecified,
        source: RecordSource = .manual,
        note: String = "",
        tookMedication: Bool = false,
        photoData: Data? = nil,
        healthKitUUID: String? = nil
    ) {
        self.measuredAt = measuredAt
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.slotRaw = (slot ?? MeasurementSlot.inferred(from: measuredAt)).rawValue
        self.armRaw = arm.rawValue
        self.sourceRaw = source.rawValue
        self.note = note
        self.tookMedication = tookMedication
        self.photoData = photoData
        self.healthKitUUID = healthKitUUID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var slot: MeasurementSlot {
        get { MeasurementSlot(rawValue: slotRaw) ?? .other }
        set { slotRaw = newValue.rawValue }
    }

    var arm: MeasurementArm {
        get { MeasurementArm(rawValue: armRaw) ?? .unspecified }
        set { armRaw = newValue.rawValue }
    }

    var source: RecordSource {
        get { RecordSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var sample: BPSample {
        BPSample(
            measuredAt: measuredAt,
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            slot: slot
        )
    }

    func touch() { updatedAt = Date() }
}

extension BPRecord: BPMeasurement {}
