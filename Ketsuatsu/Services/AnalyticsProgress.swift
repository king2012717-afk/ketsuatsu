import Foundation

// YutarouLabs 共通の「一度だけ」「N回目」の判定（共通設計 v2）。Foundation だけに依存し、単体テストできる。
// このファイルはアプリ間で同じ内容にしておく。
//
// 先行アプリの初期版は「保存後に件数を数えて N 件以上なら送る」だったため、
//   - 計測を入れる前から N 件以上あった既存ユーザーにも、次の保存で「N回目」が送られる（遡及発火）
//   - 削除して件数が N 未満に戻ると、また同じ判定を通る
// という問題があった。ここでは「計測開始時点の件数」を基準値として一度だけ記録し、
// そこから成功した新規分だけを数える。削除しても数は減らない。

/// 生涯で N 回目に到達した瞬間を、それぞれ一度だけ知らせる端末内の永続カウンタ。
///
/// - 計測開始時点（このバージョンを初めて起動したとき）の既存件数を基準値にする。
///   基準値の時点ですでに超えている節目は「到達済み」として扱い、送らない。
/// - `unit` を渡すと、直近に数えた単位と同じものは数えない（例: 同じ日の引き直し、同じ本の再登録）。
/// - 保存はすべて UserDefaults。アプリを削除すると消えるため、保証は端末・インストール単位まで。
final class AnalyticsProgress: @unchecked Sendable {

    private struct State: Codable, Equatable {
        var baseline: Int
        var count: Int
        var reached: [Int]
        var recentUnits: [String]
        var startedAt: Date
    }

    let name: String
    let milestones: [Int]
    private let defaults: UserDefaults
    private let lock = NSLock()
    /// 同じ単位の判定に使う履歴の長さ。節目の判定に必要な分だけ残す。
    private let unitMemory: Int

    init(name: String, milestones: [Int], unitMemory: Int = 20, defaults: UserDefaults = .standard) {
        self.name = name
        self.milestones = milestones.sorted()
        self.unitMemory = unitMemory
        self.defaults = defaults
    }

    private var storageKey: String { "analytics.progress.\(name)" }

    /// 計測開始時点の既存件数を一度だけ記録する。2回目以降は何もしない。
    /// - Parameters:
    ///   - existingCount: すでに保存されている件数（日数・冊数など、数える単位で）。
    ///   - existingUnits: すでに数えた扱いにする単位（例: 今日すでに引いていれば今日の日付）。
    /// - Returns: このとき初めて基準値を記録したら true。
    @discardableResult
    func establishBaseline(existingCount: Int, existingUnits: [String] = []) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard load() == nil else { return false }
        let baseline = max(0, existingCount)
        save(State(
            baseline: baseline,
            count: baseline,
            reached: milestones.filter { $0 <= baseline },
            recentUnits: Array(existingUnits.suffix(unitMemory)),
            startedAt: Date()
        ))
        return true
    }

    /// `recordSuccess` の結果。
    struct Outcome: Equatable {
        /// 通算に数えたか（同じ単位の繰り返しなら false）。
        let counted: Bool
        /// このとき新たに到達した節目（各節目は生涯で一度だけ入る）。
        let reached: [Int]
    }

    /// 新規の保存に成功したときだけ呼ぶ。
    /// - Parameters:
    ///   - unit: 同じものを二重に数えないための識別子。端末内にだけ保存し、送信はしない。
    ///   - totalAfterSave: 基準値が未記録だったときの保険。保存後の総数を渡す（この1件を除いた数を基準値にする）。
    func recordSuccess(unit: String? = nil, totalAfterSave: Int) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        var state = load() ?? State(
            baseline: max(0, totalAfterSave - 1),
            count: max(0, totalAfterSave - 1),
            reached: milestones.filter { $0 <= max(0, totalAfterSave - 1) },
            recentUnits: [],
            startedAt: Date()
        )

        if let unit {
            if state.recentUnits.contains(unit) {
                save(state)
                return Outcome(counted: false, reached: [])
            }
            state.recentUnits.append(unit)
            if state.recentUnits.count > unitMemory {
                state.recentUnits.removeFirst(state.recentUnits.count - unitMemory)
            }
        }

        state.count += 1
        let newlyReached = milestones.filter { $0 <= state.count && !state.reached.contains($0) }
        state.reached.append(contentsOf: newlyReached)
        save(state)
        return Outcome(counted: true, reached: newlyReached)
    }

    /// 計測開始時点ですでにデータがあったか（基準値が 1 以上か）。未記録なら nil。
    var hadExistingData: Bool? {
        lock.lock(); defer { lock.unlock() }
        return load().map { $0.baseline > 0 }
    }

    /// 現在の通算件数（基準値を含む）。未記録なら nil。
    var count: Int? {
        lock.lock(); defer { lock.unlock() }
        return load()?.count
    }

    private func load() -> State? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

/// 端末で一度だけ行うことの記録（例: onboarding_complete）。
enum AnalyticsOnce {

    /// まだ行っていなければ `action` を実行して true を返す。2回目以降は何もしない。
    @discardableResult
    static func perform(_ name: String, defaults: UserDefaults = .standard, _ action: () -> Void) -> Bool {
        let key = "analytics.once.\(name)"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        action()
        return true
    }

    /// 送らずに「済み」にだけする（既存ユーザーが計測前に完了していた場合など）。
    static func markDone(_ name: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: "analytics.once.\(name)")
    }

    static func isDone(_ name: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "analytics.once.\(name)")
    }
}

/// 購入完了を同じ取引で二重に送らないための記録。取引 ID は端末内にだけ保存する。
enum AnalyticsTransactionLedger {

    private static let key = "analytics.purchase.reportedTransactions"
    private static let memory = 100

    /// まだ送っていない取引なら記録して true を返す。
    static func claim(_ transactionID: String, defaults: UserDefaults = .standard) -> Bool {
        var ids = defaults.stringArray(forKey: key) ?? []
        guard !ids.contains(transactionID) else { return false }
        ids.append(transactionID)
        if ids.count > memory { ids.removeFirst(ids.count - memory) }
        defaults.set(ids, forKey: key)
        return true
    }
}
