import UIKit
import UserNotifications

/// 通知の表示とタップの扱い（仕様書 2-18）。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 通知のタップでアプリが起動した場合も受け取れるよう、起動時に設定する。
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// アプリを開いているときも、測定の時刻を知らせる。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// リマインダーをタップしたら、記録ボタンのあるホームを開く。
    /// リマインダーは特定の記録を指さないので、記録が削除されていても安全に開ける。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        DispatchQueue.main.async {
            if ReminderStore.isReminderNotification(identifier: identifier) {
                AppNavigation.shared.showHome()
            }
            completionHandler()
        }
    }
}
