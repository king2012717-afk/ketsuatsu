import Foundation
import Observation

/// アプリ全体の設定。`UserDefaults` に即時保存する。
@Observable
final class AppSettings {
    private enum Key {
        static let standard = "settings.standard"
        static let targetSystolic = "settings.targetSystolic"
        static let targetDiastolic = "settings.targetDiastolic"
        static let healthKitSyncEnabled = "settings.healthKitSyncEnabled"
        static let savePhotoWithRecord = "settings.savePhotoWithRecord"
        static let defaultArm = "settings.defaultArm"
        static let hasCompletedFirstLaunch = "settings.hasCompletedFirstLaunch"
    }

    private let defaults: UserDefaults

    /// 判定に使う基準（家庭 / 診察室）。
    var standard: BPStandard {
        didSet { defaults.set(standard.rawValue, forKey: Key.standard) }
    }

    /// 目標とする収縮期血圧。これ以下なら「目標達成」として集計する。
    var targetSystolic: Int {
        didSet { defaults.set(targetSystolic, forKey: Key.targetSystolic) }
    }

    var targetDiastolic: Int {
        didSet { defaults.set(targetDiastolic, forKey: Key.targetDiastolic) }
    }

    /// 記録の保存時にヘルスケアへ自動で書き出すか。
    var healthKitSyncEnabled: Bool {
        didSet { defaults.set(healthKitSyncEnabled, forKey: Key.healthKitSyncEnabled) }
    }

    /// 写真から読み取ったとき、元の写真も一緒に保存するか。
    var savePhotoWithRecord: Bool {
        didSet { defaults.set(savePhotoWithRecord, forKey: Key.savePhotoWithRecord) }
    }

    /// 新規記録の初期値に使う腕。
    var defaultArm: MeasurementArm {
        didSet { defaults.set(defaultArm.rawValue, forKey: Key.defaultArm) }
    }

    var hasCompletedFirstLaunch: Bool {
        didSet { defaults.set(hasCompletedFirstLaunch, forKey: Key.hasCompletedFirstLaunch) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let standardValue = defaults.string(forKey: Key.standard).flatMap(BPStandard.init(rawValue:)) ?? .home
        self.standard = standardValue

        let defaultTarget = BPCategory.hypertensionThreshold(for: standardValue)
        let storedSystolic = defaults.integer(forKey: Key.targetSystolic)
        let storedDiastolic = defaults.integer(forKey: Key.targetDiastolic)
        self.targetSystolic = storedSystolic > 0 ? storedSystolic : defaultTarget.systolic - 1
        self.targetDiastolic = storedDiastolic > 0 ? storedDiastolic : defaultTarget.diastolic - 1

        self.healthKitSyncEnabled = defaults.bool(forKey: Key.healthKitSyncEnabled)
        self.savePhotoWithRecord = defaults.object(forKey: Key.savePhotoWithRecord) as? Bool ?? true
        self.defaultArm = defaults.string(forKey: Key.defaultArm)
            .flatMap(MeasurementArm.init(rawValue:)) ?? .unspecified
        self.hasCompletedFirstLaunch = defaults.bool(forKey: Key.hasCompletedFirstLaunch)
    }

    /// 基準を切り替えたときに、目標値を新しい基準の推奨値へ合わせる。
    func resetTargetsToRecommended() {
        let threshold = BPCategory.hypertensionThreshold(for: standard)
        targetSystolic = threshold.systolic - 1
        targetDiastolic = threshold.diastolic - 1
    }
}
