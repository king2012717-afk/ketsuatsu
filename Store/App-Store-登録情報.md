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
| 1.3 | 1 | （提出時に記入） | （提出時に記入） | |

---

## 審査対応の記録

| 日付 | Version | 指摘・対応 |
|---|---|---|
| | | |

---

## 公開後にやること

- [ ] App Store の公開状態、Version、Build、正式な App Store URL を確認し、上の表に記入する
- [ ] Webサイト（`yutaroulabs-website`）の `src/content/apps/` の本アプリのページに、App Store URL・公開状態・Version・更新日を反映する
- [ ] サポートページとプライバシーポリシーのページが開け、相互リンクが正しいことを確認する
- [ ] `https://yutaroulabs.com/data/apps.json` に `published: true` で出力され、ほかのアプリのおすすめ欄に表示されることを確認する
- [ ] `docs/広告の動作確認手順.md` の「App Store 公開後にやること」（Unity の Store ID、LevelPlay の Live app 化）
- [ ] app-ads.txt の確認
