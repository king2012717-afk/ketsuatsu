import FirebaseAnalytics
import FirebaseCore
import Foundation

/// YutarouLabs 共通の Firebase Analytics 薄いラッパー（仕様書 4-7）。
/// 起動と送信、共通イベント（main_action_complete・おすすめアプリ）だけを持つ。
/// このアプリ固有のイベントは `AppAnalytics` に置く。
enum AnalyticsService {
    /// おすすめアプリの `source_app`。apps.json の ID と同じ値にする（仕様書 4-8）。
    static let sourceApp = YutarouAppsConfig.currentAppID

    /// Firebase を起動する。`GoogleService-Info.plist` が無い、または Bundle ID が違うときは起動せず、
    /// 計測だけを止める（ビルドも起動もできる。仕様書 4-7）。
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            debugLog("GoogleService-Info.plist が見つからないため、計測を止めます")
            return
        }
        // 他アプリの plist を流用していると、別アプリの計測に混ざってしまう。
        guard options.bundleID == Bundle.main.bundleIdentifier else {
            debugLog("GoogleService-Info.plist の BUNDLE_ID（\(options.bundleID)）がアプリ（\(Bundle.main.bundleIdentifier ?? "-")）と違うため、計測を止めます")
            return
        }
        FirebaseApp.configure(options: options)
        // 起動のたびに決め直す（設定は端末に残るため）。
        Analytics.setAnalyticsCollectionEnabled(isCollectionEnabled)
        debugLog(isCollectionEnabled ? "送信します" : "Debug ビルドのため送信しません（スキームの -FIRDebugEnabled で有効）")
    }

    /// Release は常に送る。Debug はスキームの起動引数 `-FIRDebugEnabled` を付けたときだけ送る。
    /// 開発中の操作が本番の数字に混ざらないようにするため。
    static var isCollectionEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-FIRDebugEnabled")
        #else
        return true
        #endif
    }

    static func log(_ name: String, parameters: [String: Any] = [:]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }

    static func setUserProperty(_ value: String, forName name: String) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setUserProperty(value, forName: name)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[Analytics] \(message)")
        #endif
    }

    // onboarding_complete は送らない。
    // このアプリにはオンボーディング画面がなく、完了に当たる操作が存在しないため、
    // 代わりの画面に結び付けると意味の違うデータになる。導入する場合はその完了時に
    // log("onboarding_complete") を追加する。

    /// アプリ横断で「主要な操作を終えた」ことを数える共通イベント。
    /// 個別イベント（blood_pressure_entry_completed など）と同じタイミングで送るため、
    /// 両者を足し合わせて集計しないこと（詳しくは FIREBASE_ANALYTICS.md）。
    static func mainActionCompleted(action: String) {
        log("main_action_complete", parameters: ["action": action])
    }

    static func recommendedAppImpression(destinationApp: String, placement: String, campaign: String) {
        log("recommended_app_impression", parameters: recommendationParameters(
            destinationApp: destinationApp,
            placement: placement,
            campaign: campaign
        ))
    }

    static func recommendedAppClick(destinationApp: String, placement: String, campaign: String) {
        log("recommended_app_click", parameters: recommendationParameters(
            destinationApp: destinationApp,
            placement: placement,
            campaign: campaign
        ))
    }

    private static func recommendationParameters(
        destinationApp: String,
        placement: String,
        campaign: String
    ) -> [String: Any] {
        [
            "source_app": sourceApp,
            "destination_app": destinationApp,
            "placement": placement,
            "campaign": campaign,
        ]
    }
}
