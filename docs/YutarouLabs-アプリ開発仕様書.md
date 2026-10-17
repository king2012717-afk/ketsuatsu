# YutarouLabs iOSアプリ 開発仕様書

**最終更新：2026年10月15日**

**このファイルの使い方**：新しいアプリの開発を依頼するとき、このファイルを最初に読ませてください。
以降の指示は、このファイルに書かれた規則を前提とします。
各リポジトリには、このファイルを `CLAUDE.md` として置きます（Part 2-10）。

**規則の強さは3段階です。**

- **【必須】** … 例外なく守る。判断で変えてはいけない。変更が必要なら必ず確認を取る
- **【推奨】** … 特別な理由がなければ従う。外す場合は理由を報告する
- **【参考】** … 既存アプリの傾向。参考にしてよい

**2026年10月15日版で暫定にしている3点（要確認）**

| 項目 | 暫定値 | 根拠 |
|---|---|---|
| Flutter | 新規禁止を維持。既存の Flutter アプリは「うちの沿線速報」「うちのマインスイーパー」の2本のみ | マインスイーパーは9/1に Flutter で着手済み |
| 起動画面 | `LaunchScreen.storyboard` を標準。黒帯等が storyboard で直せないときだけ `UILaunchScreen` を許可し、理由を報告 | 9/7の全リポジトリ一括導入が storyboard。家計簿のみ9/23に `UILaunchScreen` へ変更 |
| ダークモード | 対応を【推奨】。文字が消える等の不具合が直せないときは `.preferredColorScheme(.light)` でライト固定し、理由を報告 | ネコは9/21にライト固定で対処 |

---

# Part 0. 最重要の背景

2026年9月、AdMobのパブリッシャーアカウント（pub-4243897663299237）が
**無効なトラフィックおよびポリシー違反により停止**されました。
このため、広告を掲載するアプリは **Unity LevelPlay** をメディエーション基盤とし、
**ironSource Ads と Unity Ads** を配信ネットワークとして使用します。
AdMob SDK・AdMob広告ID・Google Mobile Adsの広告表示コードは新規実装へ戻さないでください。

原因は3つでした。**同じ失敗を二度と起こさないことが、この仕様書の最大の目的です。**

| # | 原因 | 影響 |
|---|---|---|
| 1 | 開発端末が本番扱いの広告を要求していた | 開発中の動作確認が本番トラフィックに計上された |
| 2 | 同意処理が広告SDK初期化より後、または無効だった | 同意を取らずに広告をリクエストしていた |
| 3 | ゲーム開始時に全画面広告を出していた | インタースティシャル広告ポリシー違反 |

**Part 1 の広告仕様は、この事故の直接の再発防止策です。一字一句そのまま適用してください。**

**その後に起きた審査差し戻し（再発防止として本書に反映済み）**

| 日付 | アプリ | 内容 | 反映先 |
|---|---|---|---|
| 2026-09-22 | うちの美術館 | Guideline 2.1「ATTの要求が見つからない」。同意画面で「パーソナライズしない」を選ぶとATTを出さない実装だったため、審査員がそちらを押すと一度も表示されなかった | 1-5 |

---

# Part 1. 現行広告実装：Unity LevelPlay【必須】

このPartが現在の正規仕様です。旧AdMob実装へ戻したり、AdMob用サンプルをコピーしたりしません。

## 1-1. 採用構成

- メディエーション：**Unity LevelPlay**
- 広告ネットワーク：**ironSource Ads（Bidding）＋ Unity Ads**
- iOS依存管理：原則 **Swift Package Manager**
- LevelPlay：`LevelPlay-Swift-Package`（製品名 `UnityMediationSDK`）
- Unity Adsアダプタ：`LevelPlay-UnityAds-Adapter-Swift-Package`（製品名 `UnityAdsAdapter`）
- Unity Ads SDKとAd Quality SDKは、アダプタが要求する互換バージョンを使う
- `Package.resolved` はコミットし、動作確認した組み合わせを再現できるようにする
- ironSource AdsはLevelPlay SDK側に含まれるため、別のironSourceアダプタを重複追加しない
- SDKの版番号をこの仕様書へ恒久的に固定しない。更新時は公式互換表を確認し、全アプリ一括ではなく1アプリで先に検証する
- **LevelPlay 9.5以降のバイナリは Xcode 26 世代の Swift ランタイムを参照する。** Firebase等と併用するアプリは Xcode 16.x ではリンクに失敗する（資格ノートのCIで確認済み）。ビルド環境は Xcode 26 以上を前提とする

## 1-2. 使用する広告形式

- 各アプリで**実際に必要な形式だけ**実装する
- LevelPlay管理画面に存在するだけの広告形式を、コード側へ自動追加しない
- Banner：既存アプリでバナーを使っていた場合のみ
- Interstitial：ゲーム終了など、明確な自然な区切りがある場合のみ
- Rewarded：ユーザーが報酬内容を理解し、自分で視聴ボタンを押す機能がある場合のみ
- App Open・Native・MREC（300×250）は、個別指定がない限り実装しない
- 未使用形式のAd Unit ID、広告オブジェクト、ロード処理は残さない

## 1-3. SDK初期化とAd Unit API

旧来の広告形式一括初期化APIではなく、LevelPlayのAd Unit APIを使用します。

```swift
import IronSource

let request = LPMInitRequestBuilder(appKey: AdConfig.appKey).build()
LevelPlay.initWith(request) { _, error in
    guard error == nil else { return }
    // 初期化成功後に、使用する形式だけ生成・ロードする
}
```

- Banner：`LPMBannerAdView(adUnitId:)`
- Interstitial：`LPMInterstitialAd(adUnitId:)`
- Rewarded：`LPMRewardedAd(adUnitId:)`
- Unity Ads SDKをアプリコードから直接初期化しない。LevelPlayとUnity Adsの二重初期化は禁止
- SDK初期化はアプリ起動中に1回だけ。広告形式ごとのオブジェクトも使い回す
- 初期化成功前に広告オブジェクトを生成・ロードしない

## 1-4. App KeyとAd Unit ID

値はソースコードへ散在させず、`Info.plist`またはBuild Settingsへ集約します。

```xml
<key>LevelPlayAppKey</key>
<string>アプリ固有のApp Key</string>
<key>LevelPlayBannerAdUnitID</key>
<string>使用する場合のみ</string>
<key>LevelPlayInterstitialAdUnitID</key>
<string>使用する場合のみ</string>
<key>LevelPlayRewardedAdUnitID</key>
<string>使用する場合のみ</string>
```

- App KeyとAd Unit IDはアプリごとに異なる。別アプリの値を流用しない
- 値が空、またはプレースホルダーのときはSDK初期化・広告要求を安全に停止する
- Ad Unit IDとUnity AdsのPlacement IDを混同しない。アプリコードに入れるのはLevelPlayのAd Unit ID
- LevelPlay管理画面では、対象形式ごとにironSource AdsとUnity Adsのインスタンスを有効化する
- App KeyとAd Unit IDの取得・Unity Ads紐付けは別チャットで行うことが多い。その指示文と結果は `docs/` に残す（2-2）

## 1-5. プライバシー・ATT・同意

順序は **同意取得 → LevelPlayプライバシー設定 → ATT → SDK初期化** とします。

- GDPR等の同意結果を取得してから、対応SDKでは `LPMPrivacySettings.setGDPRConsent(_:)` を設定する
- COPPA対象の有無はアプリの対象年齢に合わせ、必要な場合はSDK初期化前に設定する
- `NSUserTrackingUsageDescription` を必ず設定する
- **ATTは同意画面の選択に関わらず、未決定なら必ず1回要求する。**
  「パーソナライズしない」を選んだ場合もATTを出す。パーソナライズの可否はLevelPlay側の同意設定で決めるので、
  「しない」を選んだ人がATTで許可しても広告はパーソナライズされない（2026-09-22 美術館の差し戻し対応）
- 同意画面の文言に「このあと iOS の確認画面が表示されます」を入れる
- ATTが未決定なら、アプリUI表示後の自然なタイミングで1回だけ要求する
- ATT拒否時もクラッシュさせず、SDKが許可する非パーソナライズ／制限付き配信へ進める
- 同意状態が確定する前に広告をロードしない
- Unity Adsの「new privacy APIsを使っていない」という警告を放置しない
- 審査メモとプライバシーポリシーの記述は、実装したATT・同意の挙動と一致させる

## 1-6. 開発端末とテスト広告

**Debugコードでログを出すことと、テスト広告になることは別です。**

- **ビルド構成（Debug／Release）で広告の出し分けはしない。** Xcodeからの実機実行でも本番の広告ユニットへリクエストが飛ぶ。
  だからこそ、動作確認は必ず登録済みテストデバイスで行う
