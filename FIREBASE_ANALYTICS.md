# Firebase Analytics

YutarouLabs の計測共通設計 v2（`yutaroulabs-spec` の `templates/ANALYTICS_TEMPLATE.md`、仕様書 4-7・4-8）に合わせている。
v2 の共通部品（`AnalyticsProgress.swift` など）の実物は `book` リポジトリにあり、このアプリでは同じ規則を独自に実装している（下表）。

| v2 の部品 | このアプリ |
| --- | --- |
| `AnalyticsService.swift` | `Ketsuatsu/Services/AnalyticsService.swift`（起動・送信・共通イベント） |
| `AnalyticsProgress.swift` | `Ketsuatsu/Services/EntryMilestoneTracker.swift`（通算カウンタ・基準値） |
| `AnalyticsVisibility.swift` | `Ketsuatsu/Support/AnalyticsVisibility.swift` と `ImpressionTracker.swift`（半分以上の表示・重複抑止） |
| `AppAnalytics.swift` | `Ketsuatsu/Services/AppAnalytics.swift`（このアプリ固有のイベント） |

## 構成

| 項目 | 値 |
| --- | --- |
| Firebase プロジェクト | `YutarouLabs Apps`（`yutaroulabs-apps`） |
| Apple バンドル ID（Firebase 登録・コード上） | `com.example.Ketsuatsu` |
| SDK | Firebase Apple SDK `12.19.2`（`exactVersion` で固定） |
| プロダクト | `FirebaseAnalyticsCore`（IDFA を収集しない版。`FirebaseAnalyticsIdentitySupport` は入れない） |
| 初期化 | `KetsuatsuApp.init()` → `AnalyticsService.configure()`（LevelPlay の起動より前） |
| 設定ファイル | `Ketsuatsu/GoogleService-Info.plist`。**公開リポジトリのため Git には含めない**（`.gitignore`。仕様書 2-9）。Firebase コンソールからダウンロードして置く（同期フォルダのためアプリターゲットに自動で含まれる） |
| plist が無い・Bundle ID が違う | Firebase を起動せず、計測だけ止まる（ビルド・起動はできる）。Xcode のコンソールに `[Analytics]` で理由を出す |
| Debug ビルド | スキームの起動引数 `-FIRDebugEnabled` を付けたときだけ送る（既定は送らない）。Release は常に送る |

> **バンドル ID の確認**: App Store Connect に登録済みの本番バンドル ID が `com.example.Ketsuatsu` と違う場合、
> アプリのバンドル ID は**変更せず**、Firebase コンソールで本番のバンドル ID の iOS アプリを追加し、
> その `GoogleService-Info.plist` に差し替えること。食い違ったままだと起動時に不一致の警告が出て、
> 計測が正しく紐付かない。

計測のために ATT・AdSupport・IDFA は使わない（ATT は広告のためだけに出している。仕様書 1-5）。`first_open` は Firebase の自動収集イベントのため、アプリからは送らない。

## 送らない情報

血圧値・脈拍・服薬の有無・メモ・写真・測定日時・ヘルスケアのデータ、およびそれらから計算した値（期間内の件数、平均、判定区分など）は**イベントにもパラメータにも入れない**。
パラメータは「どの操作方法で行ったか」、まとめて記録の件数、写真の読み取りが保存された値と合っていたかの区分（後述）だけに限る。ユーザー ID は設定しない。
ユーザープロパティは `had_data_at_start`（計測を始めた時点で記録があったか。`true` / `false`）だけを設定する。既存ユーザーを分析から分けるために使う。

## イベント一覧

| イベント | 送るタイミング | パラメータ | 重複の防ぎ方 |
| --- | --- | --- | --- |
| `first_open` | 初回起動（Firebase が自動で送る） | なし | Firebase 側 |
| `blood_pressure_entry_started` | 記録を始める操作をしたとき（「手で入力する」「手入力」を押した／写真を選び終えた） | `entry_method` | ボタン操作のハンドラから送る。画面の表示（`onAppear`）では送らない。編集では送らない |
| `blood_pressure_entry_completed` | `context.save()` が成功した直後 | `entry_method`、まとめて記録のみ `record_count` | 保存に失敗したら送らない。まとめて記録は 1 回の操作で 1 回 |
| `main_action_complete` | `blood_pressure_entry_completed` と同時 | `action = blood_pressure_entry` | 同上 |
| `photo_reading_saved` | 写真から読み取った記録の `context.save()` が成功した直後（写真 1 枚ごと） | `entry_method`（`photo` / `photo_batch`）`read_result` `bp_match` `pulse_match` `reader` `confidence` | 保存に失敗したら送らない。編集では送らない。手入力では送らない |
| `third_entry_completed` | アプリ内で保存に成功した記録が累計 3 件に達したとき | なし | 端末内の累計件数と送信済みフラグ（後述）。1 インストールにつき最大 1 回 |
| `weekly_summary_viewed` | グラフの期間のチップで「1週間」を選んだとき | なし | 切り替えの操作 1 回につき 1 回。画面の表示・タブの再訪・再描画では送らない |
| `recommended_app_impression` | 設定タブの「YutarouLabsのおすすめ」の各行の **半分以上** が画面に入ったとき | `source_app`（`ketsuatsu-record`）`destination_app` `placement` `campaign` | 同じ行はアプリが前面にいる間 1 回まで。背面に回ったら数え直す |
| `recommended_app_click` | おすすめの行をタップして App Store を開くとき | 同上 | タップごと（クリックは操作の回数そのものを数える） |

