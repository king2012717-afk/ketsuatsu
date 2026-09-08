import SwiftUI

@MainActor
private final class YutarouRecommendedAppsViewModel: ObservableObject {
    @Published private(set) var apps: [YutarouApp] = []
    @Published private(set) var isLoading = true
    private let currentAppID: String
    private let currentCategory: String
    private var hasLoaded = false

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
}

/// 設定画面などに埋め込める、YutarouLabs共通のおすすめアプリ一覧。
struct YutarouLabsRecommendedApps: View {
    @StateObject private var viewModel: YutarouRecommendedAppsViewModel
    @Environment(\.openURL) private var openURL

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
                            openURL(url)
                        }
                    } label: {
                        recommendationRow(for: app)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("App Storeで開きます")
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