- 開発に使う実機は、LevelPlay管理画面の **Test devices** に端末ID（IDFV）を登録する
- 対象の広告ネットワークと、実装済み広告形式をすべて選択する
- `#if DEBUG` 内だけで `LevelPlay.setAdaptersDebug(true)` を有効化する
- `setAdaptersDebug(true)` だけをテスト広告保証として扱わない。管理画面のテストデバイス登録も必須
- Integration Test Suiteは動作確認専用。通常起動の本番コードから自動表示しない
- シミュレーターはレイアウト・SDK初期化確認に使えるが、広告配信の最終確認は登録済み実機で行う
- テスト端末でも広告は絶対に意図的クリックしない
- Release／Archiveではデバッグログ、Test Suiteボタン、画面上部の診断表示を含めない
- 動作確認の手順は `docs/広告の動作確認手順.md` に書き、アプリごとに持つ

## 1-7. Banner

- バナーはアプリ全体で原則1枚。画面遷移のたびに生成し直さない
- Safe Areaを尊重し、操作ボタンやコンテンツと重ねない
- 広告と操作領域の間に余白または背景差を設け、誤タップを防ぐ
- オンボーディング、初期設定、学習・演習中、ゲーム盤面操作中は表示しない
- **表示条件を満たさない間は、バナーのView自体を生成しない**（＝広告リクエストも発生させない）。
  条件：同意フロー完了（`canRequestAds`）／広告削除を未購入（1-12）／初期設定中でない
- `loadAd()`は生成時に1回。View更新のたびに呼ばない
- Auto Layoutでは位置アンカー同士を結び、`topAnchor`等を定数だけに制約しない
- No fillはアプリ障害として表示せず、おすすめ欄や本体UIを崩さない

## 1-8. Interstitial

- アプリ起動時、画面表示直後、ゲーム開始時、失敗直後、やり直し直後には表示しない
- ランダム確率だけで表示しない
- ゲーム終了後にスタート画面へ戻るなど、明確な自然な区切りでのみ表示する
- 回数条件と最短時間条件を併用し、連続表示を防ぐ
- 読み込み未完了なら本体処理を止めず、その回は広告をスキップする
- 学習・資格・記録アプリには入れない（4-1、4-2）

## 1-9. Rewarded

- 視聴前に、得られる報酬をボタン付近へ明示する
- ユーザー操作でのみ表示し、自動再生しない
- `didRewardAd`を受け取った場合だけ報酬を確定する
- closeとrewardの通知順は固定とみなさず、報酬の二重付与を防ぐ
- 「広告開放」は動画視聴完了後 **1時間**。視聴できる間隔も **1時間に1回**
- 開放期限は**視聴時刻から数える。重ねて延長しない**（期限内にもう一度見ても延びない）
- 次に視聴できる時刻をボタン付近に表示する
- この計算は `AdFreePolicy` のような純粋な型へ切り出し、単体テストで確認する（英会話で実装済み）
- 広告ロード失敗時に、勝手に報酬を付与する設計は個別仕様がない限り禁止する

## 1-10. 失敗処理と多重ロード防止

- 広告形式ごとに`isLoading`を持ち、同時ロードは1件まで
- 全画面広告表示中は、別の全画面広告を表示しない
- 失敗時は上限付きバックオフ。無限リトライしない
- バックグラウンド中は再試行しない
- No fillや通信失敗をユーザー向けエラーとして表示しない
- 広告の不具合でアプリ本体をクラッシュ・停止させない

## 1-11. 旧AdMobの削除

LevelPlayへ移行したアプリでは、不要になった次の項目を削除します。

- `GoogleMobileAds`とAdMobメディエーション用SDK
- AdMob本番広告ID、`GADApplicationIdentifier`、旧バナー／全画面広告コード
- AdMobだけのために入れていた依存関係
- 未使用になったUMP。ただし同意管理にGoogle UMPを継続利用すると明示したアプリは除く

削除後、プロジェクト内を`GAD`、`ca-app-pub-`、`GoogleMobileAds`で検索し、意図しない残存がないことを確認します。

## 1-12. 課金（広告削除・機能開放）と広告の関係

買い切り課金は **StoreKit 2** で実装します。うちのネコ・うちのデグー・うちのイヌ・うちの英会話で共通です。

**商品の種類**

| 商品 | 商品ID | 効果 |
|---|---|---|
| 広告削除 | `<BundleID>.adfree` | 広告だけが消える。機能は解放されない |
| 機能開放 | `<BundleID>.premium` | 有料機能がすべて使える。広告は消えない |

- どちらも**非消耗型**。アプリによって片方だけでもよい
- 商品IDはApp Store Connectと一致させる。`<BundleID>` は本体のBundle ID
- `<AppName>.storekit`（StoreKit Configuration）を同梱し、Xcodeで購入テストできるようにする

**実装の約束**

- 購入状態は App Group の共有 `UserDefaults` に保存し、ウィジェット・拡張とも共有する
- `adfree` 購入後は、バナー・全画面・ネイティブのすべてを出さず、Viewも生成しない
- 「購入を復元」ボタンを設定画面に常設する（審査ガイドライン 3.1.1）
- 有料機能の一覧と解放方式（購入のみ／広告で1時間開放／広告でチケット1枚）は
  `PremiumFeature`（`EntitlementManager.swift`）で一元管理し、散在させない
- 無料状態で有料機能に触れたときのペイウォールに、価格（`product.displayPrice`）を表示する
- 設定画面の「プラン」セクションに購入状況を出す。DEBUG限定のテスト用スイッチはReleaseに含めない
- 初回提出時は、App内課金を「Appのバージョンに紐づけ」て一緒に審査へ出す
- 「契約／税金／口座情報」で有料Appの契約が有効でないと商品が取得できず、価格が出ない

**解放方式の既存例【参考】（うちのネコ）**

| 機能 | 解放方法 |
|---|---|
| 複数ペットの管理 | 購入 / 広告で1回だけ追加できるチケット |
| 家族共有 | 購入のみ（発行する側だけ。参加する側は無料） |
| 写真の添付 | 購入 / 広告で1時間開放 |
| 過去の記録閲覧 | 購入 / 広告で1時間開放 |
| ウィジェット | 購入のみ |

---

# Part 2. 全アプリ共通の土台

## 2-1. 技術スタック【必須】

| 項目 | 指定 |
|---|---|
| 言語 / UI | Swift + SwiftUI |
| 最低iOSバージョン | **17.0**（新規アプリは17.0で統一。16.0のまま残っているものは更新時に17.0へ上げる） |
| ビルド環境 | **Xcode 26 以上**（LevelPlay 9.5以降、FoundationModels、Firebase併用のため） |
| データ永続化 | SwiftData（小規模なら UserDefaults + Codable） |
| 依存管理 | Swift Package Manager |
| アーキテクチャ | MVVM。ViewModel は `@MainActor final class ... ObservableObject`（新規は `@Observable` も可） |
| 外部通信 | 原則なし。**完全オフラインで動くことを優先**。例外は 4-5（外部API）、2-12（CloudKit共有）、4-7（計測）に限る |
| 家族共有 | CloudKit パブリックDB＋世帯コード（2-12）。**Firebase（Firestore／Auth／FCM）とCKShareは使わない** |

Flutter は「うちの沿線速報」「うちのマインスイーパー」の2本のみ。**新規アプリでは使わない。**

## 2-2. プロジェクト構成【推奨】

```
<repo>/
  CLAUDE.md                     … この仕様書（2-10）
  <AppName>.xcodeproj           … XcodeGen を使う場合は project.yml が正
  project.yml                   … XcodeGen 使用時のみ
  <AppName>/
    <AppName>App.swift          … @main
    RootView.swift              … バナー＋本体の土台
    Theme.swift                 … 配色（後述）
    AdConfig.swift              … Part 1-4
    AdsManager.swift             … Part 1-3、1-10
    PrivacyConsentManager.swift  … Part 1-5
    BannerAdView.swift           … Part 1-7
    AdFreePolicy.swift           … Part 1-9（リワード使用時）
    StoreManager.swift           … Part 1-12（課金使用時）
    EntitlementManager.swift     … Part 1-12（課金使用時）
    SharingManager.swift         … Part 2-12（家族共有使用時）
    Analytics/                   … Part 4-7（計測使用時）
    Info.plist
    PrivacyInfo.xcprivacy        … Part 2-13【必須】
    LaunchScreen.storyboard      … Part 2-11
    Assets.xcassets              … LaunchBackground / LaunchIcon / LaunchWordmark を含む
    Models.swift / Stores/ / Views/ / Game/ …（アプリ固有）
  <AppName>.storekit             … 課金使用時
  <AppName>Tests/                … Part 2-14
  <AppName>Widget/               … ウィジェット使用時
  AppStoreAssets/
    App-Store-登録情報.md        … ストア掲載文の原本（審査対応の記録・公開後の作業も追記する）
    Screenshots/
  Tools/
    make_icon.py                … アイコン生成
    make_store_screenshots.py   … スクショ生成
  docs/
    広告の動作確認手順.md         … Part 1-6
    HANDOFF.md                  … 別チャット・別セッションへ渡す指示文と、その結果
    PRIVACY_POLICY.md           … 公開するプライバシーポリシーの原本
  .github/workflows/ios.yml     … Part 2-14
```

