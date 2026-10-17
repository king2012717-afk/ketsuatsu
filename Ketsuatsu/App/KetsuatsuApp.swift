import SwiftData
import SwiftUI
import UserNotifications

@main
struct KetsuatsuApp: App {
    @State private var settings = AppSettings()
    @State private var reminders = ReminderStore()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: BPRecord.self)
        } catch {
            // 起動時にストアを開けない場合はメモリ上で動かし、記録の入力自体は行えるようにする。
            do {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: BPRecord.self, configurations: configuration)
            } catch {
                fatalError("データベースを初期化できませんでした: \(error)")
            }
        }
    }()

    @State private var consent = PrivacyConsentManager.shared

    init() {
        AnalyticsService.configure()
        // 広告 SDK はここでは起動しない。同意と ATT が終わってから PrivacyConsentManager が起動する（仕様書 1-5）。
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(reminders)
                .environment(consent)
                .tint(Theme.brand)
                .task {
                    // 計測開始時点の基準値を、データを開いた直後に記録する（仕様書 4-7）。
                    RecordService.establishAnalyticsBaseline(context: container.mainContext)
                    await reminders.installDefaultsIfNeeded()
                    await reminders.refreshAuthorizationStatus()
                    // 通知が許可済みなら、端末の再起動やアプリ更新に備えて登録し直す。
                    if reminders.authorizationStatus == .authorized {
                        await reminders.synchronize()
                    }
                }
        }
        .modelContainer(container)
    }
}
