import Foundation
import Observation
import UserNotifications

/// 測定リマインダー 1 件ぶんの設定。
struct ReminderItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    /// 1 = 日曜 … 7 = 土曜（`Calendar` の weekday に合わせる）。空 or 全選択なら毎日。
    var weekdays: Set<Int> = Set(1...7)
    var slot: MeasurementSlot = .morning
    var isEnabled: Bool = true

    var isEveryday: Bool { weekdays.count >= 7 || weekdays.isEmpty }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var weekdayText: String {
        guard !isEveryday else { return "毎日" }
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        return weekdays.sorted()
            .compactMap { index -> String? in
                guard (1...7).contains(index) else { return nil }
                return symbols[index - 1]
            }
            .joined(separator: "・")
    }

    /// 次に通知される日時（有効なもののみ）。
    func nextTriggerDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let targetWeekdays = isEveryday ? Set(1...7) : weekdays
        return (0...7).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let candidate = calendar.date(from: components), candidate > date else { return nil }
            return targetWeekdays.contains(calendar.component(.weekday, from: candidate)) ? candidate : nil
        }
        .min()
    }

    static func defaultMorning() -> ReminderItem {
        ReminderItem(hour: 7, minute: 0, slot: .morning)
    }

    static func defaultEvening() -> ReminderItem {
        ReminderItem(hour: 21, minute: 0, slot: .evening)
    }
}

/// リマインダーの保存と通知スケジュールの同期を担当する。
@MainActor
@Observable
final class ReminderStore {
    private static let storageKey = "reminders.v1"
    private static let notificationPrefix = "bp-reminder"

    private(set) var reminders: [ReminderItem] = []
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        self.reminders = Self.load(from: defaults)
    }

    var nextReminderDate: Date? {
        reminders.compactMap { $0.nextTriggerDate() }.min()
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// 通知の許可を求める。許可されたらその場でスケジュールし直す。
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        if granted { await synchronize() }
        return granted
    }

    // MARK: - 編集

    func add(_ reminder: ReminderItem) async {
        reminders.append(reminder)
        sort()
        await persistAndSync()
    }

    func update(_ reminder: ReminderItem) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        sort()
        await persistAndSync()
    }

    func remove(at offsets: IndexSet) async {
        reminders.remove(atOffsets: offsets)
        await persistAndSync()
    }

    func remove(id: UUID) async {
        reminders.removeAll { $0.id == id }
        await persistAndSync()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) async {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].isEnabled = isEnabled
        await persistAndSync()
    }

    /// 初回起動時に朝・晩の既定リマインダーを用意する（通知は無効のまま）。
    func installDefaultsIfNeeded() async {
        guard defaults.object(forKey: Self.storageKey) == nil else { return }
        reminders = [.defaultMorning(), .defaultEvening()]
        await persistAndSync()
    }

    // MARK: - 通知スケジュール

    /// 登録済みの通知をすべて作り直す。
    func synchronize() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        for reminder in reminders where reminder.isEnabled {
            for request in Self.makeRequests(for: reminder) {
                try? await center.add(request)
            }
        }
    }

    /// リマインダー 1 件ぶんの通知リクエストを作る（純粋な変換なのでどこからでも呼べる）。
    nonisolated static func makeRequests(for reminder: ReminderItem) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = "血圧を測る時間です"
        content.body = "\(reminder.slot.title)の血圧を記録しましょう。"
        content.sound = .default

        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute

        if reminder.isEveryday {
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            return [
                UNNotificationRequest(
                    identifier: "\(notificationPrefix).\(reminder.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
            ]
        }

        return reminder.weekdays.sorted().map { weekday in
            var weekdayComponents = components
            weekdayComponents.weekday = weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: weekdayComponents, repeats: true)
            return UNNotificationRequest(
                identifier: "\(notificationPrefix).\(reminder.id.uuidString).\(weekday)",
                content: content,
                trigger: trigger
            )
        }
    }

    // MARK: - 永続化

    private func persistAndSync() async {
        persist()
        await synchronize()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func sort() {
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private static func load(from defaults: UserDefaults) -> [ReminderItem] {
        guard let data = defaults.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([ReminderItem].self, from: data) else {
            return []
        }
        return items
    }
}
