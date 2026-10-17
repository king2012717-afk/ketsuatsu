# 提出チェックリスト

上から順に進めてください。**★ が付いている項目は、こちらでは代われないので必ず作業が必要です。**

YutarouLabs 共通の提出前チェックリストは `docs/YutarouLabs-アプリ開発仕様書.md` の Part 6 です。このファイルは、そのうち本アプリ固有の手順をまとめたものです。

## 1. Xcode 側の設定

### ★ 1-1. Bundle ID の確認

リポジトリ上の値は `com.example.Ketsuatsu` です。App Store Connect に登録済みの本番の値と一致しているか確認してください。

- **登録済みの Bundle ID は変更しない**（仕様書 2-8）。署名エラーを避けるために変えることもしない
- 手元の Xcode でだけ本番の値に書き換えている場合は、その値をコミットして、`main` から同じ Archive を作れるようにする（仕様書 2-17）
- Capability に **HealthKit** が付いていることを確認する

### 1-2. 署名（Signing）

Team は Yutarou Nagano（`JS7SYSHC3S`）、署名は Automatic に設定済みです（仕様書 2-8）。

### 1-3. 設定済みの項目（変更不要）

| 項目 | 値 | 場所 |
| --- | --- | --- |
| 表示名 | うちの血圧記録 | `Config/Info.plist` |
| バージョン | 1.0.1（Firebase Analytics 導入の更新） | `MARKETING_VERSION` |
| ビルド番号 | 2 | `CURRENT_PROJECT_VERSION` |
| 対応端末 | iPhone のみ | `TARGETED_DEVICE_FAMILY = 1` |
| 最低 iOS | 17.0 | `IPHONEOS_DEPLOYMENT_TARGET` |
| カテゴリ | 健康＆フィットネス | `LSApplicationCategoryType` |
| 暗号化の申告 | 使用しない | `ITSAppUsesNonExemptEncryption` |
| プライバシーマニフェスト | アプリ自身の収集なし（SDK 分は各 SDK のマニフェスト）・UserDefaults の理由申告済み | `Ketsuatsu/PrivacyInfo.xcprivacy` |
| アプリアイコン | 通常・ダーク・色合いの 3 種 | `Ketsuatsu/Assets.xcassets/AppIcon.appiconset` |

> **バージョンの上げ方**: App Store Connect に出ている最新版より大きい番号にします。不具合修正や内部の変更は 3 桁目（1.0.1 → 1.0.2）、目に見える機能追加は 2 桁目（1.0 → 1.1）を上げ、ビルド番号はアップロードのたびに 1 ずつ増やします。同じバージョンでビルドを上げ直す場合も、ビルド番号は必ず増やしてください。

> iPad にも対応させたい場合は `TARGETED_DEVICE_FAMILY` を `"1,2"` に戻してください。ただし iPad 用のスクリーンショットと動作確認が別途必要になります。

### 1-4. 広告（Unity LevelPlay）について

画面上部にバナー広告を表示します。初回起動時に同意画面と ATT を表示し、終わってから広告 SDK を起動します（仕様書 1-5）。

| 項目 | 値 |
| --- | --- |
| App Key | `Info.plist` の `LevelPlayAppKey` |
| バナーの広告ユニット ID | `Info.plist` の `LevelPlayBannerAdUnitID` |
| SDK | Unity LevelPlay（`LevelPlay-Swift-Package`）＋ Unity Ads アダプタ（Swift Package） |
| 同意と ATT | `Ketsuatsu/Services/Ads/PrivacyConsentManager.swift`、画面は `Ketsuatsu/Views/Ads/AdConsentView.swift` |

> **⚠️ Debug ビルドでも本番の広告ユニットにリクエストが飛びます。** ビルド構成で広告を出し分けていません（仕様書 1-6）。
> 動作確認は、LevelPlay 管理画面の **Test devices** に登録した端末でだけ行い、表示された広告には絶対に触れないでください。
> 手順は `docs/広告の動作確認手順.md` を参照してください。

初回ビルド時、Xcode が Swift Package を取得します（数分かかります）。取得に失敗する場合は
File → Packages → Resolve Package Versions を実行してください。

#### ★ Unity LevelPlay 側で必要な作業

- Unity LevelPlay の管理画面で、このアプリを **App Store 公開後に「アプリを検索して追加」で紐付ける**（公開前は「手動で追加」のままで構いません）
- 広告が表示されるまで、新規アプリでは数時間〜1 日ほどかかることがあります
- 支払い情報を登録していないと収益が支払われません

