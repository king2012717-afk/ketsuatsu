import Foundation

enum AdConfiguration {
    static let appKey = plistString("LevelPlayAppKey")
    static let bannerUnitID = plistString("LevelPlayBannerAdUnitID")
    /// 広告を出すか。Debug でも true（仕様書 1-6：ビルド構成で出し分けない）。
    /// 開発端末の要求が本番トラフィックに計上されないよう、動作確認は LevelPlay の Test devices に
    /// 登録した端末でだけ行う（docs/広告の動作確認手順.md）。
    static var isEnabled: Bool { true }
    static var isConfigured: Bool { !appKey.isEmpty && !bannerUnitID.isEmpty }

    private static func plistString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func log(_ message: String) {
        #if DEBUG
        print("[AdBanner] \(message)")
        #endif
    }
}