- Bundle ID は `com.yutaroulabs.<slug>`（すべて小文字）【必須】
  - ウィジェットは `<本体ID>.widget`、共有拡張は `<本体ID>.share`、テストは `<本体ID>.tests`
  - App Group は `group.<本体ID>`
  - 既存アプリの `com.YutarouLabs.*`、`com.<slug>.app`、`jp.ohno.*` は変更しない（App Store Connect登録済みのため）。新規は上の形式のみ
- リポジトリ名はアプリのスラッグ（`gomi`, `numpre`, `book` など）

## 2-3. Theme.swift【必須】

**配色はアプリアイコンから起こす。** 先にアイコンを決め、そこから色を抽出する。
これが「うちの◯◯」シリーズの統一感の源になっている。
アイコンを差し替えたときは、必ず配色も取り直す（簿記3級・家計簿・交換日記で毎回発生した作業なので、`Tools/make_icon.py` に色の書き出しを含める）。

```swift
import SwiftUI

/// アプリの配色。アプリアイコンから色を起こしている。
enum Theme {
    // メイン：アイコンのグラデーション3色（明→中→濃）
    static let leafLight = Color(red: 0.624, green: 0.792, blue: 0.212)
    static let leaf      = Color(red: 0.435, green: 0.651, blue: 0.188)  // 主役色
    static let leafDeep  = Color(red: 0.286, green: 0.529, blue: 0.169)  // 白文字を載せる濃さ
    static let leafDark  = Color(red: 0.216, green: 0.412, blue: 0.122)  // 文字色

    // 背景：主役色をごく薄めたオフホワイト
    static let base     = Color(red: 0.965, green: 0.976, blue: 0.945)
    static let baseDeep = Color(red: 0.878, green: 0.918, blue: 0.816)
    // アクセント：主役色の補色寄り（注意喚起・今日の予定など）
    static let alert    = Color(red: 0.886, green: 0.478, blue: 0.137)
    // 文字
    static let ink     = Color(red: 0.133, green: 0.188, blue: 0.106)
    static let inkSoft = Color(red: 0.361, green: 0.420, blue: 0.322)
    static let card    = Color(red: 1.000, green: 1.000, blue: 0.992)

    /// 白文字を載せる主要ボタン用
    static let brandGradient = LinearGradient(
        colors: [leaf, leafDeep], startPoint: .top, endPoint: .bottom
    )
    static let cornerRadius: CGFloat = 18
}
```

**必ず守ること**

- 色は**すべて Theme に集約**。View に生の `Color(red:...)` を書かない
- 角丸は `Theme.cornerRadius` を使う
- `.tint(Theme.leaf)` をルートに当てる
- ダークモード【推奨】：ダークモードでも読めることを確認する。直せない不具合（文字が消える等）があるときだけ
  `.preferredColorScheme(.light)` でライト固定し、理由を報告する（暫定。冒頭の要確認事項）

## 2-4. アプリ名とブランド【必須】

- アプリ名は **「うちの◯◯」** で統一（例外は Pinball のみ）
- `CFBundleDisplayName`（`INFOPLIST_KEY_CFBundleDisplayName`）に「うちの◯◯」を設定し、ホーム画面と起動画面のラベルを揃える
- 販売元表記：`Yutarou Nagano`
- 著作権表記：`2026 YutarouNagano`
- サポートURL：`https://yutaroulabs.com/support/<slug>/`
- マーケティングURL：`https://yutaroulabs.com`
- プライバシーポリシーURL：`yutaroulabs.com` 配下に置く。原本は `docs/PRIVACY_POLICY.md`

## 2-5. オンボーディング【推奨】

- 初回起動時のみ表示。`AppSettings.didFinishOnboarding` で管理
- **オンボーディング中はバナーを表示しない**（1-7参照）
- 3〜5画面以内。長くしない
- 完了後にホームへ遷移

## 2-6. スクリーンショット撮影モード【推奨】

App Store 用の素材を撮るとき、広告が写り込まないようにする（審査ガイドライン 2.3.10）。

```swift
private var isScreenshotMode: Bool {
    ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
}
// バナー表示条件に  !isScreenshotMode  を足す
```

- 環境変数名は `SCREENSHOT_MODE` に統一する。起動引数（`-disableAds` 等）は使わない

## 2-7. バージョン管理【必須】

**Info.plist にバージョンを直書きしない。** これをやると Xcode の General タブで
変更しても反映されず、原因追跡に時間を取られる（2026年9月に4本で発生）。

```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
```

- ウィジェットや App Extension のバージョンは **本体と必ず一致させる**。
  ズレているとアップロードで弾かれる
- `1.0`、`1.1`等をSwiftコード、Info.plist、ビルドスクリプトへ固定しない
- ネイティブiOSでは、XcodeのTarget > Generalに表示されるVersion／Buildを変更元とし、
  Debug・Releaseの両方が`MARKETING_VERSION`／`CURRENT_PROJECT_VERSION`を参照する
- 新しいArchiveを作る前に、App Store Connectへ既にアップロード済みの組み合わせと重複しないよう
  **Buildを必ず増やす**。Versionはリリース内容に合わせて変更する
- FlutterアプリをXcodeからArchiveする場合も、iOSの`Info.plist`は
  `$(MARKETING_VERSION)`／`$(CURRENT_PROJECT_VERSION)`を参照する。
  `Generated.xcconfig`の古い`FLUTTER_BUILD_NAME`／`FLUTTER_BUILD_NUMBER`をArchiveの値に使わない
- Flutterの`pubspec.yaml`の`version: x.y.z+build`は、XcodeのVersion／Buildと同じ値へ同期する。
  ただしArchiveの変更元はXcodeのTarget > Generalとし、そこで変更した値が必ず成果物へ反映されることを確認する
- XcodeGen を使う場合、**バージョンだけでなく Team・Bundle ID・Info.plist のキーも `project.yml` 側が正**。
  Xcode で直接変えても次の `xcodegen generate` で消える

## 2-8. Team・署名設定【必須】

- Apple Developer Teamは **Yutarou Nagano（Team ID: `JS7SYSHC3S`）** を設定する
- `DEVELOPMENT_TEAM = JS7SYSHC3S`（XcodeGen の場合は `project.yml` に書く）
- `CODE_SIGN_STYLE = Automatic`
- Debug／Release、アプリ本体、Widget、App Extensionのすべてに同じTeamを設定する
- Bundle IdentifierはApp Store Connectに登録済みの値を維持し、署名エラー回避のために勝手に変更しない
- 新規アプリは、Archive前に実機向け署名と`Any iOS Device`向けArchiveが通ることを確認する
- Flutterは`ios/Runner.xcworkspace`を開き、Runnerターゲットと追加ExtensionのTeamを確認する
- App Group を使うアプリは、本体とウィジェット・拡張の両方に **App Groups** のCapabilityを付ける

## 2-9. .gitignore【必須】

新規リポジトリには必ず以下を含める。

```
.DS_Store
xcuserdata/
*.xcuserdatad/
*.xcuserstate
DerivedData/
build/
*.moved-aside
*.hmap
*.ipa
*.dSYM.zip
*.dSYM
GoogleService-Info.plist   … 計測を使うアプリで、公開リポジトリの場合のみ
```

## 2-10. ブランチ運用と仕様書の配置【必須】

2026年10月の棚卸しで、10リポジトリ中8本で実装が `claude/...` や `feature/...` ブランチにだけ存在し、
`main` が「Initial commit」のままになっていた。Archive元が追えなくなるため、次を守る。

- 作業は `claude/<topic>` ブランチで進めてよいが、**Archive・提出前に必ず `main` へマージする**
- `main` の HEAD と App Store Connect へ上げた Build を対応させ、原本（`App-Store-登録情報.md`）に記録する
- マージ済みの作業ブランチは削除する。`claude/tmp-*` のような検証用ブランチも残さない
- この仕様書を各リポジトリの直下に `CLAUDE.md` として置く。仕様書を更新したら、次にそのリポジトリを触るときに差し替える
- 複数リポジトリへ同じ変更を入れるとき（起動画面の一括導入、計測の一斉導入など）は、同名のブランチで揃え、
  `docs/HANDOFF.md` に対象アプリ一覧と結果を残す

## 2-11. 起動画面【必須】

2026年9月7日に `yutaroulabs-launch-screen-audit` ブランチで全リポジトリへ共通起動画面を導入した。
新規アプリも同じ構成にする。

- 素材は `yutaroulabs-website` リポジトリの公式テンプレートから取る。アプリごとに
  `LaunchBackground` / `LaunchIcon`（1x/2x/3x） / `LaunchWordmark`（1x/2x/3x）の3 imageset を `Assets.xcassets` に追加
- `LaunchScreen.storyboard` を公式テンプレート準拠で追加し、
  `INFOPLIST_KEY_UILaunchScreen_Generation` ではなく `INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen` を使う
- 起動を遅らせる実装（スプラッシュの待ち時間など）は入れない
- 画面の左右に黒帯が出るなど storyboard で直せない表示不具合があるときだけ、`UILaunchScreen`（Info.plist 直書き）へ
  切り替えてよい。理由を報告する（暫定。冒頭の要確認事項）

## 2-12. 家族・パートナーとの共有【推奨／方式は必須】

