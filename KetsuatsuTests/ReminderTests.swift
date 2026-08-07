import UserNotifications
import XCTest
@testable import Ketsuatsu

final class ReminderTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }

    /// 2024/10/1 は火曜日。
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2024
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    private func makeSchedule(
        mode: ReminderSchedule.Mode = .uniform,
        uniform: [ReminderTime] = [],
        weekdays: [Int: [ReminderTime]] = [:]
    ) -> ReminderSchedule {
        ReminderSchedule(isEnabled: true, mode: mode, uniformTimes: uniform, weekdayTimes: weekdays)
    }

    // MARK: - 既定値

    func testDefaultScheduleIsThreeTimesADay() {
        let schedule = ReminderSchedule.standard

        XCTAssertTrue(schedule.isEnabled)
        XCTAssertEqual(schedule.mode, .uniform)
        XCTAssertEqual(schedule.times(forEditing: nil).map(\.timeText), ["07:00", "13:00", "21:00"])
        XCTAssertEqual(schedule.times(forEditing: nil).map(\.slot), [.morning, .noon, .evening])
        XCTAssertEqual(schedule.weeklyCount, 21)
        XCTAssertEqual(schedule.summaryText, "毎日 3 回")
    }

    // MARK: - まとめて設定

    func testUniformScheduleAppliesToEveryWeekday() {
        let schedule = makeSchedule(uniform: ReminderPreset.threeTimesDaily.times)

        for weekday in ReminderSchedule.allWeekdays {
            XCTAssertEqual(schedule.times(for: weekday).count, 3, "曜日 \(weekday)")
        }
        XCTAssertEqual(schedule.notificationRequestCount, 3, "毎日の通知は時刻ごとに 1 件でよい")
    }

    func testUniformScheduleCreatesOneRepeatingRequestPerTime() {
        let requests = ReminderStore.makeRequests(for: makeSchedule(uniform: ReminderPreset.threeTimesDaily.times))

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 3, "識別子は重複しない")

        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.count, 3)
        XCTAssertTrue(triggers.allSatisfy { $0.repeats })
        XCTAssertTrue(triggers.allSatisfy { $0.dateComponents.weekday == nil }, "毎日なので曜日は指定しない")
        XCTAssertEqual(Set(triggers.compactMap { $0.dateComponents.hour }), [7, 13, 21])
    }

    func testDisabledTimeIsNotScheduled() {
        var times = ReminderPreset.threeTimesDaily.times
        times[1].isEnabled = false

        let schedule = makeSchedule(uniform: times)

        XCTAssertEqual(schedule.weeklyCount, 14)
        XCTAssertEqual(ReminderStore.makeRequests(for: schedule).count, 2)
    }

    func testDisabledScheduleCreatesNoRequests() {
        var schedule = makeSchedule(uniform: ReminderPreset.threeTimesDaily.times)
        schedule.isEnabled = false

        XCTAssertTrue(ReminderStore.makeRequests(for: schedule).isEmpty)
        XCTAssertNil(schedule.nextTriggerDate(after: date(day: 1, hour: 8), calendar: calendar))
    }

    // MARK: - 曜日ごとの設定

    func testPerWeekdaySchedule() {
        // 平日は朝だけ、土日は朝と晩
        var weekdays: [Int: [ReminderTime]] = [:]
        for weekday in 2...6 {
            weekdays[weekday] = [ReminderTime(hour: 7)]
        }
        for weekday in [1, 7] {
            weekdays[weekday] = [ReminderTime(hour: 8), ReminderTime(hour: 21)]
        }

        let schedule = makeSchedule(mode: .perWeekday, weekdays: weekdays)

        XCTAssertEqual(schedule.times(for: 2).count, 1)
        XCTAssertEqual(schedule.times(for: 7).count, 2)
        XCTAssertEqual(schedule.weeklyCount, 9)
        XCTAssertEqual(schedule.summaryText, "曜日ごと・週 9 回")

        let requests = ReminderStore.makeRequests(for: schedule)
        XCTAssertEqual(requests.count, 9, "曜日ごとの設定は曜日 × 時刻ぶんの通知が必要")

        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertTrue(triggers.allSatisfy { $0.dateComponents.weekday != nil })
        XCTAssertEqual(triggers.filter { $0.dateComponents.weekday == 1 }.count, 2)
        XCTAssertEqual(triggers.filter { $0.dateComponents.weekday == 3 }.count, 1)
    }

    /// 「まとめて」→「曜日ごと」に切り替えたら、いまの時刻が全曜日へ引き継がれる。
    func testSwitchingToPerWeekdayCopiesUniformTimes() {
        var schedule = makeSchedule(uniform: ReminderPreset.threeTimesDaily.times)

        schedule.switchMode(to: .perWeekday)

        XCTAssertEqual(schedule.mode, .perWeekday)
        for weekday in ReminderSchedule.allWeekdays {
            XCTAssertEqual(schedule.times(for: weekday).map(\.timeText), ["07:00", "13:00", "21:00"])
        }
        // 引き継いだ時刻は曜日ごとに別の ID を持つ（片方だけ消せるように）
        let mondayIDs = Set(schedule.times(for: 2).map(\.id))
        let tuesdayIDs = Set(schedule.times(for: 3).map(\.id))
        XCTAssertTrue(mondayIDs.isDisjoint(with: tuesdayIDs))
    }

    func testCopyTimesToOtherWeekdays() {
        var schedule = makeSchedule(mode: .perWeekday, weekdays: [1: [ReminderTime(hour: 9), ReminderTime(hour: 20)]])

        schedule.copyTimes(from: 1, to: [2, 3])

        XCTAssertEqual(schedule.times(for: 2).map(\.timeText), ["09:00", "20:00"])
        XCTAssertEqual(schedule.times(for: 3).map(\.timeText), ["09:00", "20:00"])
        XCTAssertTrue(schedule.times(for: 4).isEmpty, "指定していない曜日は変えない")
    }

    // MARK: - 編集

    func testAddUpdateRemoveTime() {
        var schedule = makeSchedule(uniform: [ReminderTime(hour: 7)])
        let added = ReminderTime(hour: 13)

        schedule.addTime(added, weekday: nil)
        XCTAssertEqual(schedule.times(forEditing: nil).count, 2)

        var updated = added
        updated.hour = 15
        schedule.updateTime(updated, weekday: nil)
        XCTAssertEqual(schedule.times(forEditing: nil).map(\.timeText), ["07:00", "15:00"])

        schedule.removeTime(id: added.id, weekday: nil)
        XCTAssertEqual(schedule.times(forEditing: nil).map(\.timeText), ["07:00"])
    }

    func testSuggestedNewTimeFillsMissingSlots() {
        var schedule = makeSchedule(uniform: [ReminderTime(hour: 7)])
        XCTAssertEqual(schedule.suggestedNewTime(for: nil).timeText, "13:00")

        schedule.addTime(ReminderTime(hour: 13), weekday: nil)
        XCTAssertEqual(schedule.suggestedNewTime(for: nil).timeText, "21:00")
    }

    func testApplyPresetInPerWeekdayModeFillsEveryWeekday() {
        var schedule = makeSchedule(mode: .perWeekday)

        schedule.apply(.twiceDaily)

        XCTAssertEqual(schedule.weeklyCount, 14)
        for weekday in ReminderSchedule.allWeekdays {
            XCTAssertEqual(schedule.times(for: weekday).map(\.timeText), ["07:00", "21:00"])
        }
    }

    // MARK: - 次の通知

    func testNextTriggerLaterToday() {
        let schedule = makeSchedule(uniform: ReminderPreset.threeTimesDaily.times)

        let next = schedule.nextTriggerDate(after: date(day: 1, hour: 8), calendar: calendar)

        XCTAssertEqual(next, date(day: 1, hour: 13), "同じ日の次の時刻を返す")
    }

    func testNextTriggerMovesToNextDay() {
        let schedule = makeSchedule(uniform: [ReminderTime(hour: 7)])

        let next = schedule.nextTriggerDate(after: date(day: 1, hour: 8), calendar: calendar)

        XCTAssertEqual(next, date(day: 2, hour: 7))
    }

    func testNextTriggerRespectsWeekdaySchedule() {
        // 土曜（7）だけ 7:00。2024/10/1 は火曜日なので次は 10/5（土）。
        let schedule = makeSchedule(mode: .perWeekday, weekdays: [7: [ReminderTime(hour: 7)]])

        let next = schedule.nextTriggerDate(after: date(day: 1, hour: 8), calendar: calendar)

        XCTAssertEqual(next, date(day: 5, hour: 7))
    }

    // MARK: - 通知件数の上限

    func testRequestsAreCappedAtLimit() {
        // 1 日 10 回 × 7 曜日 = 70 件。iOS の上限を超えるぶんは登録しない。
        var weekdays: [Int: [ReminderTime]] = [:]
        for weekday in ReminderSchedule.allWeekdays {
            weekdays[weekday] = (6..<16).map { ReminderTime(hour: $0) }
        }
        let schedule = makeSchedule(mode: .perWeekday, weekdays: weekdays)

        XCTAssertEqual(schedule.notificationRequestCount, 70)

        let requests = ReminderStore.makeRequests(for: schedule, limit: 60)
        XCTAssertEqual(requests.count, 60)

        // 早い時刻を優先するので、どの曜日にも朝の通知が残る。
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        for weekday in ReminderSchedule.allWeekdays {
            XCTAssertTrue(
                triggers.contains { $0.dateComponents.weekday == weekday && $0.dateComponents.hour == 6 },
                "曜日 \(weekday) の 6 時が残っていない"
            )
        }
    }

    // MARK: - 表示

    func testTimeText() {
        XCTAssertEqual(ReminderTime(hour: 7, minute: 5).timeText, "07:05")
        XCTAssertEqual(ReminderTime(hour: 21, minute: 30).timeText, "21:30")
    }

    func testSlotIsInferredFromHour() {
        XCTAssertEqual(ReminderTime(hour: 7).slot, .morning)
        XCTAssertEqual(ReminderTime(hour: 13).slot, .noon)
        XCTAssertEqual(ReminderTime(hour: 21).slot, .evening)
        XCTAssertEqual(ReminderTime(hour: 7, slot: .other).slot, .other, "明示した時間帯が優先される")
    }
}
