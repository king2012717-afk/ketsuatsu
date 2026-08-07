import SwiftUI

/// タブ構成のルート画面。
struct RootView: View {
    @Environment(AppSettings.self) private var settings

    @State private var selection: Tab = .home

    private enum Tab: Hashable {
        case home
        case history
        case charts
        case settings
    }

    var body: some View {
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
