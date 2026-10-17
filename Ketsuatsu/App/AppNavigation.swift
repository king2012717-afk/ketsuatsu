import Observation

/// 画面の外（通知のタップなど）から、表示するタブを切り替えるための窓口。
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    /// ホームを開く要求の回数。値が変わったら `RootView` がホームへ切り替える。
    private(set) var homeRequest = 0

    func showHome() {
        homeRequest += 1
    }
}
