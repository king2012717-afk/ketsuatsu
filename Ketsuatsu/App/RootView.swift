import SwiftUI

/// タブ構成のルート画面。
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrivacyConsentManager.self) private var consent
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .home

    private enum Tab: Hashable {
        case home
        case history
        case charts
        case settings
    }

    var body: some View {
        VStack(spacing: 0) {
            // 広告は画面上部（各タブのナビゲーションバーの上）に固定する。
            AdBanner()
            tabs
        }
        // 広告の同意がまだなら、最初に同意画面を出す。選ぶまで広告 SDK は起動しない（仕様書 1-5）。
        .fullScreenCover(isPresented: Binding(get: { consent.needsConsent }, set: { _ in })) {
            AdConsentView()
        }
        // 同意済みなら、画面が前面に出てから ATT（未決定のときだけ）→ 広告 SDK の起動へ進む。
        // ATT はアプリが前面にいないと表示されないため、起動直後ではなくここで行う。
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await consent.resumeIfConsented() }
        }
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
