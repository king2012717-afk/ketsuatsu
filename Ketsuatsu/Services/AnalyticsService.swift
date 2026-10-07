import FirebaseAnalytics
import FirebaseCore
import Foundation

/// YutarouLabs 共通の Firebase Analytics 薄いラッパー。
/// イベント名と共通パラメータをここへ集約し、各アプリへ横展開しやすくする。
enum AnalyticsService {
    static let sourceApp = "ketsuatsu"

    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    static func log(_ name: String, parameters: [String: Any] = [:]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }

    /// blood_pressure_entry_started / _completed の entry_method に入れる値。
    enum EntryMethod {
        /// 手入力（RecordSource.manual と同じ値）
        static let manual = "manual"
        /// 写真 1 枚から読み取り（RecordSource.photo と同じ値）
        static let photo = "photo"
        /// 写真をまとめて読み取り
        static let photoBatch = "photo_batch"
    }

    // onboarding_complete は送らない。
    // このアプリにはオンボーディング画面がなく、完了に当たる操作が存在しないため、
    // 代わりの画面に結び付けると意味の違うデータになる。導入する場合はその完了時に
    // log("onboarding_complete") を追加する。

    /// アプリ横断で「主要な操作を終えた」ことを数える共通イベント。
    /// 個別イベント（blood_pressure_entry_completed など）と同じタイミングで送るため、
    /// 両者を足し合わせて集計しないこと（詳しくは FIREBASE_ANALYTICS.md）。
    static func mainActionCompleted(action: String) {
        log("main_action_complete", parameters: ["action": action])
    }

    static func recommendedAppImpression(destinationApp: String, placement: String, campaign: String) {
        log("recommended_app_impression", parameters: recommendationParameters(
            destinationApp: destinationApp,
            placement: placement,
            campaign: campaign
        ))
    }

    static func recommendedAppClick(destinationApp: String, placement: String, campaign: String) {
        log("recommended_app_click", parameters: recommendationParameters(
            destinationApp: destinationApp,
            placement: placement,
            campaign: campaign
        ))
    }

    private static func recommendationParameters(
        destinationApp: String,
        placement: String,
        campaign: String
    ) -> [String: Any] {
        [
            "source_app": sourceApp,
            "destination_app": destinationApp,
            "placement": placement,
            "campaign": campaign,
        ]
    }
}