### 1-5. アクセス解析（Firebase Analytics）について

イベントの一覧・送るタイミング・重複の防ぎ方・DebugView での確認手順は、リポジトリ直下の `FIREBASE_ANALYTICS.md` にまとめています。

> **`GoogleService-Info.plist` は Git に含めていません**（公開リポジトリのため。仕様書 2-9）。
> Firebase コンソール → プロジェクト `YutarouLabs Apps` → このアプリ → `GoogleService-Info.plist` をダウンロードし、`Ketsuatsu/` に置いてください。
> 置かなくてもビルド・起動はできますが、計測は止まります。

#### ★ 1.0.1 の提出前に必要な作業

1. **バンドル ID の一致確認**: App Store Connect に登録済みの本番バンドル ID と、プロジェクトの `PRODUCT_BUNDLE_IDENTIFIER`、`Ketsuatsu/GoogleService-Info.plist` の `BUNDLE_ID`（現在はいずれも `com.example.Ketsuatsu`）が同じか確認する。
   本番が違う値の場合は、**アプリのバンドル ID は変えず**、Firebase コンソールで本番のバンドル ID の iOS アプリを追加して、その `GoogleService-Info.plist` に差し替える。
2. **Swift Package の解決**: Xcode で File → Packages → Resolve Package Versions を実行し、`Package.resolved` に追加された `firebase-ios-sdk`（12.19.2）などの固定をコミットする。
3. **ビルドとテスト**: ⌘B でビルド、⌘U でテスト（`EntryMilestoneTrackerTests` を含む）。LevelPlay と一緒にリンクして警告・エラーが出ないことを確認する。
4. **DebugView**: `FIREBASE_ANALYTICS.md` の確認表どおりにイベントが出ることを確認する。
5. **App のプライバシー**: `store-listing.md` の表に合わせて「おおよその位置情報（アナリティクス）」を追加し、Firebase の案内と照合する。
6. **プライバシーポリシー**: 更新した `privacy-policy.md`（6. アクセス解析について）を公開ページに反映する。

## 2. ★ プライバシーポリシーとサポートページの公開

App Store Connect では **プライバシーポリシー URL とサポート URL が必須**です。HealthKit を使うアプリは特にプライバシーポリシーが厳しく見られます。

YutarouLabs のアプリは `yutaroulabs.com` に公開します（仕様書 2-4）。サポートは `https://yutaroulabs.com/support/ketsuatsu/`、プライバシーポリシーも `yutaroulabs.com` 配下です。原本はこのフォルダの `privacy-policy.md` と `support.md` です。

以下の GitHub Pages の手順は、`yutaroulabs.com` で公開できないときの予備です。

このリポジトリの GitHub Pages で公開するのが手軽です。

1. `Store/privacy-policy.md` と `Store/support.md` の末尾にある `<ご連絡先メールアドレスを記入してください>` を実際のアドレスに書き換える
2. GitHub のリポジトリ → Settings → Pages → Source を `main` ブランチ、フォルダを `/ (root)` に設定
3. 数分後に次の URL で公開されます

```
https://<ユーザー名>.github.io/ketsuatsu/Store/privacy-policy
https://<ユーザー名>.github.io/ketsuatsu/Store/support
```

> リポジトリが Private の場合、GitHub Pages は公開できないプランがあります。その場合はメモ系サービスの公開ページなど、誰でも見られる URL であれば何でも構いません。

## 3. App Store Connect の登録

