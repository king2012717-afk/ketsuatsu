# Firebase Analytics

## 構成

- Firebase project: `YutarouLabs Apps` (`yutaroulabs-apps`)
- Apple bundle ID: `com.example.Ketsuatsu`
- SDK: Firebase Apple SDK `12.19.2`
- Product: `FirebaseAnalyticsCore`（IDFA 収集機能なし）

## DebugView

1. Xcode で `Ketsuatsu.xcodeproj` を開き、Swift Package の解決を完了する。
2. Scheme の Run > Arguments に `-FIRDebugEnabled` を追加する。
3. シミュレータまたは実機でアプリを起動し、記録開始、記録保存、1週間表示、おすすめアプリ表示・タップを操作する。
4. Firebase Console > Analytics > DebugView でイベントとパラメータを確認する。
5. 検証後は `-FIRDebugEnabled` を外す。必要なら一度 `-FIRDebugDisabled` で起動する。

`first_open` は Firebase 標準イベントのためアプリ側から送信しない。ATT、AdSupport、IDFA は追加しない。

## 横展開

`Ketsuatsu/Services/AnalyticsService.swift` を共通テンプレートとして使う。アプリごとに `sourceApp` を変更し、主要行動の成功後だけ `main_action_complete` と固有イベントを送る。
