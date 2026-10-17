import Foundation

/// うちの血圧記録に固有の分析イベント（仕様書 4-7 の `AppAnalytics`）。
/// 送るのは操作の種類と件数だけで、血圧値・脈拍・服薬・メモ・写真・ヘルスケアのデータは含めない。
/// 発火条件と重複の防ぎ方は `FIREBASE_ANALYTICS.md` を参照。
enum AppAnalytics {

    /// blood_pressure_entry_started / _completed の entry_method に入れる値。
    enum EntryMethod: String {
        /// 手入力
        case manual
        /// 写真 1 枚から読み取り
        case photo
        /// 写真をまとめて読み取り
        case photoBatch = "photo_batch"
    }

    /// 記録を始める操作をしたとき（手入力を選んだ／写真を選び終えた）。ユーザー操作のハンドラから呼ぶ。
    static func entryStarted(_ method: EntryMethod) {
        AnalyticsService.log("blood_pressure_entry_started", parameters: [
            "entry_method": method.rawValue,
        ])
    }

    /// 永続保存に成功した記録について送る。まとめて記録は 1 回の操作で 1 回だけ、件数を `record_count` に入れる。
    static func entryCompleted(_ method: EntryMethod, recordCount: Int) {
        var parameters: [String: Any] = ["entry_method": method.rawValue]
        if method == .photoBatch {
            parameters["record_count"] = recordCount
        }
        AnalyticsService.log("blood_pressure_entry_completed", parameters: parameters)
        AnalyticsService.mainActionCompleted(action: "blood_pressure_entry")
    }

    static func thirdEntryCompleted() {
        AnalyticsService.log("third_entry_completed")
    }

    /// グラフで「1週間」を選んだとき。
    static func weeklySummaryViewed() {
        AnalyticsService.log("weekly_summary_viewed")
    }

    /// 計測を始めた時点で記録があったか（既存ユーザーを分析から分けるため。仕様書 4-7）。
    static func setHadDataAtStart(_ hadData: Bool) {
        AnalyticsService.setUserProperty(hadData ? "true" : "false", forName: "had_data_at_start")
    }
}
