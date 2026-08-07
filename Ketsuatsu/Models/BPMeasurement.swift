import Foundation

/// 集計・グラフ描画が SwiftData のモデルに依存しないようにするための抽象。
/// テストではプレーンな `BPSample` を使って同じロジックを検証できる。
protocol BPMeasurement {
    var measuredAt: Date { get }
    var systolic: Int { get }
    var diastolic: Int { get }
    var pulse: Int? { get }
    var slot: MeasurementSlot { get }
}

extension BPMeasurement {
    /// 脈圧（収縮期 − 拡張期）。動脈の硬さの目安として使われる。
    var pulsePressure: Int { systolic - diastolic }

    /// 平均血圧（拡張期 + 脈圧 / 3）。
    var meanArterialPressure: Double { Double(diastolic) + Double(pulsePressure) / 3.0 }

    func category(standard: BPStandard) -> BPCategory {
        BPCategory.classify(systolic: systolic, diastolic: diastolic, standard: standard)
    }
}

/// 値だけを保持する軽量な測定値。グラフ描画とテストで使う。
struct BPSample: BPMeasurement, Identifiable, Hashable, Sendable {
    var id: UUID
    var measuredAt: Date
    var systolic: Int
    var diastolic: Int
    var pulse: Int?
    var slot: MeasurementSlot

    init(
        id: UUID = UUID(),
        measuredAt: Date,
        systolic: Int,
        diastolic: Int,
        pulse: Int? = nil,
        slot: MeasurementSlot? = nil
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.slot = slot ?? MeasurementSlot.inferred(from: measuredAt)
    }
}

/// 血圧値の妥当な入力範囲。OCR の候補選別と手入力バリデーションで共有する。
enum BPValueRange {
    static let systolic = 50...300
    static let diastolic = 20...200
    static let pulse = 20...250

    /// 生理的にあり得る組み合わせかどうか。
    static func isPlausible(systolic: Int, diastolic: Int) -> Bool {
        guard self.systolic.contains(systolic), self.diastolic.contains(diastolic) else { return false }
        return systolic > diastolic
    }
}
