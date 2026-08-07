import Foundation
import Observation
import UserNotifications

/// 通知スケジュールの保存と、iOS への通知登録を担当する。
@MainActor
@Observable
final class ReminderStore {
    private static let storageKey = "reminderSchedule.v2"
    private static let legacyStorageKey = "reminders.v1"
    private static let notificationPrefix = "bp-reminder"

    /// iOS が保持できる保留中の通知はアプリごとに 64 件。他の用途の余地も残して上限を決めている。
    static let notificationLimit = 60

    private(set) var schedule: ReminderSchedule
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        self.schedule = Self.load(from: defaults)
    }

    var nextReminderDate: Date? { schedule.nextTriggerDate() }

    /// 通知の登録件数が上限を超えているか（超えた分は登録されない）。
    var exceedsNotificationLimit: Bool {
        schedule.isEnabled && schedule.notificationRequestCount > Self.notificationLimit
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - 編集

    /// スケジュールを書き換え、保存と通知の登録し直しまで行う。
    func modify(_ transform: (inout ReminderSchedule) -> Void) {
        var updated = schedule
        transform(&updated)
        guard updated != schedule else { return }
        schedule = updated
        persist()
        Task { await synchronize() }
    }

    /// 初回起動時に既定のスケジュール（朝・昼・晩の 1 日 3 回）を用意する。
    func installDefaultsIfNeeded() async {
        guard defaults.object(forKey: Self.storageKey) == nil else { return }
        persist()
        await synchronize()
    }

    // MARK: - 通知の許可

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        if granted { await synchronize() }
        return granted
    }

    // MARK: - 通知スケジュール

    /// 登録済みの通知をすべて作り直す。
    func synchronize() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.notificationPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        for request in Self.makeRequests(for: schedule) {
            try? await center.add(request)
        }
    }

    /// スケジュールから通知リクエストを組み立てる（純粋な変換なのでどこからでも呼べる）。
    ///
    /// 「まとめて」は曜日を指定しない毎日の繰り返し通知にまとめ、
    /// 「曜日ごと」は曜日 × 時刻ぶんの繰り返し通知を作る。
    nonisolated static func makeRequests(
        for schedule: ReminderSchedule,
        limit: Int = notificationLimit
    ) -> [UNNotificationRequest] {
        guard schedule.isEnabled else { return [] }

        /// 上限で切るときの優先順位。1 日のうち早い時刻から残す。
        var entries: [(priority: Int, request: UNNotificationRequest)] = []

        switch schedule.mode {
        case .uniform:
            for time in schedule.times(forEditing: nil) where time.isEnabled {
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                entries.append((
                    time.minutesFromMidnight,
                    makeRequest(
                        identifier: "\(notificationPrefix).\(time.id.uuidString)",
                        time: time,
                        components: components
                    )
                ))
            }

        case .perWeekday:
            for weekday in ReminderSchedule.allWeekdays {
                for time in schedule.times(for: weekday) where time.isEnabled {
                    var components = DateComponents()
                    components.weekday = weekday
                    components.hour = time.hour
                    components.minute = time.minute
                    entries.append((
                        time.minutesFromMidnight * 10 + weekday,
                        makeRequest(
                            identifier: "\(notificationPrefix).\(weekday).\(time.id.uuidString)",
                            time: time,
                            components: components
                        )
                    ))
                }
            }
        }

        guard entries.count > limit else { return entries.map(\.request) }
        // どの曜日も朝の通知が残るように、曜日単位ではなく時刻順で切る。
        return entries
            .sorted { $0.priority < $1.priority }
            .prefix(limit)
            .map(\.request)
    }

    private nonisolated static func makeRequest(
        identifier: String,
        time: ReminderTime,
        components: DateComponents
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "血圧を測る時間です"
        content.body = "\(time.slot.title)の血圧を記録しましょう。"
        content.sound = .default

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
    }

    // MARK: - 永続化

    private func persist() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> ReminderSchedule {
        if let data = defaults.data(forKey: storageKey),
           let schedule = try? JSONDecoder().decode(ReminderSchedule.self, from: data) {
            return schedule
        }
        if let migrated = migrateLegacySchedule(from: defaults) {
            return migrated
        }
        return .standard
    }

    /// 旧バージョン（時刻＋曜日の一覧）で保存された設定を、新しいスケジュールへ変換する。
    private static func migrateLegacySchedule(from defaults: UserDefaults) -> ReminderSchedule? {
        struct LegacyReminder: Codable {
            var hour: Int
            var minute: Int
            var weekdays: Set<Int>
            var slot: MeasurementSlot
            var isEnabled: Bool
        }

        guard let data = defaults.data(forKey: legacyStorageKey),
              let legacy = try? JSONDecoder().decode([LegacyReminder].self, from: data),
              !legacy.isEmpty else {
            return nil
        }

        let isEveryday = legacy.allSatisfy { $0.weekdays.count >= 7 || $0.weekdays.isEmpty }
        var schedule = ReminderSchedule(isEnabled: true, mode: isEveryday ? .uniform : .perWeekday)

        if isEveryday {
            schedule.uniformTimes = legacy.map {
                ReminderTime(hour: $0.hour, minute: $0.minute, slot: $0.slot, isEnabled: $0.isEnabled)
            }
        } else {
            for weekday in ReminderSchedule.allWeekdays {
                schedule.weekdayTimes[weekday] = legacy
                    .filter { $0.weekdays.isEmpty || $0.weekdays.contains(weekday) }
                    .map { ReminderTime(hour: $0.hour, minute: $0.minute, slot: $0.slot, isEnabled: $0.isEnabled) }
            }
        }

        defaults.removeObject(forKey: legacyStorageKey)
        return schedule
    }
}
