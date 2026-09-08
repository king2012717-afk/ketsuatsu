import Foundation

/// 1件の不正データで一覧全体の読み込みが失敗しないようにするラッパー。
private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct YutarouAppsEnvelope: Decodable {
    let apps: [LossyDecodable<YutarouApp>]
}

/// 公開JSONの取得、24時間キャッシュ、おすすめ抽選を担当する。
enum YutarouAppsService {
    private static let cachedJSONKey = "yutarouLabs.appsJSON.v1"
    private static let lastFetchedAtKey = "yutarouLabs.appsLastFetchedAt.v1"

    static func loadRecommendations(
        currentAppID: String,
        currentCategory: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async -> [YutarouApp] {
        let allApps = await loadApps(now: now, defaults: defaults)
        return selectRecommendations(
            from: allApps,
            currentAppID: currentAppID,
            currentCategory: currentCategory
        )
    }

    /// 同カテゴリから最大2件を選び、残りを全候補から補う。
    static func selectRecommendations(
        from apps: [YutarouApp],
        currentAppID: String,
        currentCategory: String
    ) -> [YutarouApp] {
        var seenIDs = Set<String>()
        let candidates = apps.filter {
            $0.published
                && $0.id != currentAppID
                && $0.iosURL != nil
                && seenIDs.insert($0.id).inserted
        }

        var selected = Array(
            candidates
                .filter { $0.category == currentCategory }
                .shuffled()
                .prefix(YutarouAppsConfig.sameCategoryCount)
        )
        let selectedIDs = Set(selected.map(\.id))
        let remaining = candidates
            .filter { !selectedIDs.contains($0.id) }
            .shuffled()

        selected.append(
            contentsOf: remaining.prefix(
                max(0, YutarouAppsConfig.recommendationCount - selected.count)
            )
        )
        return selected
    }

    private static func loadApps(now: Date, defaults: UserDefaults) async -> [YutarouApp] {
        let cachedData = defaults.data(forKey: cachedJSONKey)
        let lastFetchedAt = defaults.object(forKey: lastFetchedAtKey) as? Date

        let cacheAge = lastFetchedAt.map { now.timeIntervalSince($0) }
        if let cachedData,
           let cacheAge,
           cacheAge >= 0,
           cacheAge < YutarouAppsConfig.cacheLifetime,
           let cachedApps = decodeApps(from: cachedData) {
            debugLog("24時間以内のキャッシュから\(cachedApps.count)件を読み込みました。")
            return cachedApps
        }

        do {
            var request = URLRequest(url: YutarouAppsConfig.endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ... 299 ~= httpResponse.statusCode,
                  let apps = decodeApps(from: data)
            else { throw URLError(.cannotParseResponse) }

            defaults.set(data, forKey: cachedJSONKey)
            defaults.set(now, forKey: lastFetchedAtKey)
            debugLog("公開JSONから\(apps.count)件を取得しました。")
            return apps
        } catch {
            // 通信やJSONの問題は画面へ出さず、期限切れでも既存キャッシュを利用する。
            debugLog("公開JSONの取得に失敗しました: \(error.localizedDescription)")
            guard let cachedData,
                  let cachedApps = decodeApps(from: cachedData)
            else {
                debugLog("利用できるキャッシュがないため、おすすめ欄を非表示にします。")
                return []
            }
            debugLog("期限切れキャッシュから\(cachedApps.count)件を読み込みました。")
            return cachedApps
        }
    }

    /// 現在の配列形式に加え、将来 `{ "apps": [...] }` になっても読み込める。
    private static func decodeApps(from data: Data) -> [YutarouApp]? {
        let decoder = JSONDecoder()
        let decoded: [YutarouApp]

        if let items = try? decoder.decode([LossyDecodable<YutarouApp>].self, from: data) {
            decoded = items.compactMap(\.value)
        } else if let envelope = try? decoder.decode(YutarouAppsEnvelope.self, from: data) {
            decoded = envelope.apps.compactMap(\.value)
        } else {
            return nil
        }

        // 全件が不正なデータで、正常なキャッシュを上書きしない。
        return decoded.isEmpty ? nil : decoded
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[RecommendedApps] \(message)")
        #endif
    }
}
