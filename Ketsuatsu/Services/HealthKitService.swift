import Foundation
import HealthKit

/// ヘルスケア（HealthKit）との読み書きをまとめる。
///
/// 書き出しは血圧の相関サンプル（収縮期 + 拡張期）と心拍数サンプル。
/// 取り込みでは自アプリが書いたサンプルを除外して、往復による重複を防ぐ。
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let bundleIdentifier = Bundle.main.bundleIdentifier

    private init() {}

    /// ヘルスケアから取り込んだ 1 件ぶんの測定値。
    struct ImportedReading: Identifiable, Hashable, Sendable {
        var id: UUID
        var date: Date
        var systolic: Int
        var diastolic: Int
        var pulse: Int?
    }

    enum HealthKitError: LocalizedError {
        case unavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "この端末ではヘルスケアを利用できません。"
            case .notAuthorized:
                return "ヘルスケアへのアクセスが許可されていません。設定 App のプライバシーから許可してください。"
            }
        }
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var systolicType: HKQuantityType { HKQuantityType(.bloodPressureSystolic) }
    private var diastolicType: HKQuantityType { HKQuantityType(.bloodPressureDiastolic) }
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private var correlationType: HKCorrelationType { HKCorrelationType(.bloodPressure) }

    private var pressureUnit: HKUnit { .millimeterOfMercury() }
    private var heartRateUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    /// 書き出しが許可されているか（読み取りの可否は仕様上わからない）。
    var canWrite: Bool {
        guard isAvailable else { return false }
        return store.authorizationStatus(for: systolicType) == .sharingAuthorized
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let types: Set<HKSampleType> = [systolicType, diastolicType, heartRateType]
        try await store.requestAuthorization(toShare: types, read: types)
    }

    // MARK: - 書き出し

    /// 記録をヘルスケアへ保存し、削除時に使う UUID を返す。
    @discardableResult
    func save(
        systolic: Int,
        diastolic: Int,
        pulse: Int?,
        date: Date
    ) async throws -> String {
        guard isAvailable else { throw HealthKitError.unavailable }
        guard store.authorizationStatus(for: systolicType) == .sharingAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let metadata: [String: Any] = [HKMetadataKeyWasUserEntered: true]
        let systolicSample = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: pressureUnit, doubleValue: Double(systolic)),
            start: date,
            end: date,
            metadata: metadata
        )
        let diastolicSample = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: pressureUnit, doubleValue: Double(diastolic)),
            start: date,
            end: date,
            metadata: metadata
        )
        let correlation = HKCorrelation(
            type: correlationType,
            start: date,
            end: date,
            objects: [systolicSample, diastolicSample],
            metadata: metadata
        )

        var objects: [HKObject] = [correlation]
        if let pulse, BPValueRange.pulse.contains(pulse) {
            objects.append(
                HKQuantitySample(
                    type: heartRateType,
                    quantity: HKQuantity(unit: heartRateUnit, doubleValue: Double(pulse)),
                    start: date,
                    end: date,
                    metadata: metadata
                )
            )
        }

        try await store.save(objects)
        return correlation.uuid.uuidString
    }

    /// 記録の削除に合わせてヘルスケア側のサンプルも消す。
    func delete(uuidString: String) async throws {
        guard isAvailable, let uuid = UUID(uuidString: uuidString) else { return }
        let predicate = HKQuery.predicateForObject(with: uuid)
        _ = try? await store.deleteObjects(of: correlationType, predicate: predicate)
    }

    // MARK: - 取り込み

    /// 指定日以降の血圧データを取り込む。自アプリが書いたサンプルは除外する。
    func importReadings(since startDate: Date) async throws -> [ImportedReading] {
        guard isAvailable else { throw HealthKitError.unavailable }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [.strictStartDate])
        let correlations = try await fetch(type: correlationType, predicate: predicate)
            .compactMap { $0 as? HKCorrelation }
            .filter { $0.sourceRevision.source.bundleIdentifier != bundleIdentifier }

        let heartRates = try await fetch(type: heartRateType, predicate: predicate)
            .compactMap { $0 as? HKQuantitySample }

        return correlations.compactMap { correlation in
            guard let systolic = correlation.objects(for: systolicType).first as? HKQuantitySample,
                  let diastolic = correlation.objects(for: diastolicType).first as? HKQuantitySample else {
                return nil
            }
            let date = correlation.startDate
            // 同じタイミング（前後 2 分以内）で記録された心拍数を脈拍として扱う。
            let pulse = heartRates
                .filter { abs($0.startDate.timeIntervalSince(date)) <= 120 }
                .min { abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date)) }
                .map { Int($0.quantity.doubleValue(for: heartRateUnit).rounded()) }

            return ImportedReading(
                id: correlation.uuid,
                date: date,
                systolic: Int(systolic.quantity.doubleValue(for: pressureUnit).rounded()),
                diastolic: Int(diastolic.quantity.doubleValue(for: pressureUnit).rounded()),
                pulse: pulse
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func fetch(type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}