共有を実装する場合は、うちのデグー・うちのネコ・うちの家計簿で統一した **世帯コード方式** にする。
CKShare（招待リンク）と Firebase は使わない（CKShare はリンクを開いてもらう手数と受諾処理が多く、
Firebase は CloudKit と二重になるため。ネコは Firebase から、家計簿は CKShare から作り直した）。

**方式**

- 6桁の招待コード（世帯コード）を1つ決め、共有するデータに `householdCode` として付ける
- 別の Apple ID の家族が同じコードを入力すれば、同じデータを読み書きできる
- CloudKit の**パブリックデータベース**をコードで絞り込んで同期する
- 競合は `updatedAt` の後勝ち。削除は墓石（tombstone）で伝える
- 家族が記録したら `CKQuerySubscription` で通知が届き、その場で同期する
- 起動時・アプリに戻ったとき・「今すぐ同期」で同期する
- 送るのは `needsSync` が立っている変更分だけ。保存に成功したレコードだけ `needsSync` を下ろす
  （失敗したものまで送信済みにすると変更が黙って失われる）
- プル時の突き合わせは辞書索引で行う（全件走査は件数の二乗で遅くなる）
- 共有拡張・ショートカット（App Intents）からの記録にも世帯コードが付くよう、定数は全ターゲットから読める場所に置く

**設計の約束**

- **共有は任意機能。** 単独でも価値が完結するようにし、相手がいない人が初回で離脱しない設計にする
- 「自分だけ」区分のデータには世帯コードを付けず、クラウドへ一度も送らない
- コードの発行側を有料（`premium`）にしてよいが、参加側は無料にする（1-12）
- 参加が空振りした（コードに該当データがない）ときに気づける表示を出す
- 初回画面の「招待コードで参加」は、コード入力だけの画面にする（ログイン画面を挟まない）

## 2-13. Privacy Manifest（PrivacyInfo.xcprivacy）【必須】

全アプリに `PrivacyInfo.xcprivacy` を置く。内容は App Store Connect の「アプリのプライバシー」の回答と一致させる。

LevelPlay（ironSource Ads＋Unity Ads）構成の標準値：

| 項目 | 値 |
|---|---|
| `NSPrivacyTracking` | `true`（ATTを出すため） |
| `NSPrivacyTrackingDomains` | 空配列（SDK側のマニフェストに任せる） |
| 収集データ | `DeviceID`、`AdvertisingData`、`ProductInteraction`。いずれも 目的＝`ThirdPartyAdvertising`、ユーザーに紐づけない、トラッキングに使わない |
| 必須理由API | `UserDefaults` → `CA92.1`。他に使うAPI（ファイルタイムスタンプ等）があれば追加 |

- アプリ本体が集めるデータ（記録・学習履歴・音声）は端末内に留め、収集データに含めない
- 広告SDKを追加・削除したら、このファイルと App Store Connect の回答を同時に見直す
- 計測（4-7）を入れたアプリは `ProductInteraction` の目的に `Analytics` を足す

## 2-14. テストとCI【推奨】

ロジック層には単体テストを置く。直近のアプリでは当たり前になっている（交通ナビ84件、マインスイーパー回帰テスト、英会話のUIテスト）。

- 対象：`Game/` のルール、`AdFreePolicy`、経路・判定・解析などUIに依存しないもの、計測の「N回目」カウンタ
- UIに依存しないよう、テスト対象は `Foundation` のみに依存する型へ切り出す
- 「コードレビューで見つかった不具合」を直したときは、回帰テストを同じコミットに入れる
- `.github/workflows/ios.yml` で、push／PR ごとに次を回す：
  1. `macos-15` ランナーで Xcode 26 系を選択
  2. （XcodeGen の場合）`brew install xcodegen` → `xcodegen generate`
  3. `xcodebuild -resolvePackageDependencies`
  4. `generic/platform=iOS Simulator` で `CODE_SIGNING_ALLOWED=NO` のビルド
  5. `build-for-testing`
- CI が緑であることを提出前の条件に含める（Part 6）

## 2-15. Apple Intelligence・App Intents【推奨】

美術館（解説の要約・自然文検索）、交通ナビ（文章での検索・Siriショートカット）、英会話（AIコーチ）で導入済み。

- `FoundationModels` は **Deployment Target 17.0 を維持したまま**、次の三重ガードで使う：
  1. `#if canImport(FoundationModels)`
  2. `if #available(iOS 26, *)`
  3. `SystemLanguageModel.default.availability` が `.available` のときだけ有効（`OnDeviceIntelligence.isAvailable`）
- 使えない端末では機能を隠すか、従来の処理（キーワード検索など）へ無言で落とす。エラーは出さない
- `@Generable` を付ける構造体は **private にしない**（生成される extension から見えずビルドが止まる。実績あり）
- Siriから開く機能は `AppIntents` の App Entity として公開し、「うちの◯◯で（名前）を検索」の形にする
- ビルドには Xcode 26 が必要。CI でも Xcode 26 系を選ぶ（2-14）

## 2-16. ホーム画面ウィジェット【推奨】

- ウィジェットターゲットの Bundle ID・バージョン・Team は 2-2、2-7、2-8 に従う
- 本体との共有は App Group の `UserDefaults`（`WidgetSync` / `StudySnapshot` のような共有型を `Shared/` に置く）
- 購入状態（1-12）も App Group 経由で共有し、ウィジェットが有料機能なら購入前は案内表示にする
- 拡張の `Info.plist` に必須キー（`NSExtension` 等）を忘れない（家計簿で不足してアップロードが止まった）
- ウィジェットのタップで本体の該当画面を直接開く
- 写真を表示するときは原寸データを渡さない。`ImageIO` のサムネイル生成API等で、フルデコードせず表示サイズまで縮小する
- Timelineは必要最小限とし、短時間の過剰更新を要求しない。空データ、App Group不整合、未購入の各状態に専用表示を用意する
- 本体のモデル・App Groupのキー・購入状態の形式を変更したときは、旧バージョンのウィジェットからも安全に読めるか確認する
- Live Activityを実装する場合は二重開始を防止し、正常終了・強制終了・日付変更・アプリ再起動後の後始末を実機確認する
- Live Activityの開始方法と終了方法を審査メモへ記載する

## 2-17. リリース元ブランチとコミットの正本【必須】

App Storeへ提出するコードの正本は `main` とする。作業ブランチだけに完成実装を残さない。

- Archive前に作業ブランチを `main` へマージし、`main` から同じArchiveを再現できる状態にする
- `App-Store-登録情報.md` に、Version、Build、Archive元コミットSHA、提出日を記録する
- 記録したコミットSHAは `main` から到達可能でなければならない
- `main` へのPRでは、ビルドと単体テストの必須チェックが成功するまでマージしない
- 一時検証用workflowは、検証完了後に正式な `.github/workflows/ios.yml` へ統合するか削除する
- リリース後は不要になった `claude/*`、`feature/*`、一時検証ブランチを整理する。未マージの変更がないことを確認してから削除する
- `main` がREADMEや初期コミットだけで、実装が作業ブランチにしかない状態を禁止する

## 2-18. 通知・リマインダー共通仕様【通知を使う場合は必須】

通知・ユーティリティだけでなく、記録・健康・ペット・家計簿などのリマインダーにも適用する。

- 通知権限は初回起動直後に自動要求せず、ユーザーが通知を有効化した時点で要求する
- 通知IDにはアプリ固有prefixを付け、無効化・再設定時は自アプリの対象通知だけを削除する
- 設定変更時、アプリ起動時、前面復帰時、タイムゾーン変更後に必要な通知を再構築する
- 拒否・制限中はアプリ本体を止めず、現在の状態と「設定」アプリへの導線を表示する
- 曜日×時刻、個別予定を含め、登録前に64件上限を検査する。上限を超える場合の優先順位を定義する
- 通知文面だけで目的が分かるようにし、個人情報・健康情報をロック画面へ過剰表示しない
- 通知生成をUIから分離し、識別子、曜日、時刻、件数上限、夏時間・タイムゾーンを単体テストする
- 通知タップ時の遷移先を定義する。対象データが削除済みでも安全にホームへ戻れるようにする

## 2-19. エクスポート・インポート・バックアップ【使用する場合は必須】

家族共有とは別の機能として扱う。CSV/PDFは閲覧・提出用、JSON等のバックアップは復元用と役割を分ける。

- CSVは原則UTF-8 BOM付きとし、カンマ、引用符、改行を含む値を正しくエスケープする
- 日付書式、ロケール、タイムゾーン、単位を固定し、ヘッダーに単位を明記する
- 復元用データには `schemaVersion` と `exportedAt` を含める
- 復元方式は「全置換」または「UUID等によるマージ」のどちらかを明記し、意図せず既存データを消さない
- インポート実行前に対象件数を表示し、完了後に追加・更新・重複・不正行の件数を表示する
- 同じファイルを複数回読み込んでも重複登録しない仕組みを持つ
- 旧schemaのmigration、壊れたファイル、空ファイル、巨大ファイルをテストする
- 写真・メモ・健康情報を含む場合は、共有前に個人情報を含むことを表示する
- 共有用の一時ファイルは推測しにくい名前またはアプリ専用一時領域へ作成し、不要後に削除する
- Analyticsにはファイル名、自由記述、記録内容を送らない。送る場合は形式と成功／失敗、件数区分だけにする

