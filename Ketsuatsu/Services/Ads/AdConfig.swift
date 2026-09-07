import Foundation

/// 広告ユニットIDをビルド構成で自動的に切り替える設定。
///
/// ⚠️ 開発中は必ず Google 公式のテストIDを使うこと。
/// 開発中のアプリで本番広告を表示・タップすると無効なトラフィックとみなされ、
/// AdMob アカウント停止の原因になる（2026年9月に実際に発生）。
enum AdConfig {

    // MARK: - 広告ユニットID

    /// Google公式 iOS デモバナー。
    /// **要求する広告サイズに対応したIDを使うこと。**
    /// アンカーアダプティブ → 2435281174 / 固定320x50 → 2934735716
    private static let demoBannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    /// 本番ユニットID（AdMob管理画面で発行した値に差し替える）
    private static let productionBannerUnitID = "ca-app-pub-4243897663299237/7828014939"

    // MARK: - 判定ロジック（変更禁止）

    /// 本番の広告ユニットIDを使ってよいか。
    /// 1. コンパイル時: Debug ビルドは常にデモID
    /// 2. 実行時: App Store から配信されたビルドであること
    ///    （Simulator / Xcode実行 / Profile / Ad Hoc / TestFlight はすべて除外）
    static var isUsingProductionAdUnits: Bool {
        #if DEBUG
        return false
        #else
        return AdsBuildEnvironment.isAppStoreBuild
        #endif
    }

    static var bannerUnitID: String {
        isUsingProductionAdUnits ? productionBannerUnitID : demoBannerUnitID
    }

    /// AdMobのテストデバイスID。
    /// ソースには埋め込まず、Xcodeスキームの環境変数 `AD_TEST_DEVICE_IDS` に
    /// カンマ区切りで設定する。App Store 配信ビルドでは常に空。
    static var testDeviceIdentifiers: [String] {
        guard !isUsingProductionAdUnits else { return [] }
        guard let raw = ProcessInfo.processInfo.environment["AD_TEST_DEVICE_IDS"] else { return [] }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - アプリ固有の設定

    /// 広告を表示するかどうか。将来「広告を消す」課金を入れる場合はここを見に行く。
    static var isEnabled: Bool { true }

    /// 広告まわりのログ。読み込めないときの切り分け用に Debug ビルドだけ出す。
    static func log(_ message: String) {
        #if DEBUG
        print("[Ads] \(message)")
        #endif
    }
}

/// ビルドの配信経路の判定。
/// App Store は配信時に `embedded.mobileprovision` を取り除くため、
/// これが存在するビルド（Xcode実行 / Profile / Ad Hoc / TestFlight）は false になる。
enum AdsBuildEnvironment {
    static var isAppStoreBuild: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") == nil else {
            return false
        }
        // TestFlight は sandbox のレシートを持つ。プロビジョニングの判定と二重化しておく。
        if let receipt = Bundle.main.appStoreReceiptURL?.lastPathComponent, receipt == "sandboxReceipt" {
            return false
        }
        return true
        #endif
    }
}
