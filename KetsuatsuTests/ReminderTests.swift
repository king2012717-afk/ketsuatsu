import XCTest
@testable import Ketsuatsu

final class ReminderTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }

    private func date(year: Int = 2024, month: Int = 10, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    func testNextTriggerLaterToday() {
        let reminder = ReminderItem(hour: 21, minute: 0)
        // 2024/10/1 は火曜日
        let now = date(day: 1, hour: 8)

        let next = reminder.nextTriggerDate(after: now, calendar: calendar)

        XCTAssertEqual(next, date(day: 1, hour: 21))
    }

    func testNextTriggerMovesToNextDay() {
        let reminder = ReminderItem(hour: 7, minute: 30)
        let now = date(day: 1, hour: 8)

        let next = reminder.nextTriggerDate(after: now, calendar: calendar)

        XCTAssertEqual(next, date(day: 2, hour: 7, minute: 30))
    }

    func testNextTriggerRespectsWeekdays() {
        // 日曜（1）と土曜（7）だけ。2024/10/1 は火曜日なので次は 10/5（土）。
        let reminder = ReminderItem(hour: 7, minute: 0, weekdays: [1, 7])
        let now = date(day: 1, hour: 8)

        let next = reminder.nextTriggerDate(after: now, calendar: calendar)

        XCTAssertEqual(next, date(day: 5, hour: 7))
    }

    func testDisabledReminderHasNoTrigger() {
        var reminder = ReminderItem(hour: 7, minute: 0)
        reminder.isEnabled = false

        XCTAssertNil(reminder.nextTriggerDate(after: date(day: 1, hour: 1), calendar: calendar))
    }

    func testEverydayReminderCreatesSingleRequest() {
        let reminder = ReminderItem(hour: 7, minute: 0)

        let requests = ReminderStore.makeRequests(for: reminder)

        XCTAssertEqual(requests.count, 1, "毎日のリマインダーは 1 件の繰り返し通知にまとめる")
    }

    func testWeekdayReminderCreatesRequestPerDay() {
        let reminder = ReminderItem(hour: 7, minute: 0, weekdays: [2, 4, 6])

        let requests = ReminderStore.makeRequests(for: reminder)

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 3, "識別子は重複しない")
    }

    func testWeekdayText() {
        XCTAssertEqual(ReminderItem(hour: 7, minute: 0).weekdayText, "毎日")
        XCTAssertEqual(ReminderItem(hour: 7, minute: 0, weekdays: [2, 6]).weekdayText, "月・金")
    }

    func testTimeText() {
        XCTAssertEqual(ReminderItem(hour: 7, minute: 5).timeText, "07:05")
        XCTAssertEqual(ReminderItem(hour: 21, minute: 30).timeText, "21:30")
    }
}