---

# Part 3. ストア提出の共通仕様

## 3-1. 事前に用意するもの

| 項目 | 仕様 |
|---|---|
| スクリーンショット | iPhone 6.9インチで3〜5枚。1枚目に価値提案のコピーを載せる。広告を写さない（2-6） |
| プロモーション用テキスト | 170字以内。**アプリの最も強い1点**を書く |
| 概要 | 見出しに `■` を使い、機能ブロックで区切る |
| キーワード | 100字以内。カンマ区切り、スペースなし |
| 審査メモ | ログイン要否、主要機能、広告の表示場所、リワード確認手順、課金の確認手順、ATTの出方を明記 |

**審査メモの定型文（該当するものを入れる）**

- 広告：「広告は Unity LevelPlay（ironSource Ads／Unity Ads）です。バナーは◯◯画面の上部、リワードは設定＞広告から任意で視聴できます」
- ATT：「初回起動時に同意画面のあと、選択に関わらず iOS のトラッキング確認を表示します」
- 課金：「設定＞プランで『広告を削除』（非消耗型）を購入できます。『購入を復元』も同じ画面にあります」
- 音声：「音声認識は Apple の Speech フレームワークのみを使用し、音声は開発者のサーバーへ送信しません」
- 問題データ：「問題はすべてオリジナルです。出典は◯◯（公的機関名）の公開資料です」

## 3-2. 落とし穴【必須で覚えること】

- **新バージョンを作るとプロモーション用テキストは空になる。** 引き継がれない。
  必ず旧バージョンの文面を控えてから作成する
- 「このバージョンの最新情報」は初回リリース（1.0）では入力欄が出ない
- ビルド番号は同一バージョン内で一意であればよい。バージョンを上げたら 1 に戻してもよい
- **年齢制限の質問票は3行形式に変わった**（2026年9月確認）。古い多項目の回答を控えていても使い回せない

## 3-3. ビルド選択後の追加入力を減らす設定【必須】

### プロジェクト側で自動化できるもの

通常のHTTPS通信とApple標準暗号化だけを使い、非免除暗号を含まないアプリは、`Info.plist`へ次を入れます。

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

これにより、条件を満たすアプリではアップロードごとの輸出コンプライアンス質問を省略できます。
独自暗号、VPN、暗号資産ウォレット等を実装した場合は`false`を流用せず、必ず個別確認します。

### App Store Connectで初回に設定して維持するもの

- 広告を含むアプリは、App Information > Age Ratingsの **AdvertisingをYes** にする
- 年齢制限は3行の質問票に答える。広告あり＝Advertising Yes、課金あり＝In-App Purchase Yes
- コンテンツを収録するアプリ（美術・書籍・画像）は、**収録物の年齢区分を提出前に実査する。**
  美術館では春画12点を外して12+で申告した。「None」で出して審査員に見つかると差し戻される
- 広告SDKを追加・削除したときは、App Privacyの回答とPrivacy Manifest（2-13）を再確認する
- Content Rights、カテゴリ、サポートURL、プライバシーポリシーURLを未回答のまま残さない
- 審査用連絡先と審査メモは、再利用できる値をアプリ情報へ保存する

### リリース方法の標準値

- 特別な指定がなければ **Automatically release this version（審査承認後に自動リリース）** を選ぶ
- 「指定日時以降に自動リリース」は選ばず、配信予定日時を入力不要にする
- 予約公開または手動公開が必要なときだけ、ユーザーへ確認して変更する
- 段階的リリースは、個別指定がない限りオフとする

リリース方法はApple側のバージョン項目なので、Info.plistだけで入力欄自体を消すことはできません。
App Store Connectを操作できる担当者またはエージェントが、ビルド選択と同時に上記標準値まで入力し、
ユーザーへ「ビルドを選択した後は残りを手入力してください」と丸投げしないでください。

## 3-4. 提出作業の完了条件【必須】

ビルドを選択しただけでは完了としません。次を確認し、可能な範囲は同じ作業内で入力します。

- 作業ブランチが `main` へマージ済み（2-10）
- ビルド選択済み
- 輸出コンプライアンスが自動判定済み、または必要な回答済み
- 年齢制限のAdvertisingが広告有無と一致
- App Privacyが使用SDKと `PrivacyInfo.xcprivacy` に一致
- リリース方法が「審査承認後に自動リリース」
- 審査メモ、連絡先、著作権、サポートURLに不足なし
- 「審査に追加」または「審査へ提出」直前まで必須項目エラーなし
- `App-Store-登録情報.md` に、提出したVersion／Build、審査対応の記録、公開後にやること（ストアURLの記入、app-ads.txt、noteへの告知など）を追記済み
- 配信開始後、ストアURLを原本とサポートページへ書く

## 3-5. リリースノートの書き方【推奨】

- **「ポリシー違反を修正した」とは書かない。** 利用者に意味のある変化だけを書く
- 事実と食い違う表現を避ける（審査担当も読む欄）
- 広告まわりの修正は、この定型でよい

```
・プライバシーに関する同意確認を追加しました
・同意の確認が完了するまで広告を読み込まないよう、表示処理を見直しました
・広告の読み込みが重複して行われることがある不具合を修正しました
・画面の切り替え時に広告が繰り返し読み込まれる問題を修正しました
```

## 3-6. 公開後のWeb・App Store同期【必須】

`yutaroulabs.com/data/apps.json` はWebサイトの `src/content/apps/*.md` を正本として自動生成済みである。
別のJSON台帳を手作業で増やさず、App Store公開後は次を一連の作業として行う。

1. App Storeで公開状態と正式なApp Store URLを確認する
2. `App-Store-登録情報.md` に公開日、Version、Build、App Store ID、正式URLを記録する
3. Webサイトの `src/content/apps/<slug>.md` にApp Store URL、公開状態、価格、広告、課金、Version、更新日を反映する
4. アプリ詳細、サポート、プライバシーポリシーの各URLが有効で、相互リンクが正しいことを確認する
5. `https://yutaroulabs.com/data/apps.json` に `published: true` で出力され、App Store URLが正規化されていることを確認する
6. 既存アプリのおすすめ欄に表示され、対象アプリ自身は除外されることを実機確認する
7. 公開アプリの詳細ページに `SoftwareApplication` 構造化データがあり、企画中・内容未完成ページは `noindex` のままであることを確認する
8. sitemapの対象・`lastmod`を確認し、新規URLはSearch Consoleへ送信する
9. App StoreのVersion・スクリーンショットを同期するGitHub Actionsが成功していることを確認する

- `apps.json`、Web一覧、クロスプロモーション用一覧を別々に二重管理しない
- App Storeで未公開、予約中、配信停止中のアプリを `published: true` にしない
- App Store IDが確定する前の仮URLを公開データへ残さない

---

# Part 4. アプリ種別ごとの仕様

## 4-1. 資格試験アプリ

既存9本：FP2級 / FP3級 / 基本情報技術者 / ITパスポート / 運転免許 / 宅建 / 危険物乙4種 / 美容師試験 / 簿記3級
（着手済み：簿記2級 / 衛生管理者 / 電気工事士2種 / 登録販売者）

### 2つの実装系統がある

| 系統 | 構成 | 該当 |
|---|---|---|
| **ネイティブ型** | SwiftUI で全画面を実装。問題データは Swift の構造体または JSON | FP2 / FP3 / 危険物乙4 / 簿記3級 |
| **WebView型** | 既存のPWA（`app.js` + `questions.js`）を `WKWebView` でラップ。Swiftファイルは3個程度 | 基本情報 / ITパスポート / 宅建 / 運転免許 / 美容師 |

**新規は原則ネイティブ型**。既にWeb版が存在する場合のみWebView型を検討する。

### 必須機能

- **四択問題**（分野別 + ランダム演習）
- **一問一答○×**（四択の全選択肢を自動で正誤問題に変換する方式が効率的）
- **本番形式の模擬試験**（実際の試験と同じ問題数・合格判定基準）
- **間隔反復**（間違えた問題を最適なタイミングで再出題）
- **学習プラン**（試験日から逆算して毎日のノルマを自動作成）
- **分野別の正答率表示**
- **全問に解説**

### 推奨機能

- 合格可能性メーター
- 誤答の原因分析（ケアレスミス / 知識不足 / 未学習）
- 直前対策モード
- 完全オフライン動作（**登録・ログイン不要は必須**）
- 試験固有の問題形式（簿記の仕訳問題など）は、四択とは別の画面・別のJSONにする

### 問題数の目安【参考】

- 簿記3級：510問（知識330問＋仕訳180問）。初版の630問から整理した
- 問題はJSON（`questions.json`、`shiwake.json` 等）に分け、`Tools/` に収録を増やすスクリプトを置く

### 広告の置き方

- バナーのみ。**演習中・模試中は非表示**
- インタースティシャルは入れない（「答え合わせ3回ごと」のような実装も禁止）
- リワードは「解説の追加表示」「広告なし1時間」など任意の価値と交換する場合のみ

