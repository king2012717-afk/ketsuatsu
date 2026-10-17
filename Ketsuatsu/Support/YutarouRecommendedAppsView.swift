import SwiftUI

@MainActor
private final class YutarouRecommendedAppsViewModel: ObservableObject {
    @Published private(set) var apps: [YutarouApp] = []
    @Published private(set) var isLoading = true
    private let currentAppID: String
    private let currentCategory: String
    private var hasLoaded = false
    /// recommended_app_impression をいつ送るかの記録（半分以上見えたか・前面の間に送ったか）。
    private var impressions = ImpressionTracker()

    init(currentAppID: String, currentCategory: String) {
        self.currentAppID = currentAppID
        self.currentCategory = currentCategory
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        defer { isLoading = false }
        apps = await YutarouAppsService.loadRecommendations(
            currentAppID: currentAppID,
            currentCategory: currentCategory
        )
    }

    /// 行の見えている割合が変わったときに呼ぶ。今回送るべきなら true を返す。
    func shouldLogImpression(for app: YutarouApp, visibleFraction: Double) -> Bool {
        impressions.update(id: app.id, visibleFraction: visibleFraction)
    }

    /// アプリが背面に回ったら、表示の回数を数え直す。
    func didEnterBackground() {
        impressions.didEnterBackground()
    }

    /// アプリが前面に戻ったとき、見えている行のうちまだ送っていないアプリを返す。
    func appsToLogOnBecomingActive() -> [YutarouApp] {
        let ids = Set(impressions.didBecomeActive())
        return apps.filter { ids.contains($0.id) }
    }
}

/// 設定画面などに埋め込める、YutarouLabs共通のおすすめアプリ一覧。
struct YutarouLabsRecommendedApps: View {
    @StateObject private var viewModel: YutarouRecommendedAppsViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(currentAppID: String, currentCategory: String) {
        _viewModel = StateObject(
            wrappedValue: YutarouRecommendedAppsViewModel(
                currentAppID: currentAppID,
                currentCategory: currentCategory
            )
        )
    }

    var body: some View {
        Section {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.apps) { app in
                    Button {
                        if let url = app.iosURL {
                            AnalyticsService.recommendedAppClick(
                                destinationApp: app.id,
                                placement: "settings_recommendations",
                                campaign: "yutaroulabs_cross_promo"
                            )
                            openURL(url)
                        }
                    } label: {
                        recommendationRow(for: app)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("App Storeで開きます")
                    .onVisibleFractionChange { fraction in
                        // 行の半分以上が画面に入ったときだけ、前面にいる間アプリごとに 1 回送る（仕様書 4-8）。
                        guard viewModel.shouldLogImpression(for: app, visibleFraction: fraction) else { return }
                        logImpression(of: app)
                    }
                }
            }
        } header: {
            if viewModel.isLoading || !viewModel.apps.isEmpty {
                Text("YutarouLabsのおすすめ")
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                viewModel.didEnterBackground()
            case .active:
                viewModel.appsToLogOnBecomingActive().forEach(logImpression)
            default:
                break
            }
        }
    }

    private func logImpression(of app: YutarouApp) {
        AnalyticsService.recommendedAppImpression(
            destinationApp: app.id,
            placement: "settings_recommendations",
            campaign: "yutaroulabs_cross_promo"
        )
    }

    private func recommendationRow(for app: YutarouApp) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    iconPlaceholder
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(app.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.secondary.opacity(0.15))
            Image(systemName: "square.grid.2x2.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
