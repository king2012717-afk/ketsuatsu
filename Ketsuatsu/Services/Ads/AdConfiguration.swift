import Foundation

/// AdMob の設定をまとめた場所。
///
/// 開発中（Debug ビルド）は Google のテスト用広告ユニットを使う。
/// 自分のアプリで自分の広告をタップすると規約違反となり、アカウントが止まることがあるため。
enum AdConfiguration {

    /// AdMob のアプリ ID。`Info.plist` の `GADApplicationIdentifier` にも同じ値を入れている。
    static let applicationID = "ca-app-pub-4243897663299237~4523194742"

    /// 本番のバナー広告ユニット ID。
    private static let productionBannerUnitID = "ca-app-pub-4243897663299237/7828014939"

    /// Google が公開しているテスト用のバナー広告ユニット ID。
    private static let testBannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    static var bannerUnitID: String {
        #if DEBUG
        return testBannerUnitID
        #else
        return productionBannerUnitID
        #endif
    }

    /// 広告を表示するかどうか。将来「広告を消す」課金を入れる場合はここを見に行く。
    static var isEnabled: Bool { true }

    /// 広告まわりのログ。読み込めないときの切り分け用に Debug ビルドだけ出す。
    static func log(_ message: String) {
        #if DEBUG
        print("[AdBanner] \(message)")
        #endif
    }
}