### コンテンツ上の注意【必須】

- 問題文は**必ずオリジナル**。実際の試験問題を転載しない
- 出典が公的機関の場合は審査メモにその旨を明記する
- 他アプリと問題データを使い回さない（重複コンテンツとみなされるリスク）
- ベンダー資格（Salesforce等）は、受験時のNDAに抵触する実問題の再現を一切しない。
  アプリ名に商標を入れず、免責文を置く

---

## 4-2. 記録・管理アプリ

既存13本：血圧記録 / 本棚 / メシ / デグー / イヌ / ネコ / タロット / ガレージ / 不動産カルテ / 家事王 / 植物 / 家計簿 / 交換日記 など

### 必須機能

- **ワンタップ記録**（ホーム画面から最短1タップで記録が完了する）
- **一覧と詳細**
- **グラフまたは統計**（記録が溜まると意味が出る画面）
- SwiftData による永続化（交換日記のように CloudKit 同期を前提にする場合は Core Data + CloudKit も可）

### 推奨機能

- **ホーム画面ウィジェット**（2-16。アプリを開かずに記録できると価値が跳ね上がる）
- **家族・パートナーとの共有**（2-12 の世帯コード方式）
- 写真の添付（写真からの記録を入口の前面に出すと使われやすい）
- 共有Extension・ショートカットからの記録
- 通知によるリマインド
- CSV / PDF エクスポート
- 同じものの二度登録を防ぐ（本棚：同一ISBN、ガレージ：同一車両など）

### 広告の置き方

- 画面上部に常設バナー1枚
- 記録の入力中・編集中は非表示
- インタースティシャルは入れない

### 設計上のポイント

- **「今日の記録」がホームの主役**。過去の閲覧は二の次
- 入力項目は最小限から始め、詳細入力は別画面に逃がす
- 記録が0件のときの画面（空状態）を必ず設計する
- 読み込み失敗時にデータを消さない（本棚で発生した不具合）

---

## 4-3. ゲーム

既存4本：ソリティア / 麻雀ソリティア / スパイダーソリティア / Pinball
（着手済み：マインスイーパー（Flutter） / 四川省 / 2048 / ブロックパズル / ナンプレ）

### ファイル構成【推奨】

```
<AppName>/
  ContentView.swift
  GameViewModel.swift        … ゲーム進行の状態管理
  Game/                      … ルール・盤面ロジック（UIに依存させない。単体テスト対象）
  Views/
  Support/
    Ads.swift                … 広告（バナー＋インタースティシャル＋リワード）
    GameStore.swift          … 記録・統計の永続化
    BackgroundTheme.swift    … 背景テーマ
    SoundManager.swift
    HapticsManager.swift
```

### 必須機能

- **難易度選択**（初心者向け〜上級者向け）
- **デイリーチャレンジ**（その日の配置は全プレイヤー共通。連続クリア日数を記録し、記録表にも出す）
- **ヒント**
- **1手戻す**
- **中断保存**（アプリを閉じても続きから遊べる）
- **統計**（プレイ回数・クリア率・最短時間など）
- **必ずクリアできる配置**の保証（理不尽さを排除する。盤面ソルバーで検証する）

### 推奨機能

- 背景テーマの選択
- 効果音とハプティクス（設定でオフにできること）
- タップとドラッグの両対応
- 盤面ロジックの回帰テスト（2-14）

### 広告の置き方【最重要】

- **バナー**：盤面の外。**盤面との間に必ず区切り線を入れる**（誤タップ防止）
- **インタースティシャル**：Part 1-8 の条件を厳守。
  「スタート画面へ戻るとき」「完了3ゲーム以上」「前回から120秒以上」の3条件すべて
- **リワード**：ヒント追加・アンドゥ追加など、ユーザーが能動的に選ぶ場面でのみ

**ゲーム開始時に全画面広告を出す実装は、いかなる形でも禁止。**

---

## 4-4. 通知・ユーティリティアプリ

既存：うちの沿線速報 / うちのゴミ出し / うちの交通ナビ

「ユーザーが見ていないときに動いて、必要なときだけ知らせる」タイプ。
記録アプリと違い、**アプリを開かせないことが価値**になる。

### 必須機能

- **プッシュ通知またはローカル通知**が中核
- **通知のタイミングをユーザーが設定できる**（前日夜 / 当日朝 など）
- 通知内容が一目で判断できる（開かなくても用が足りる文面）
- 通知の再スケジュール処理

### 実装上の注意【必須】

