# うちの血圧記録 — App Store 登録情報

ストアに入力する文面の原本は `store-listing.md` です。このファイルには、提出したバージョンの記録と、
審査・公開後にやることを残します（仕様書 2-10・2-17・3-4・3-6）。

---

## 基本情報

| 項目 | 値 |
|---|---|
| アプリ名 | うちの血圧記録 |
| Bundle ID | `com.example.Ketsuatsu`（リポジトリ上の値。App Store Connect の登録値と一致しているか要確認） |
| 販売元 | Yutarou Nagano |
| 著作権 | 2026 YutarouNagano |
| サポートURL | https://yutaroulabs.com/support/ketsuatsu/ |
| マーケティングURL | https://yutaroulabs.com |
| App Store ID | （公開後に記入） |
| App Store URL | （公開後に記入） |
| 価格 | 無料（広告あり・課金なし） |

---

## 提出記録

Archive は必ず `main` から作り、そのコミット SHA を記録します。記録した SHA は `main` から到達できなければなりません。

| Version | Build | Archive 元コミット（`main`） | 提出日 | 結果 |
|---|---|---|---|---|
| 1.0 | （未記録） | （未記録） | （未記録） | 公開済み |
| 1.2 | （未記録） | （未記録） | （未記録） | 配信中（2026年10月17日時点） |
| 1.3 | 1 | `37c9673` | （未提出） | App Store Connect で「NSUserTrackingUsageDescription があるのにトラッキングの申告がない」と止められた |
| 1.3 | 2 | `47b7e62` | 2026-10-17 | ITMS-91064（Invalid tracking information）で差し戻し |
| 1.3 | 3 | （提出時に記入） | （提出時に記入） | マニフェストを NSPrivacyTracking false・ドメインのキーなしに直したビルド |

---

## 審査対応の記録

| 日付 | Version | 指摘・対応 |
|---|---|---|
| 2026-10-17 | 1.3 (1) | 提出前の確認で「アプリに NSUserTrackingUsageDescription が含まれているのに、App のプライバシーでトラッキングに使用するデータがない」と表示された。広告に使う 3 項目（デバイス ID・広告データ・製品の操作）を「トラッキングに使用：はい」に変更し、PrivacyInfo.xcprivacy も合わせた（ビルド 2） |
| 2026-10-17 | 1.3 (2) | アップロード後、ITMS-91064「NSPrivacyTracking must be true if NSPrivacyTrackingDomains isn't empty」で差し戻し。原因はアプリのマニフェストが `NSPrivacyTracking` true でトラッキング先ドメインが空だったこと（広告 SDK のマニフェストはいずれもドメインを宣言していない）。`NSPrivacyTracking` を false にし、`NSPrivacyTrackingDomains` のキーを削除、各データの Tracking も false に戻した（ビルド 3）。App Store Connect の「トラッキングに使用：はい」はそのまま |

---

## 公開後にやること

- [ ] App Store の公開状態、Version、Build、正式な App Store URL を確認し、上の表に記入する
- [ ] Webサイト（`yutaroulabs-website`）の `src/content/apps/` の本アプリのページに、App Store URL・公開状態・Version・更新日を反映する
- [ ] サポートページとプライバシーポリシーのページが開け、相互リンクが正しいことを確認する
- [ ] `https://yutaroulabs.com/data/apps.json` に `published: true` で出力され、ほかのアプリのおすすめ欄に表示されることを確認する
- [ ] `docs/広告の動作確認手順.md` の「App Store 公開後にやること」（Unity の Store ID、LevelPlay の Live app 化）
- [ ] app-ads.txt の確認
