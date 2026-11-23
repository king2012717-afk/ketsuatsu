import Observation
import SwiftData

/// 記録の保存先（SwiftData のストア）を開き、開けたかどうかを持つ。
///
/// ストアを開けないとき（移行の失敗・空き容量の不足・ファイルの破損など）に、黙ってメモリ上のストアで
/// 動かすと、記録が保存できたように見えて終了時にすべて消える。既存の記録も 0 件に見える。
/// そのため、開けなかったときは `isPersistent` を false にし、アプリ側で「記録を開けない」画面だけを出して
/// 記録の入力・計測の送信をさせない（仕様書 4-2・4-7）。**既存のストアのファイルは消さない。**
@MainActor
@Observable
final class DataStore {
    /// 画面に渡すコンテナ。`isPersistent` が false のときは、空のメモリ上のコンテナ
    /// （画面を組み立てるためだけのもので、記録には使わせない）。
    private(set) var container: ModelContainer
    /// 永続ストアを開けたか。
    private(set) var isPersistent: Bool
    /// 開けなかった理由（問い合わせのときに伝えてもらうための表示用）。
    private(set) var failureDescription: String?

    private let open: () throws -> ModelContainer

    /// - Parameter open: 永続ストアを開く処理（テストで失敗を再現するために差し替えられる）。
    init(open: @escaping () throws -> ModelContainer = { try ModelContainer(for: BPRecord.self) }) {
        self.open = open
        let opened: ModelContainer?
        let failure: String?
        do {
            opened = try open()
            failure = nil
        } catch {
            opened = nil
            failure = error.localizedDescription
        }
        container = opened ?? Self.placeholderContainer()
        isPersistent = opened != nil
        failureDescription = failure
    }

    /// もう一度開いてみる（空き容量を空けたあとなど）。開けたら通常の画面に戻る。
    func retry() {
        guard !isPersistent else { return }
        do {
            container = try open()
            isPersistent = true
            failureDescription = nil
        } catch {
            failureDescription = error.localizedDescription
        }
    }

    private static func placeholderContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: BPRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("データベースを初期化できませんでした: \(error)")
        }
    }
}
