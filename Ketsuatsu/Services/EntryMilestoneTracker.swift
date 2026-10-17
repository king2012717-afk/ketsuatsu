import Foundation

/// 「アプリ内で保存に成功した記録の件数」を端末（インストール）単位で数え、
/// 3 件目に到達した瞬間を 1 回だけ判定する。
///
/// - 件数は保存に成功するたびに増やすだけで、削除しても減らさない。
///   そのため、削除して登録し直しても、再起動しても 3 件目の判定は二度と起きない。
/// - 数えるのは手入力・写真（1 枚／まとめて）で記録したもの。ヘルスケアからの取り込みは
///   `RecordService.create` を通らないため含めない。
/// - 値は UserDefaults に保存する。アプリを削除して入れ直すと記録と一緒に消えるため、
///   その端末では最初から数え直しになる。端末をまたいだ重複は（ログインがないため）判別できない。
struct EntryMilestoneTracker {
    static let thirdEntryThreshold = 3

    enum Key {
        static let migrated = "analytics.entryMilestone.migrated.v1"
        static let completedEntries = "analytics.entryMilestone.completedEntries.v1"
        /// Firebase 導入時の実装と同じキー。そちらで送信済みなら再送しない。
        static let thirdEntrySent = "analytics.blood_pressure.third_entry_sent"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completedEntries: Int { defaults.integer(forKey: Key.completedEntries) }
    var isThirdEntrySent: Bool { defaults.bool(forKey: Key.thirdEntrySent) }

    /// この仕組みを入れる前から使っている端末向けに、1 回だけ既存の記録件数を引き継ぐ（計測開始時点の基準値）。
    /// 起動してデータを開いた直後に呼ぶ。保存の直前にも念のため呼ぶ（引き継ぎ済みなら何もしない）。
    /// すでに 3 件以上ある場合は「到達済み」とし、イベントは送らない（4 件目以降の誤発火を防ぐ）。
    ///
    /// - Parameter existingEntryCount: ヘルスケアからの取り込みを除いた、保存済みの記録件数。
    ///   移行が済んでいる場合は呼ばれない。
    /// - Returns: 今回引き継いだ場合は、その時点の既存件数。すでに引き継ぎ済みなら nil。
    @discardableResult
    func migrateIfNeeded(existingEntryCount: () -> Int) -> Int? {
        guard !defaults.bool(forKey: Key.migrated) else { return nil }
        let existing = max(existingEntryCount(), 0)
        if existing > completedEntries {
            defaults.set(existing, forKey: Key.completedEntries)
        }
        if existing >= Self.thirdEntryThreshold {
            defaults.set(true, forKey: Key.thirdEntrySent)
        }
        defaults.set(true, forKey: Key.migrated)
        return existing
    }

    /// 保存に成功した件数を加え、今回の呼び出しで初めて 3 件目に到達した場合だけ true を返す。
    /// true が返ったら、呼び出し側で third_entry_completed を送る。
    func addCompletedEntries(_ count: Int = 1) -> Bool {
        guard count > 0 else { return false }
        let total = completedEntries + count
        defaults.set(total, forKey: Key.completedEntries)
        guard total >= Self.thirdEntryThreshold, !isThirdEntrySent else { return false }
        defaults.set(true, forKey: Key.thirdEntrySent)
        return true
    }
}
