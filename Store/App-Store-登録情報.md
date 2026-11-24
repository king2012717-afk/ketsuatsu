# うちの血圧記録 — App Store 登録情報

ストアに入力する文面の原本は `store-listing.md` です。このファイルには、提出したバージョンの記録と、
審査・公開後にやることを残します（仕様書 2-10・2-17・3-4・3-6）。

---

## 基本情報

| 項目 | 値 |
|---|---|
| アプリ名 | うちの血圧記録 |
| Bundle ID | `com.example.Ketsuatsu`（App Store Connect の登録値と一致。2026-11-21 運営データで確認。登録済みのため変更しない） |
| 販売元 | Yutarou Nagano |
| 著作権 | 2026 YutarouNagano |
| サポートURL | https://yutaroulabs.com/support/ketsuatsu/ |
| マーケティングURL | https://yutaroulabs.com |
| App Store ID | 6799039547 |
| App Store URL | https://apps.apple.com/jp/app/id6799039547 |
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
| 1.4 | 1 | `038fa5d`（提出時点の `main` の HEAD。**Archive した Mac の `git log --oneline -1` で要確認**。Build も同じく要確認） | 2026-11-24 | 審査待ち。評価のお願い（記録5件の保存後）、サブタイトル・キーワード・1枚目のスクリーンショットを変更。写真の読み取りを改善（液晶の数字を形から読む `SegmentDisplayReader`。斜めから撮った写真にも対応）。読み取りが合っていたかの計測（`photo_reading_saved`）。品質監査の指摘 8 件に対応（#7）。マニフェストを仕様書 2-13 の標準値に（デバイス ID・広告データの Tracking を true） |
| 1.3 | 3 | `923ccda`（推定：2026-11-21 時点で Mac の作業コピーが未変更のままこのコミットだった） | （未記録） | マニフェストを NSPrivacyTracking false・ドメインのキーなしに直したビルド。2026-10-19 に配信開始（App Store のバージョン履歴で確認） |

---

## 審査対応の記録

| 日付 | Version | 指摘・対応 |
|---|---|---|
| 2026-10-17 | 1.3 (1) | 提出前の確認で「アプリに NSUserTrackingUsageDescription が含まれているのに、App のプライバシーでトラッキングに使用するデータがない」と表示された。広告に使う 3 項目（デバイス ID・広告データ・製品の操作）を「トラッキングに使用：はい」に変更し、PrivacyInfo.xcprivacy も合わせた（ビルド 2） |
| 2026-10-17 | 1.3 (2) | アップロード後、ITMS-91064「NSPrivacyTracking must be true if NSPrivacyTrackingDomains isn't empty」で差し戻し。原因はアプリのマニフェストが `NSPrivacyTracking` true でトラッキング先ドメインが空だったこと（広告 SDK のマニフェストはいずれもドメインを宣言していない）。`NSPrivacyTracking` を false にし、`NSPrivacyTrackingDomains` のキーを削除、各データの Tracking も false に戻した（ビルド 3）。App Store Connect の「トラッキングに使用：はい」はそのまま |

---

## 1.4 の提出で確認すること（2026-11-24 提出）

提出は本人が行った。次の項目は、こちら（リポジトリ）からは確かめられないため、済んだらチェックを入れる。

- [ ] Archive 元のコミットと Build を、上の表の 1.4 の行で確定する（「要確認」を消す）
- [ ] App Store Connect の「App のプライバシー」：「製品の操作」の「トラッキングに使用」を「いいえ」にした（デバイス ID・広告データは「はい」。仕様書 1-5）
- [ ] 公開しているプライバシーポリシーのページに、読み取り精度の集計の 1 行と最終更新日（2026年11月23日）を反映した（原本は `privacy-policy.md`）
- [ ] ヨーロッパ 42 地域の除外を `eu_guard.py --check` で確認した（ON=0・OFF=42・不明=0。仕様書 3-7）
- [ ] 開発端末を LevelPlay の Test devices に登録し、`docs/広告の動作確認手順.md` の「テストデバイス」欄に記入した
- [ ] アップロードの検証（ITMS-91064 など）で差し戻しが無かった。マニフェストの Tracking を変えた最初の版のため、差し戻しがあれば「審査対応の記録」に書く（マニフェストだけ戻すならコミット `aaf843b` を戻す）

## 公開後にやること

- [ ] App Store の公開状態、Version、Build、正式な App Store URL を確認し、上の表に記入する
- [ ] Webサイト（`yutaroulabs-website`）の `src/content/apps/` の本アプリのページに、App Store URL・公開状態・Version・更新日を反映する
- [ ] サポートページとプライバシーポリシーのページが開け、相互リンクが正しいことを確認する
- [ ] `https://yutaroulabs.com/data/apps.json` に `published: true` で出力され、ほかのアプリのおすすめ欄に表示されることを確認する
- [ ] `docs/広告の動作確認手順.md` の「App Store 公開後にやること」（Unity の Store ID、LevelPlay の Live app 化）
- [ ] app-ads.txt の確認
