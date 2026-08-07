import Foundation

/// リマインダーの時刻 1 件。
struct ReminderTime: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int
    var slot: MeasurementSlot
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int = 0,
        slot: MeasurementSlot? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.slot = slot ?? MeasurementSlot.inferred(fromHour: hour)
        self.isEnabled = isEnabled
    }

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    /// 並べ替え用。0:00 からの分数。
    var minutesFromMidnight: Int { hour * 60 + minute }

    /// 新しい ID で複製する（曜日ごとにコピーするときに使う）。
    func duplicated() -> ReminderTime {
        ReminderTime(hour: hour, minute: minute, slot: slot, isEnabled: isEnabled)
    }
}

/// 何曜日の何時に通知するかをまとめたスケジュール。
///
/// - `uniform`: すべての曜日で同じ時刻に通知する（「1 日 3 回」のような設定）
/// - `perWeekday`: 曜日ごとに時刻を変える（平日は朝だけ、休日は朝昼晩、など）
struct ReminderSchedule: Codable, Equatable, Sendable {

    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case uniform
        case perWeekday

        var id: String { rawValue }

        var title: String {
            switch self {
            case .uniform: return "まとめて"
            case .perWeekday: return "曜日ごと"
            }
        }

        var footnote: String {
            switch self {
            case .uniform: return "設定した時刻に毎日通知します。"
            case .perWeekday: return "曜日ごとに通知する時刻を変えられます。"
            }
        }
    }

    var isEnabled: Bool
    var mode: Mode
    /// 「まとめて」のときに使う時刻。
    var uniformTimes: [ReminderTime]
    /// 「曜日ごと」のときに使う時刻。キーは `Calendar` の weekday（1 = 日曜 … 7 = 土曜）。
    var weekdayTimes: [Int: [ReminderTime]]

    init(
        isEnabled: Bool = true,
        mode: Mode = .uniform,
        uniformTimes: [ReminderTime] = ReminderPreset.threeTimesDaily.times,
        weekdayTimes: [Int: [ReminderTime]] = [:]
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.uniformTimes = uniformTimes
        self.weekdayTimes = weekdayTimes
    }

    /// 初期状態。朝・昼・晩の 1 日 3 回。
    static var standard: ReminderSchedule { ReminderSchedule() }

    static let allWeekdays = Array(1...7)
    static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    static func weekdayName(_ weekday: Int, short: Bool = true) -> String {
        let index = (weekday - 1) % 7
        guard index >= 0, index < weekdaySymbols.count else { return "" }
        return short ? weekdaySymbols[index] : "\(weekdaySymbols[index])曜日"
    }

    // MARK: - 参照

    /// 指定した曜日に通知する時刻（時刻順）。
    func times(for weekday: Int) -> [ReminderTime] {
        let times = mode == .uniform ? uniformTimes : (weekdayTimes[weekday] ?? [])
        return times.sorted { $0.minutesFromMidnight < $1.minutesFromMidnight }
    }

    /// 編集対象の時刻。`weekday` が nil なら「まとめて」の一覧。
    func times(forEditing weekday: Int?) -> [ReminderTime] {
        let times = weekday.map { weekdayTimes[$0] ?? [] } ?? uniformTimes
        return times.sorted { $0.minutesFromMidnight < $1.minutesFromMidnight }
    }

    /// 1 週間に鳴る回数。
    var weeklyCount: Int {
        Self.allWeekdays.reduce(0) { $0 + times(for: $1).filter(\.isEnabled).count }
    }

    /// 実際に iOS へ登録する通知の件数。
    /// 「まとめて」は毎日繰り返す通知 1 件で済むが、「曜日ごと」は曜日 × 時刻の数だけ必要になる。
    var notificationRequestCount: Int {
        switch mode {
        case .uniform:
            return uniformTimes.filter(\.isEnabled).count
        case .perWeekday:
            return weeklyCount
        }
    }

    var summaryText: String {
        guard isEnabled, weeklyCount > 0 else { return "オフ" }
        switch mode {
        case .uniform:
            return "毎日 \(uniformTimes.filter(\.isEnabled).count) 回"
        case .perWeekday:
            return "曜日ごと・週 \(weeklyCount) 回"
        }
    }

    /// 次に通知される日時。
    func nextTriggerDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            var components = calendar.dateComponents([.year, .month, .day], from: day)

            var candidates: [Date] = []
            for time in times(for: weekday) where time.isEnabled {
                components.hour = time.hour
                components.minute = time.minute
                components.second = 0
                if let candidate = calendar.date(from: components), candidate > date {
                    candidates.append(candidate)
                }
            }
            if let earliest = candidates.min() { return earliest }
        }
        return nil
    }

    // MARK: - 編集

    /// `weekday` が nil なら「まとめて」の一覧を編集する。
    mutating func addTime(_ time: ReminderTime, weekday: Int?) {
        if let weekday {
            weekdayTimes[weekday, default: []].append(time)
        } else {
            uniformTimes.append(time)
        }
    }

    mutating func updateTime(_ time: ReminderTime, weekday: Int?) {
        if let weekday {
            guard let index = weekdayTimes[weekday]?.firstIndex(where: { $0.id == time.id }) else { return }
            weekdayTimes[weekday]?[index] = time
        } else {
            guard let index = uniformTimes.firstIndex(where: { $0.id == time.id }) else { return }
            uniformTimes[index] = time
        }
    }

    mutating func removeTime(id: UUID, weekday: Int?) {
        if let weekday {
            weekdayTimes[weekday]?.removeAll { $0.id == id }
        } else {
            uniformTimes.removeAll { $0.id == id }
        }
    }

    mutating func setEnabled(_ isEnabled: Bool, timeID: UUID, weekday: Int?) {
        if let weekday {
            guard let index = weekdayTimes[weekday]?.firstIndex(where: { $0.id == timeID }) else { return }
            weekdayTimes[weekday]?[index].isEnabled = isEnabled
        } else {
            guard let index = uniformTimes.firstIndex(where: { $0.id == timeID }) else { return }
            uniformTimes[index].isEnabled = isEnabled
        }
    }

    /// 設定方法を切り替える。「まとめて」→「曜日ごと」のときは、いまの時刻を全曜日へ引き継ぐ。
    mutating func switchMode(to newMode: Mode) {
        guard newMode != mode else { return }
        switch newMode {
        case .perWeekday:
            if weekdayTimes.values.allSatisfy(\.isEmpty) {
                for weekday in Self.allWeekdays {
                    weekdayTimes[weekday] = uniformTimes.map { $0.duplicated() }
                }
            }
        case .uniform:
            // 曜日ごとの設定はそのまま残しておき、戻したときに復元できるようにする。
            break
        }
        mode = newMode
    }

    /// ある曜日の時刻を、他の曜日へコピーする。
    mutating func copyTimes(from weekday: Int, to targets: [Int]) {
        let source = weekdayTimes[weekday] ?? []
        for target in targets where target != weekday {
            weekdayTimes[target] = source.map { $0.duplicated() }
        }
    }

    /// かんたん設定を適用する。「曜日ごと」のときは全曜日に同じ内容を入れる。
    mutating func apply(_ preset: ReminderPreset) {
        switch mode {
        case .uniform:
            uniformTimes = preset.times
        case .perWeekday:
            for weekday in Self.allWeekdays {
                weekdayTimes[weekday] = preset.times
            }
        }
    }

    /// 「時刻を追加」で提案する時刻。まだ使っていない時間帯を順に埋める。
    func suggestedNewTime(for weekday: Int?) -> ReminderTime {
        let existing = times(forEditing: weekday)
        let usedSlots = Set(existing.map(\.slot))
        let candidates = [ReminderTime(hour: 7), ReminderTime(hour: 13), ReminderTime(hour: 21)]
        if let unused = candidates.first(where: { !usedSlots.contains($0.slot) }) {
            return unused
        }
        // すべて埋まっている場合は最後の時刻の 1 時間後。
        let hour = ((existing.last?.hour ?? 11) + 1) % 24
        return ReminderTime(hour: hour)
    }
}

/// よく使う組み合わせ。
enum ReminderPreset: String, CaseIterable, Identifiable, Sendable {
    case twiceDaily
    case threeTimesDaily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twiceDaily: return "1 日 2 回（朝・晩）"
        case .threeTimesDaily: return "1 日 3 回（朝・昼・晩）"
        }
    }

    var detail: String {
        times.map(\.timeText).joined(separator: " / ")
    }

    /// 呼ぶたびに新しい ID の時刻を返す。
    var times: [ReminderTime] {
        switch self {
        case .twiceDaily:
            return [
                ReminderTime(hour: 7, slot: .morning),
                ReminderTime(hour: 21, slot: .evening)
            ]
        case .threeTimesDaily:
            return [
                ReminderTime(hour: 7, slot: .morning),
                ReminderTime(hour: 13, slot: .noon),
                ReminderTime(hour: 21, slot: .evening)
            ]
        }
    }
}