[App Store Connect](https://appstoreconnect.apple.com) → マイ App → ＋ → 新規 App

- プラットフォーム: iOS
- 名前: `うちの血圧記録`
- プライマリ言語: 日本語
- バンドル ID: 1-1 で登録したもの
- SKU: 任意の文字列（例: `ketsuatsu-1`）

作成後、`store-listing.md` の内容を各欄に貼り付けてください。

## 4. スクリーンショット

`Store/screenshots/` の 6 枚（1290 × 2796）を、iPhone 6.9 インチの枠にアップロードします。

### ★ 実機の画面に差し替える（推奨）

同梱の画像は実装から起こした再現図です。App Store の審査では「実際のアプリの画面であること」が求められるため、**実機かシミュレータで撮った画面に差し替えてください。**

もっとも簡単な方法:

1. Xcode のシミュレータで **iPhone 16 Pro Max**（6.9 インチ）を選んでアプリを実行
2. **Mac を機内モードにする**か Wi-Fi を切る（広告が読み込まれず、上部が空欄になります）
3. サンプルの記録をいくつか入れる
4. 撮りたい画面で `⌘S`（File → Save Screen Shot）→ デスクトップに 1320 × 2868 の PNG が保存されます
5. その 6 枚をそのままアップロードする

> **広告が写った画面はアップロードしないでください。** 審査ガイドライン 2.3.10 で、スクリーンショットに第三者の広告を含めることは認められていません。

見出し付きのデザインのまま中身だけ差し替えたい場合は、撮った画像を `Store/raw/01.png` 〜 `06.png` として置き、次を実行してください。

```sh
pip3 install playwright pillow
playwright install chromium
python3 Store/generate_screenshots.py
```

`Store/screenshots/` が実機の画面で作り直されます。

## 5. ★ 審査用の添付ファイル

App 審査に関する情報の「添付ファイル」に、**血圧計の表示が写った写真を 1 枚**添付してください。審査担当者がシミュレータで読み取り機能を試せるようにするためです（シミュレータではカメラが使えないため）。

## 6. ビルドのアップロード

```
Xcode → Product → Destination → Any iOS Device (arm64)
Xcode → Product → Archive
Organizer → Distribute App → App Store Connect → Upload
```

アップロード後、App Store Connect で処理が終わるまで 10〜30 分ほどかかります。処理が終わったらビルドをバージョンに紐付けます。

## 7. 提出前の最終確認

共通の項目は仕様書 Part 6 をすべて埋めてください。本アプリで特に確認すること：

- [ ] 作業ブランチを `main` へマージし、Archive 元のコミットを `App-Store-登録情報.md` に記録した（仕様書 2-10・2-17）
- [ ] CI（`iOS build`）が緑である
- [ ] Bundle ID が App Store Connect に登録済みの値と一致している（変更はしない）
- [ ] Build 番号がアップロード済みの値と重複していない
- [ ] 同意画面で **どちらを選んでも ATT が表示される** ことを実機で確認した（アプリを削除して入れ直して 2 回試す）
- [ ] 同意と ATT が終わるまでバナーが出ず、広告のリクエストも出ていない
- [ ] 開発実機を LevelPlay の Test devices に登録し、テスト広告だけが出ることを確認した。**広告をクリックしていない**
- [ ] プライバシーポリシー URL とサポート URL が実際に開ける
- [ ] スクリーンショット 6 枚をアップロードした（広告と同意画面が写っていない）
- [ ] App のプライバシーを `store-listing.md` の表（＝ `PrivacyInfo.xcprivacy`）に合わせた。「データを収集していません」は選ばない
- [ ] 年齢指定を3行の質問票で回答した（広告: はい）
- [ ] 本番のバンドル ID と `GoogleService-Info.plist` の `BUNDLE_ID` が一致している
- [ ] `Package.resolved` に Firebase の固定が入った状態でコミットした
- [ ] DebugView で `FIREBASE_ANALYTICS.md` の確認表どおりにイベントが出た（健康情報がパラメータに含まれていない）
- [ ] 更新したプライバシーポリシーを公開した
- [ ] 審査メモに HealthKit とカメラの用途、広告と ATT、動作確認手順を書いた
- [ ] 血圧計の写真を審査用に添付した
- [ ] 実機で一通り動作を確認した（記録・写真読み取り・通知・ヘルスケア・CSV）
- [ ] プロモーション用テキストを新しいバージョンに入力し直した（新バージョンを作ると空になる）
- [ ] リリース方法を「審査承認後に自動リリース」にした

## 審査で指摘されやすい点

このアプリで特に注意が必要なのは次の 3 点です。

1. **HealthKit の用途説明が足りない** … 審査メモとプライバシーポリシーの両方に、読み書きの目的と「広告に使わない」旨を明記しています。
2. **医療的な断定を避ける** … 判定区分の表示はガイドラインの分類にもとづく参考情報であり、診断ではありません。アプリ内・説明文の両方に医療機器ではない旨を記載しています。
3. **写真読み取りが試せない** … シミュレータではカメラが使えないため、審査用に血圧計の写真を添付し、写真ライブラリから試せることをメモに書いています。