### entry_method の値

| 値 | 記録方法 | started を送る操作 |
| --- | --- | --- |
| `manual` | 手入力 | ホームの「手入力」、または ＋ メニューの「手で入力する」を押したとき |
| `photo` | 写真 1 枚（撮影・ライブラリ） | 写真を 1 枚撮影・選択し終えたとき |
| `photo_batch` | 写真をまとめて記録 | 写真を 2 枚以上選び終えたとき |

**計測単位**: started と completed はどちらも「1 回の記録操作（画面）」単位でそろえている。

- `manual` / `photo` は 1 操作 = 1 件。
- `photo_batch` は 1 操作 = N 件。completed は 1 回だけ送り、保存できた件数を `record_count` に入れる。
- したがって「記録の完了率」は `completed ÷ started` を `entry_method` ごとに見れば、どの方法でも同じ意味になる。
- 「記録された件数」を見たいときは、`photo_batch` だけ `record_count` を合計し、それ以外はイベント数を数える。
- キャンセルで閉じた場合は started だけが残る（completed は送らない）。
- カメラ／写真選択を途中でやめた（写真を選ばなかった）ときは started を送らない。
- 写真を選んだあとに読み取り自体が失敗したときは、started だけが残る。「やり直す」で選び直すと、もう一度 started が送られる。

### photo_reading_saved（読み取り精度の計測）

「写真の読み取りが、実際に保存された値と合っていたか」を数える。読み取った値を手で直してから保存した割合が分かる。
**送るのは下表の区分の名前だけ**で、血圧・脈拍の値、写真、読み取った文字は送らない（`Ketsuatsu/Services/OCR/PhotoReadingOutcome.swift`）。

| パラメータ | 値 | 意味 |
| --- | --- | --- |
| `entry_method` | `photo` / `photo_batch` | 写真 1 枚か、まとめて記録か |
| `read_result` | `full` / `bp_only` / `partial` / `none` | 読み取れた項目（上・下・脈拍／上・下だけ／一部だけ／何も読めず） |
| `bp_match` | `true` / `false` | 読み取った上・下が、どちらもそのまま保存されたか。上・下を読めなかったときは `false` |
| `pulse_match` | `true` / `false` / `not_read` | 読み取った脈拍がそのまま保存されたか。`not_read` は脈拍を読めなかった（そのあと手で入れたかどうかは区別しない。脈拍を記録したかどうかを送らないため） |
| `reader` | `shape` / `text` | 採用した読み方。`shape` は液晶の数字の形から（`SegmentDisplayReader`）、`text` は文字認識（Vision）から |
| `confidence` | `high` / `low` | 確度が 0.85 以上か（未満のときは画面に「値が正しいか確認してください」を出している） |

見方：

- **読み取りの正解率** ＝ `bp_match = true` の件数 ÷ `photo_reading_saved` の件数。`reader` で分ければ、どちらの読み方が当たっているかが分かる
- **確度の付け方が妥当か** ＝ `confidence = high` の中の `bp_match = false` の割合（高いのに外れている）が小さいこと
- **読めなかった割合** ＝ `read_result = none` または `partial` の割合
- まとめて記録は、保存した写真 1 枚ごとに 1 回送る（`blood_pressure_entry_completed` は 1 回の操作で 1 回のまま）

**範囲の限界**：

- 保存された記録だけが対象。読み取り結果を見てキャンセルした・まとめて記録でチェックを外した写真は数えない（`blood_pressure_entry_started(photo)` と `completed(photo)` の差には表れる）
- 値を直さずに保存した場合を「合っていた」と数える。誤りに気づかず保存した分は正解に入る
- どの機種で外れたかは分からない（機種名や写真は送らない）

