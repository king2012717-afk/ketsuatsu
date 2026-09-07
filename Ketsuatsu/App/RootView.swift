import SwiftUI

/// タブ構成のルート画面。
struct RootView: View {
    @StateObject private var consent = ConsentManager.shared

    @State private var selection: Tab = .home

    private enum Tab: Hashable {
        case home
        case history
        case charts
        case settings
    }

    /// App Store 用のスクリーンショットを撮るときは広告を写り込ませない。
    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 広告は画面上部（各タブのナビゲーションバーの上）に固定する。
            // 同意が取れるまで View 自体を作らない＝広告リクエストも発生しない。
            if consent.canRequestAds && !isScreenshotMode {
                AdBanner()
            }
            tabs
        }
        .task { ConsentManager.shared.startOnce() }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(Tab.home)

            HistoryView()
                .tabItem { Label("履歴", systemImage: "list.bullet") }
                .tag(Tab.history)

            ChartsView()
                .tabItem { Label("グラフ", systemImage: "chart.xyaxis.line") }
                .tag(Tab.charts)

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }
}
