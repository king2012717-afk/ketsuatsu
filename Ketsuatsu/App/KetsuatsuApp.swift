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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(reminders)
                .tint(Theme.brand)
                .task {
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