### weekly_summary_viewed の条件

- 期間のチップで、別の期間から「1週間」に切り替えたときに 1 回送る（期間はチップの操作でしか変わらない）
- グラフタブを開いただけ・別タブから戻っただけでは送らない（仕様書 4-7：`onAppear` からは送らない）
- 「1週間」のまま記録を追加したり、画面が再描画されたりしても送らない

### main_action_complete の使い方

YutarouLabs の各アプリで「主要な操作を終えた」ことを同じ名前で数え、**アプリ横断で比較する**ための共通イベント。

- 本アプリでは `blood_pressure_entry_completed` と必ず同時に 1 回送る（`action = blood_pressure_entry`）。
- **個別イベントと足し合わせない**。両方を合計すると記録の完了が 2 倍に数えられる。
- アプリ内の分析には `blood_pressure_entry_completed`、アプリ横断の比較には `main_action_complete` のどちらか一方だけを使う。
- 複数アプリをまとめて見るときは `app_id`（Firebase のアプリ）か `action` で絞り込む。

## third_entry_completed の判定方法

`Ketsuatsu/Services/EntryMilestoneTracker.swift` が UserDefaults に次の値を持つ。

| キー | 内容 |
| --- | --- |
| `analytics.entryMilestone.completedEntries.v1` | アプリ内で保存に成功した記録の累計件数（削除しても減らさない） |
| `analytics.blood_pressure.third_entry_sent` | 送信済みフラグ（Firebase 導入時の実装と同じキー） |
| `analytics.entryMilestone.migrated.v1` | 既存データからの引き継ぎが済んだか |

1. **引き継ぎ（計測開始時点の基準値。1 回だけ）**: アップデート後の初回起動で、データを開いた直後に、ヘルスケアからの取り込みを除いた保存済みの件数を数える。
   このときユーザープロパティ `had_data_at_start` を設定する（1 件以上なら `true`）。起動時に済んでいなければ、最初の保存の直前に行う。
   - 3 件以上 → 「到達済み」として送信済みフラグを立てる。**イベントは送らない**（既存ユーザーの 4 件目以降で誤って送られるのを防ぐ）
   - 1〜2 件 → その件数から数え始める
   - 0 件 → 0 から数える
2. **保存に成功するたび**に累計へ加え、3 件以上かつ未送信なら 1 回だけ送ってフラグを立てる。まとめて記録で 3 件をまたいだ場合も 1 回だけ。
3. 削除しても累計は減らさないので、削除→登録し直し、再起動、アップデートでは再送しない。

**数える対象**: 手入力・写真 1 枚・まとめて記録で、アプリ内から保存したもの。
**数えない対象**: ヘルスケアからの取り込み（ユーザー自身の記録操作ではないため。`RecordService.create` を通らない）、編集（新しい記録ではないため）。

**範囲の限界**（ログインがないため）:

- 判定は**端末（インストール）単位**。同じ人が別の iPhone で使うと、その端末でも 1 回送られうる。
- アプリを削除して入れ直すと、記録と一緒に累計も消えるため、その端末では最初から数え直す（Firebase 側も新しいインストールとして扱う）。
- iCloud バックアップから復元した場合は、記録と累計が一緒に戻るので再送しない。
- 保存に失敗した記録が、あとで SwiftData の自動保存によって保存されても数えない（まれなケースで、少なめに数える側に倒している）。

## 実装しないイベント

- `onboarding_complete`: 本アプリにはオンボーディング画面がない。起動画面や別の画面に結び付けると意味の違うデータになるため送らない。オンボーディングを導入したときに、その完了時に追加する。
- 課金系（`purchase` など）: アプリ内課金・サブスクリプションがないため送らない。

## 保存失敗時の動き（画面・ヘルスケアへの影響）

- `context.save()` が失敗したときは、「保存できませんでした」と知らせてから記録画面を閉じる（まとめて記録は、保存できなかった件数を出す）。記録はコンテキストに残って一覧に表示されるが、アプリを終了すると消えることがある。
- 永続ストア自体を開けなかったときは、通常の画面の代わりに「記録を開けませんでした」を出し、記録の入力をさせない（`DataStore`）。このときは計測開始時点の基準値（`had_data_at_start`）も記録しない。
- ヘルスケアへの書き出しも従来どおり行う（一覧に表示されている内容とヘルスケアをそろえるため）。
- 分析イベントは送らない。

## DebugView での確認