- **iOSのローカル通知は64件までしか保持できない。**
  アプリ起動のたびに組み直して先の予定を継ぎ足す設計にする

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active { rescheduleNotifications() }
}
```

- バックグラウンド更新を使う場合、`background_fetch` 相当の仕組みを入れる
- 通知権限が拒否された場合の代替導線（アプリ内表示）を用意する
- 前面に戻ったときの鮮度確認は、15分に1回までのように回数を抑える

### 広告の置き方

- バナーのみ。**初期設定（オンボーディング）中は非表示**
- 通知から起動した直後は、目的の情報を最優先で見せる。広告で覆わない

### 設計上のポイント

- ホームは「次に起きること」を1つだけ大きく見せる
- 設定項目が多くなりがちなので、初期設定で最小限だけ聞き、残りは後から
- よく使う操作（定番区間など）は保存でき、App Entity として Siri から呼べるようにする（2-15）

---

## 4-5. 外部API連携ツール

既存：うちの不動産カルテ / うちの本棚（書誌API） / うちの美術館（美術館の公開API） / うちの交通ナビ（公開GTFS）

### 実装上の注意【必須】

- **APIキーをソースにハードコードしない。** 設定画面またはビルド設定から渡す。
  Google Books のようにキーを「iOSアプリ制限付き」にできるAPIは必ず制限をかける
- 無料枠のあるAPIは**呼び出し回数を抑える設計**にする（結果を端末にキャッシュ）
- API障害時に画面が壊れないこと。取得できなかった項目は「取得できません」と出す。偽のサンプル値を見せない
- 出典を必ず画面に明記する（例：国土交通省「不動産情報ライブラリ」、OpenStreetMap、国立国会図書館サーチ）
- 外部データを端末へ取り込んで完結する型（GTFS、美術館の収録データ）は、取り込み後はオフラインで動くようにし、
  取り込みスクリプトを `Tools/` に置く。収録を増やす後処理で見つかった不具合は記録する
- 取得元APIの仕様変更（楽天APIの2026年新仕様など）は原本に日付付きで記録する
- 他サービスの検討結果（採用しなかった理由）も `docs/` に残す

### 広告の置き方

- バナーのみ
- **読み込み失敗時の再試行は上限付きバックオフ。** 通信量が増えると審査でも不利

---

## 4-6. 新しいカテゴリを作るとき

既存4カテゴリに当てはまらないアプリを作る場合、以下で判断する。

**広告形式の選び方**

| 状況 | 使ってよい形式 |
|---|---|
| 常に画面が表示されている | バナー（上部固定1枚） |
| 明確な「区切り」が存在する（1ゲーム終了、1セッション完了） | インタースティシャル（Part 1-8の条件付き） |
| ユーザーが対価として選ぶ場面がある | リワード |
| 上のどれにも当てはまらない | **バナーのみ** |

**インタースティシャルを入れてよい条件（すべて満たす場合のみ）**

1. ユーザーの作業が明確に「完了」する瞬間がある
2. その瞬間に画面が切り替わることをユーザーが予期している
3. 表示しても作業内容が失われない
4. 回数と時間の両方で頻度を制限できる

1つでも欠けたら**バナーのみ**にする。迷ったらバナーのみ。

**既存アプリとの衝突**

うちの英会話（10/11時点）は、インタースティシャル・MREC・ネイティブ広告を実装し、ATTを出さず、Bundle ID が `jp.ohno.*` になっている。
本書と合わない点は、次のアップデートで本書に合わせる（インタースティシャルとネイティブの削除、ATT追加、`PrivacyInfo.xcprivacy` の `NSPrivacyTracking` を `true`）。
Bundle ID は変更しない。

---

## 4-7. 計測（Firebase Analytics）【推奨】

2026年10月に本棚・沿線速報・危険物乙4・タロットへ一斉導入した。共通設計の原本は `ANALYTICS_TEMPLATE.md`（共通設計 v2）。
先行の DeguCare / Ketsuatsu（v1）で見つかった不備を直してある。

### 構成【必須】

| 項目 | 値 |
|---|---|
| Firebase プロジェクト | `YutarouLabs Apps`（Project ID: `yutaroulabs-apps`）。全アプリを同じプロジェクトに登録し、Bundle ID ごとに分ける |
| SDK（SwiftUI） | `firebase-ios-sdk`（Exact Version で固定）、プロダクトは **`FirebaseAnalyticsCore` のみ** |
| SDK（Flutter） | `firebase_core` / `firebase_analytics`。Podfile に `$FirebaseAnalyticsWithoutAdIdSupport = true` |
| IDFA | 扱わない（`GoogleAppMeasurementIdentitySupport` を含めない） |
| ATT | 計測のために新しく出さない（広告用のATTはそのまま） |
| 設定ファイル | アプリごとに Firebase コンソールからダウンロードした `GoogleService-Info.plist`。**他アプリのものを流用しない**（Bundle ID が違うと計測を止める仕組みを入れる） |
| plist が無いとき | ビルドも起動もできる。Firebase を起動せず、計測だけ止まる |
| Debug ビルド | スキームの `-FIRDebugEnabled` にチェックしたときだけ送る（既定オフ）。Release は常に送る |
| Crashlytics | 入れる場合、plist 未配置でもビルドが通るようスクリプトにガードを入れる |

### 部品（各アプリに同じ内容のファイルを置く）

| ファイル | 役割 |
|---|---|
| `AnalyticsService.swift` | Firebase の起動と送信。イベント名の型、パラメータの切り詰め、共通イベント |
| `AnalyticsProgress.swift` | 「N回目に一度だけ」「一度だけ」、購入の重複防止。Foundation のみ・単体テストあり |
| `AnalyticsVisibility.swift` | 行が実際に画面に出たかの判定（`onBecameVisible`）、おすすめアプリ表示の重複抑止 |
| `AppAnalytics.swift` | アプリ固有のイベントとパラメータ |

### 共通ルール【必須】

- 「完了」系のイベントは、**永続化の成功を戻り値で確認してから**送る。`try? context.save()` のあとに無条件で送らない
- 編集・キャンセル・入力エラー・保存失敗では送らない
- `onAppear` / `task` からは送らない。ユーザー操作のハンドラから送る。連打の二重送信をガードする
- 「N回目」「初めて」は**通算カウンタ**で判定する（件数ベースは遡及発火と削除時のぶれが起きる）
- 個人データ（書名・感想・写真・記録の中身）は送らない
- `had_data_at_start` のような「計測開始時点の状態」をユーザープロパティで持つ

### 共通イベント名

| イベント | 送る時 |
|---|---|
| `main_action_complete` | そのアプリの主要操作が成功したとき（`action` にアプリ固有名） |
| `first_<action>_completed` / `second_<action>_completed` | 通算1回目・2回目。端末ごとに一度だけ |
| `onboarding_complete` | 初回案内があるアプリのみ |
| `purchase_started` / `purchase_completed` | 課金があるアプリのみ。`AnalyticsTransactionLedger` で重複防止 |
| `recommended_app_impression` / `recommended_app_click` | 4-8 のおすすめアプリ |

---

## 4-8. おすすめアプリ（シリーズ内クロスプロモ）【推奨】

設定画面に「YutarouLabs のほかのアプリ」を並べ、App Store へ送る。本棚・ネコ・デグーなどで実装済み。

- アプリ一覧は `apps.json`（ID＝`source_app` に使うスラッグ、表示名、App Store ID、アイコン）で持つ
- 行が**スクロール領域に半分以上入った**ときだけ `recommended_app_impression` を送る（重複抑止あり）
- 行を押して App Store を開く直前に `recommended_app_click` を送る
- パラメータ：`source_app`、`destination_app`、`placement`（`settings_recommendations`）、`campaign`（`yutaroulabs_cross_promo`）
- おすすめ欄は広告の No fill 時にも崩れない独立したUIにする（1-7）
- 自分自身は一覧から除く。未公開のアプリは載せない

## 4-9. 共通部品のバージョンと差分検査【必須】

Analytics・おすすめアプリ・課金・広告など、複数リポジトリへ同じ部品をコピーする場合に適用する。

- 共通部品または同梱READMEに `CommonComponentVersion` を記録する
- 原本は `ANALYTICS_TEMPLATE.md` 等の1か所に定め、各アプリ側で独自変更した箇所は理由をコメントまたは `docs/` に残す
- 共通テンプレート更新時は対象アプリ一覧を作り、適用済み・対象外・保留を記録する
- CIで、必要なファイル、イベント名、パラメータ名、設定キーが欠けていないか検査する
- Firebase使用時は `main_action_complete`、該当するmilestone、購入イベント、クロスプロモーションイベントの実装有無を検査する
- おすすめ欄を実装した場合は `recommended_app_impression` と `recommended_app_click` の両方を確認する。表示だけ、クリックだけの実装を残さない
- コピー間の差分が継続的に増える場合はSwift Package化または同期スクリプト化し、手作業コピーを続けない
- Firebase・広告・課金SDKのバージョン変更は1アプリで先行検証し、成功後に対象アプリへ段階展開する

---

# Part 5. 新規アプリ依頼時のテンプレート

新しいアプリを頼むときは、このファイルに加えて以下を渡してください。

```
## アプリ概要
- アプリ名（「うちの◯◯」形式）:
- 一言でいうと:
- 種別: 資格試験 / 記録・管理 / ゲーム / 通知・ユーティリティ / 外部API / その他
- 想定ユーザー:

## 中核機能（これがないと成立しない、を3つまで）
1.
2.
3.

## あったら良い機能
- ウィジェット: 要 / 不要
- 家族共有（世帯コード方式）: 要 / 不要
- Apple Intelligence / Siri: 要 / 不要
- 計測（Firebase Analytics）: 要 / 不要

## デザイン
- アプリアイコンのイメージ（色・モチーフ）:
- 主役色:

## 広告
- 形式: 広告なし / バナー / バナー＋インタースティシャル / バナー＋リワード / その他
- LevelPlay App Key:
- （使用時のみ）Banner Ad Unit ID:
- （使用時のみ）Interstitial Ad Unit ID:
- （使用時のみ）Rewarded Ad Unit ID:
- （インタースティシャル使用時）自然な区切りはどこか:
- （リワード使用時）報酬内容と付与条件:
- LevelPlay管理画面でironSource Ads／Unity Adsの対象形式を有効化済みか:
- 開発実機をTest devicesへ登録済みか:

## 課金
- 広告削除（adfree）: あり / なし（価格: ）
- 機能開放（premium）: あり / なし（価格: ）
- 有料機能と解放方式の一覧:

## データ
- オフライン完結か、外部APIを使うか:
- 使う場合のAPI名と出典表記:
- 共有するデータの範囲（「自分だけ」区分の有無）:

## 制約・注意点
-
```

---

# Part 6. 提出前チェックリスト

**このリストを全部埋めるまで App Store に提出しないこと。**

## 広告【必須】

- [ ] Unity LevelPlay SDKを導入し、対象ターゲットへリンクした
- [ ] Unity Ads SDKとLevelPlay Unity Ads Adapterが互換バージョンでリンクされている
- [ ] ironSource Ads／Unity AdsがLevelPlay管理画面で対象形式に対して有効である
- [ ] App Keyと使用するAd Unit IDが対象アプリの値である
- [ ] 未使用広告形式のオブジェクト・ロード処理・Ad Unit IDを追加していない
- [ ] 旧AdMob SDK、AdMob本番ID、不要なGAD設定が残っていない
- [ ] 同意→LevelPlayプライバシー設定→ATT→SDK初期化の順である
- [ ] **同意画面でどちらを選んでもATTが表示される**ことを実機で確認した（審査員が「しない」を押す前提）
- [ ] `NSUserTrackingUsageDescription`と`SKAdNetworkItems`を設定した
- [ ] 開発実機をLevelPlayのTest devicesへ登録し、対象ネットワーク・形式を選択した
- [ ] `setAdaptersDebug(true)`はDebugのみで、本番画面に診断表示がない
- [ ] 登録済み実機でテスト広告を確認し、広告をクリックしていない
- [ ] 画面を行き来してもバナーを多重生成・多重ロードしない
- [ ] 表示条件を満たさない間はバナーViewを生成していない
- [ ] （ゲーム）**開始時に全画面広告が出ない**ことを10回以上確認した
- [ ] オンボーディング中・演習中にバナーが出ない
- [ ] （資格系・記録系）インタースティシャルが入っていない
- [ ] リワード完了後の広告開放が1時間、視聴間隔も1時間で、延長が重ならない
- [ ] Rewardedは`didRewardAd`受信時だけ報酬を一度付与する
- [ ] No fill・通信失敗時も本体UIが壊れず、ユーザー向けエラーを出さない

## 課金【課金ありの場合は必須】

- [ ] 商品IDが `<BundleID>.adfree` / `.premium` で、App Store Connect の非消耗型と一致している
- [ ] `adfree` 購入後にバナー・全画面・ネイティブが一切出ない
- [ ] 「購入を復元」が設定画面に常設され、サンドボックスで購入・復元を実機確認した
- [ ] 購入状態がウィジェット・拡張と共有されている
- [ ] 有料Appの契約が有効で、価格が表示される
- [ ] 初回提出時はApp内課金をバージョンに紐づけた

## ビルド設定【必須】

- [ ] 作業ブランチを `main` へマージし、Archive元のコミットを原本に記録した
- [ ] Archive元コミットSHAが `main` から到達可能で、同じコードを再現できる
- [ ] `main` のPR必須チェック（build／test）が緑である
- [ ] 一時検証workflow・未マージの完成実装が作業ブランチだけに残っていない
- [ ] `CLAUDE.md`（この仕様書）がリポジトリ直下にある
- [ ] Info.plist にVersion／Buildを直書きしていない
- [ ] ネイティブiOSは`$(MARKETING_VERSION)`／`$(CURRENT_PROJECT_VERSION)`を使っている
- [ ] FlutterのiOS Archiveも`$(MARKETING_VERSION)`／`$(CURRENT_PROJECT_VERSION)`を使っている
- [ ] Flutterの`Generated.xcconfig`に残った古いVersion／BuildがArchiveへ優先されない
- [ ] `pubspec.yaml`のVersion／BuildをXcodeの設定値と同期した
- [ ] ウィジェット・拡張のバージョンが本体と一致している
- [ ] 拡張の `Info.plist` に必須キーが揃っている
- [ ] Build番号がApp Store Connectへアップロード済みの値と重複していない
- [ ] TeamがYutarou Nagano（`JS7SYSHC3S`）、署名がAutomaticである
- [ ] 本体・Widget・ExtensionのTeamと署名設定が一致している
- [ ] Deployment Target が 17.0
- [ ] Xcode 26 でビルドが通る
- [ ] `ITSAppUsesNonExemptEncryption`をアプリの暗号利用実態に合わせて設定した
- [ ] `PrivacyInfo.xcprivacy` があり、SDK構成と一致している
- [ ] 共通起動画面（3 imageset＋storyboard）が入り、`CFBundleDisplayName` が「うちの◯◯」である
- [ ] `.gitignore` を配置した
- [ ] 単体テストが通り、CI（`iOS build`）が緑である
- [ ] （FoundationModels使用時）iOS 17〜25 の端末・シミュレータで機能が隠れ、クラッシュしない
- [ ] （計測使用時）`GoogleService-Info.plist` が自アプリのもので、Debugで `-FIRDebugEnabled` なしに送信されない
- [ ] （共通部品使用時）原本のバージョンと一致し、必須イベント・設定キーの差分検査が通る
- [ ] （通知使用時）拒否状態、再設定、タイムゾーン変更、64件上限、通知タップ後の遷移を確認した
- [ ] （Widget使用時）空データ・未購入・写真あり・旧共有データで表示でき、メモリ超過しない
- [ ] （Live Activity使用時）二重開始せず、終了・強制終了・再起動後に残存しない
- [ ] （入出力使用時）CSV／PDF／JSONの正常系、重複取込、破損ファイル、旧schemaを確認した

## ストア【必須】

- [ ] プロモーション用テキストを新バージョンに入力し直した
- [ ] リリースノートが事実と一致している
- [ ] サポートURL・プライバシーポリシーURLが有効
- [ ] 広告ありアプリはAge RatingsのAdvertisingがYesである（3行質問票形式）
- [ ] コンテンツ収録アプリは収録物の年齢区分を実査し、申告と一致している
- [ ] App PrivacyがLevelPlay・ironSource Ads・Unity Ads（＋Firebase）を含む現行SDK構成と一致している
- [ ] 審査メモにATT・広告・課金・音声の確認手順を書いた
- [ ] リリース方法が「審査承認後に自動リリース」で、不要な配信予定日時を要求しない
- [ ] ビルド選択後の必須項目を入力し、提出直前までエラーがない
- [ ] 原本に提出記録と「公開後にやること」を追記した

## 公開後【必須】

- [ ] App Storeの公開状態、Version、Build、正式URLを確認した
- [ ] `App-Store-登録情報.md` に公開日、App Store ID、正式URLを記録した
- [ ] Webサイトの `src/content/apps/<slug>.md` を公開内容に合わせた
- [ ] アプリ詳細・サポート・プライバシーポリシーの各ページが有効である
- [ ] `/data/apps.json` に公開済みとして出力され、未公開アプリが混入していない
- [ ] 既存アプリのおすすめ欄で表示と自アプリ除外を確認した
- [ ] `SoftwareApplication` 構造化データ、sitemap、`lastmod`を確認した
- [ ] 新規URLをSearch Consoleへ送信した
- [ ] App Store情報の同期workflowが成功した

## 最後に

- [ ] **広告を絶対にクリックしていない**

---

# 付録. 2026年10月15日版の変更履歴

| 節 | 変更 | 根拠となったリポジトリ・出来事 |
|---|---|---|
| 冒頭 | 暫定3点（Flutter／起動画面／ダークモード）を明示 | mine-sweeper、kyoyuKakeibo、UchiNoNekoIOS |
| Part 0 | 審査差し戻しの記録表を追加 | uchinoBijutsukan 2026-09-22 |
| 1-1 | Xcode 26 必須を追記 | book（FIREBASE_ANALYTICS.md）、資格ノートCI |
| 1-2 | Native・MREC を個別指定なしでは実装しないと明記 | english |
| 1-5 | 選択に関わらずATTを要求、文言追加 | uchinoBijutsukan |
| 1-6 | ビルド構成で出し分けない前提、`docs/広告の動作確認手順.md` | UchiNoNekoIOS（課金の仕組み.md） |
| 1-7 | 条件未達時はバナーViewを生成しない | UchiNoNekoIOS |
| 1-9 | 視聴間隔1時間、延長を重ねない、`AdFreePolicy` | english |
| 1-12 | 新設：StoreKit 2 買い切り課金 | UchiNoNekoIOS、english、deguCareIOS、UchiInuIOS |
| 2-1 | Xcode 26、Firebase／CKShare 禁止、Flutter 2本 | 全体 |
| 2-2 | `CLAUDE.md`、`PrivacyInfo.xcprivacy`、`docs/`、Tests、CI、Bundle ID 小文字統一 | 全体 |
| 2-3 | アイコン差し替え時の配色取り直し、ダークモードの扱い | boki3、kyoyuKakeibo、koukannikki、UchiNoNekoIOS |
| 2-4 | `CFBundleDisplayName`、プライバシーポリシーURL | UchiNoNekoIOS、english |
| 2-6 | 環境変数名を `SCREENSHOT_MODE` に統一 | english（`-disableAds`） |
| 2-7 | XcodeGen は Team・Bundle ID も `project.yml` が正 | all-money-kanri、english、kyoyuKakeibo、norikaeannai |
| 2-10 | 新設：ブランチ運用と仕様書の配置 | 10リポジトリ中8本で main が初期コミットのみ |
| 2-11 | 新設：共通起動画面 | yutaroulabs-launch-screen-audit ブランチ（2026-09-07） |
| 2-12 | 新設：世帯コード方式の家族共有 | kyoyuKakeibo、UchiNoNekoIOS、deguCareIOS |
| 2-13 | 新設：Privacy Manifest の標準値 | english、norikaeannai、uchinoBijutsukan |
| 2-14 | 新設：テストとCI | norikaeannai、mine-sweeper、english |
| 2-15 | 新設：Apple Intelligence・App Intents | uchinoBijutsukan、norikaeannai、english |
| 2-16 | 新設：ウィジェット | english、kyoyuKakeibo、UchiNoNekoIOS |
| 2-16 | Widgetの写真縮小・Timeline・Live Activity制約を追加 | deguCareIOS、UchiInuIOS |
| 2-17 | 新設：リリース元ブランチとコミットの正本 | book、norikaeannai、kyoyuKakeiboほか |
| 2-18 | 新設：全カテゴリ共通の通知・リマインダー仕様 | ketsuatsu、kyoyuKakeibo、UchiNoNekoIOS、deguCareIOS、UchiInuIOS、gomi |
| 2-19 | 新設：CSV／PDF／JSONの入出力・バックアップ | ketsuatsu、kyoyuKakeibo、deguCareIOS |
| 3-1 | 審査メモの定型文 | english、uchinoBijutsukan |
| 3-2, 3-3 | 年齢制限の3行質問票、収録物の実査 | uchinoBijutsukan（2026-09-21、春画12点） |
| 3-4 | main マージ、原本への記録、公開後の作業 | uchinoBijutsukan |
| 3-6 | 新設：App Store公開後のWeb・apps.json・SEO同期 | yutaroulabs-website |
| 4-1 | 簿記3級追加、問題数の目安、仕訳形式、NDA | boki3、2026-08 チャット |
| 4-2 | ネコ・家計簿・交換日記追加、写真からの記録、二度登録防止 | kyoyuKakeibo、book |
| 4-3 | 着手済みゲーム、盤面ソルバー、デイリー記録表 | mine-sweeper |
| 4-4 | 交通ナビ、鮮度確認の間隔、Siri | norikaeannai |
| 4-5 | 取り込み型、APIキー制限、仕様変更の記録 | book、uchinoBijutsukan、norikaeannai |
| 4-6 | 英会話との衝突を明記 | english |
| 4-7 | 新設：計測（Firebase Analytics 共通設計 v2） | book（ANALYTICS_TEMPLATE.md） |
| 4-8 | 新設：おすすめアプリ | book、UchiNoNekoIOS |
| 4-9 | 新設：共通部品のバージョン管理と差分検査 | book、gomi、Firebase導入済み各アプリ |
| Part 5 | ウィジェット・共有・AI・計測・課金の欄を追加 | — |
| Part 6 | 課金セクション新設、ブランチ・CI・Manifest・起動画面・年齢区分の項目追加 | — |
