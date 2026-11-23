import SwiftData
import SwiftUI
import UserNotifications

@main
struct KetsuatsuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    @State private var reminders = ReminderStore()

    /// 記録の保存先。開けなかったときは、通常の画面の代わりに「記録を開けない」画面を出す。
    @State private var store = DataStore()

    @State private var consent = PrivacyConsentManager.shared

    init() {
        AnalyticsService.configure()
        // 広告 SDK はここでは起動しない。同意と ATT が終わってから PrivacyConsentManager が起動する（仕様書 1-5）。
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isPersistent {
                    RootView()
                        .task {
                            // 計測開始時点の基準値を、データを開いた直後に記録する（仕様書 4-7）。
                            // ストアを開けなかったときは記録しない（既存の記録が 0 件に見えて、誤った値になるため）。
                            RecordService.establishAnalyticsBaseline(context: store.container.mainContext)
                            await reminders.installDefaultsIfNeeded()
                            // 通知の登録し直しは、前面に出るたびに RootView が行う（起動時を含む。仕様書 2-18）。
                        }
                } else {
                    // 記録の入力・広告・計測の完了イベントは、ここでは一切動かさない。
                    StoreUnavailableView(detail: store.failureDescription) { store.retry() }
                }
            }
            .environment(settings)
            .environment(reminders)
            .environment(consent)
            .tint(Theme.brand)
            .modelContainer(store.container)
        }
    }
}