1. Xcode で `Ketsuatsu.xcodeproj` を開き、File → Packages → Resolve Package Versions で Swift Package を解決する。
   解決後、`Package.resolved` に `firebase-ios-sdk` などが追加されるので、その差分をコミットする（現在のファイルには Firebase の固定がない）。
2. Scheme → Edit Scheme → Run → Arguments に `-FIRDebugEnabled` を追加してチェックを入れる。**Debug ビルドはこれが無いと何も送らない**。
3. シミュレータまたは実機で起動し、Firebase Console → Analytics → DebugView を開く。
4. 下の表の操作をして、イベントとパラメータを確かめる。
5. 終わったら `-FIRDebugEnabled` を外す（必要なら一度 `-FIRDebugDisabled` で起動する）。

| # | 操作 | 期待するイベント |
| --- | --- | --- |
| 1 | アプリを削除して入れ直し、起動 | `first_open` |
| 2 | 手入力 → 保存 | `blood_pressure_entry_started`(manual) → `blood_pressure_entry_completed`(manual) + `main_action_complete` |
| 3 | 手入力 → キャンセル | `blood_pressure_entry_started`(manual) のみ |
| 4 | 履歴から記録を開いて編集 → 保存 | なし |
| 5 | 写真 1 枚 → 読み取り結果 → そのまま保存 | started(photo) → `photo_reading_saved`(photo, bp_match=true) → completed(photo) + `main_action_complete` |
| 5b | 写真 1 枚 → 読み取り結果 → 上か下の値を直して保存 | 5 と同じで、`photo_reading_saved` の `bp_match` が `false` |
| 6 | 写真を 3 枚まとめて → 2 枚だけ選んで保存 | started(photo_batch) → `photo_reading_saved`(photo_batch) を 2 回 → completed(photo_batch, record_count=2) + `main_action_complete` を各 1 回 |
| 7 | 新規インストールで 3 件目を保存 | 3 件目の completed のあとに `third_entry_completed` を 1 回 |
| 8 | 4 件目を保存／1 件削除して保存し直す／再起動して保存 | `third_entry_completed` は出ない |
| 9 | 旧バージョン（Firebase 導入前）で 3 件以上記録 → 本バージョンに上書き → 記録 | `third_entry_completed` は出ない |
| 10 | グラフタブ → 「1週間」を選ぶ → 別タブ → グラフタブに戻る → 「1か月」→「1週間」 | `weekly_summary_viewed` が 2 回（チップで選んだ 2 回だけ） |
| 11 | 設定タブを開き、おすすめが半分以上見えるまでスクロール → 上下にスクロールを繰り返す | 半分以上見えた行ごとに `recommended_app_impression` が 1 回ずつ（`source_app` = `ketsuatsu-record`） |
| 11b | 11 のあとホーム画面に戻り、もう一度アプリを開く（設定タブのまま） | 見えている行の `recommended_app_impression` が改めて 1 回ずつ |
| 14 | `-FIRDebugEnabled` を外して Debug ビルドを起動し、記録する | 何も送られない（コンソールに `[Analytics] Debug ビルドのため送信しません`） |
| 15 | 旧バージョンで記録がある端末を上書き更新して起動 | ユーザープロパティ `had_data_at_start` = `true` |
| 12 | おすすめの行をタップ | `recommended_app_click`（App Store が開く） |
| 13 | 保存失敗（`RecordService.insert` の `try context.save()` の直前に一時的に `throw` を入れるなどして再現） | started のみ。completed・`third_entry_completed` は出ない |

イベントのパラメータに血圧値・脈拍・メモなどが含まれていないことも、DebugView で合わせて確認する。

## 単体テスト

Xcode で ⌘U。

- `KetsuatsuTests/EntryMilestoneTrackerTests.swift`：新規インストール・再起動・削除と再登録・既存ユーザーの引き継ぎ・まとめて記録の判定、基準値
- `KetsuatsuTests/ImpressionTrackerTests.swift`：半分以上の表示、スクロールで戻ったとき、背面から戻ったときの数え直し
- `KetsuatsuTests/PhotoReadingOutcomeTests.swift`：読み取りと保存された値の突き合わせ、パラメータに値が入らないこと

## 横展開

共通部分は `AnalyticsService.swift`、アプリ固有のイベントは `AppAnalytics.swift` に分けている。`sourceApp` は `YutarouAppsConfig.currentAppID`（apps.json の ID）から取る。
主要な操作が**永続保存に成功した後だけ** `main_action_complete` と固有イベントを送る。

`third_entry_completed` は、Firebase 導入時の依頼で決めたイベント名をそのまま使っている。共通イベント名（`first_<action>_completed` / `second_<action>_completed`）とは別の節目である。
