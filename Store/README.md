# 提出チェックリスト

上から順に進めてください。**★ が付いている項目は、こちらでは代われないので必ず作業が必要です。**

## 1. Xcode 側の設定

### ★ 1-1. Bundle ID を自分のものに変える

現在は `com.example.Ketsuatsu` という仮の値です。このままでは提出できません。

1. [Apple Developer](https://developer.apple.com/account/resources/identifiers/list) で Identifier を登録
   （例: `jp.あなたのドメイン.ketsuatsu`。持っているドメインを逆順にするのが慣例です）
2. Capability に **HealthKit** を追加
3. Xcode → プロジェクト → TARGETS「Ketsuatsu」→ Signing & Capabilities → Bundle Identifier を登録した値に変更

### ★ 1-2. 署名（Signing）

同じ画面で **Team** に自分の Apple Developer アカウントを選びます。
「Automatically manage signing」を有効にしておけば、プロビジョニングは自動で作られます。

### 1-3. 設定済みの項目（変更不要）

| 項目 | 値 | 場所 |
| --- | --- | --- |
| 表示名 | うちの血圧記録 | `Config/Info.plist` |
| バージョン | 1.0 | `MARKETING_VERSION` |
| ビルド番号 | 1 | `CURRENT_PROJECT_VERSION` |
| 対応端末 | iPhone のみ | `TARGETED_DEVICE_FAMILY = 1` |
| 最低 iOS | 17.0 | `IPHONEOS_DEPLOYMENT_TARGET` |
| カテゴリ | 健康＆フィットネス | `LSApplicationCategoryType` |
| 暗号化の申告 | 使用しない | `ITSAppUsesNonExemptEncryption` |
| プライバシーマニフェスト | 収集なし・UserDefaults の理由申告済み | `Ketsuatsu/PrivacyInfo.xcprivacy` |
| アプリアイコン | 通常・ダーク・色合いの 3 種 | `Ketsuatsu/Assets.xcassets/AppIcon.appiconset` |

> iPad にも対応させたい場合は `TARGETED_DEVICE_FAMILY` を `"1,2"` に戻してください。ただし iPad 用のスクリーンショットと動作確認が別途必要になります。

## 2. ★ プライバシーポリシーとサポートページの公開

App Store Connect では **プライバシーポリシー URL とサポート URL が必須**です。HealthKit を使うアプリは特にプライバシーポリシーが厳しく見られます。

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
2. サンプルの記録をいくつか入れる
3. 撮りたい画面で `⌘S`（File → Save Screen Shot）→ デスクトップに 1320 × 2868 の PNG が保存されます
4. その 6 枚をそのままアップロードする

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

- [ ] Bundle ID を自分のものに変えた
- [ ] Team を選び、署名が通っている
- [ ] プライバシーポリシー URL とサポート URL が実際に開ける
- [ ] スクリーンショット 6 枚をアップロードした
- [ ] App のプライバシー →「データを収集していません」を選んだ
- [ ] 年齢指定を回答した（医療／治療情報: まれ／軽度 → 12+）
- [ ] 審査メモに HealthKit とカメラの用途、動作確認手順を書いた
- [ ] 血圧計の写真を審査用に添付した
- [ ] 実機で一通り動作を確認した（記録・写真読み取り・通知・ヘルスケア・CSV）

## 審査で指摘されやすい点

このアプリで特に注意が必要なのは次の 3 点です。

1. **HealthKit の用途説明が足りない** … 審査メモとプライバシーポリシーの両方に、読み書きの目的と「広告に使わない」旨を明記しています。
2. **医療的な断定を避ける** … 判定区分の表示はガイドラインの分類にもとづく参考情報であり、診断ではありません。アプリ内・説明文の両方に医療機器ではない旨を記載しています。
3. **写真読み取りが試せない** … シミュレータではカメラが使えないため、審査用に血圧計の写真を添付し、写真ライブラリから試せることをメモに書いています。
