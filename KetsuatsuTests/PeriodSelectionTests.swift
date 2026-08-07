import XCTest
@testable import Ketsuatsu

final class PeriodSelectionTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 12, year: Int = 2024) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? Date()
    }

    private func sample(_ month: Int, _ day: Int, hour: Int = 7, year: Int = 2024) -> BPSample {
        BPSample(
            measuredAt: date(month, day, hour: hour, year: year),
            systolic: 128,
            diastolic: 82,
            pulse: 68,
            slot: MeasurementSlot.inferred(fromHour: hour)
        )
    }

    // MARK: - 期間

    func testWeekIntervalCoversSevenDays() {
        let selection = PeriodSelection(filter: .week1)
        let now = date(10, 25)

        let interval = selection.interval(now: now, calendar: calendar)

        XCTAssertEqual(interval?.start, calendar.startOfDay(for: date(10, 19)), "今日を含む 7 日間")
        XCTAssertEqual(interval?.end, calendar.startOfDay(for: date(10, 26)), "当日の終わりまで含む")
    }

    func testHalfYearAndOtherPresets() {
        XCTAssertEqual(PeriodFilter.month6.days, 180)
        XCTAssertEqual(PeriodFilter.month6.title, "半年")
        XCTAssertEqual(PeriodFilter.year1.days, 365)
        XCTAssertNil(PeriodFilter.all.days)
        XCTAssertNil(PeriodFilter.custom.days)
    }

    func testAllPeriodHasNoInterval() {
        XCTAssertNil(PeriodSelection(filter: .all).interval(now: date(10, 25), calendar: calendar))
    }

    func testCustomIntervalIncludesBothEndDays() {
        let selection = PeriodSelection(
            filter: .custom,
            customStart: date(10, 1, hour: 23),
            customEnd: date(10, 10, hour: 1)
        )

        let interval = selection.interval(now: date(10, 25), calendar: calendar)

        XCTAssertEqual(interval?.start, calendar.startOfDay(for: date(10, 1)))
        XCTAssertEqual(interval?.end, calendar.startOfDay(for: date(10, 11)), "終了日の当日も含む")
    }

    func testCustomIntervalAcceptsReversedDates() {
        let selection = PeriodSelection(
            filter: .custom,
            customStart: date(10, 10),
            customEnd: date(10, 1)
        )

        let interval = selection.interval(now: date(10, 25), calendar: calendar)

        XCTAssertEqual(interval?.start, calendar.startOfDay(for: date(10, 1)), "開始と終了が逆でも扱える")
        XCTAssertEqual(interval?.end, calendar.startOfDay(for: date(10, 11)))
    }

    func testFilterByInterval() {
        let samples = [sample(9, 30), sample(10, 1), sample(10, 5), sample(10, 20)]
        let selection = PeriodSelection(filter: .custom, customStart: date(10, 1), customEnd: date(10, 5))

        let filtered = BPAggregator.filter(samples, in: selection.interval(now: date(10, 25), calendar: calendar))

        XCTAssertEqual(filtered.count, 2)
        XCTAssertNil(
            filtered.first { $0.measuredAt < self.date(10, 1, hour: 0) },
            "期間より前の記録は含まない"
        )
    }

    func testFilterWithoutIntervalKeepsEverything() {
        let samples = [sample(9, 30), sample(10, 20)]

        XCTAssertEqual(BPAggregator.filter(samples, in: nil).count, 2)
    }

    // MARK: - 期間の長さと集計単位

    func testDayCount() {
        XCTAssertEqual(PeriodSelection(filter: .week1).dayCount(now: date(10, 25), calendar: calendar), 7)
        XCTAssertEqual(PeriodSelection(filter: .month6).dayCount(now: date(10, 25), calendar: calendar), 180)

        let custom = PeriodSelection(filter: .custom, customStart: date(10, 1), customEnd: date(10, 10))
        XCTAssertEqual(custom.dayCount(now: date(10, 25), calendar: calendar), 10)
    }

    func testAggregationUnitFollowsPeriodLength() {
        XCTAssertEqual(AggregationUnit.automatic(forDayCount: 7), .day)
        XCTAssertEqual(AggregationUnit.automatic(forDayCount: 30), .day)
        XCTAssertEqual(AggregationUnit.automatic(forDayCount: 90), .week)
        XCTAssertEqual(AggregationUnit.automatic(forDayCount: 180), .week)
        XCTAssertEqual(AggregationUnit.automatic(forDayCount: 365), .month)
    }

    // MARK: - 集計

    func testWeeklyAverages() {
        // 10/1(火) と 10/3(木) は同じ週、10/8(火) は次の週
        let samples = [
            BPSample(measuredAt: date(10, 1, hour: 7), systolic: 120, diastolic: 80),
            BPSample(measuredAt: date(10, 3, hour: 7), systolic: 130, diastolic: 84),
            BPSample(measuredAt: date(10, 8, hour: 7), systolic: 140, diastolic: 90)
        ]

        let averages = BPAggregator.averages(samples, by: .week, calendar: calendar)

        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages[0].systolic, 125, accuracy: 0.001)
        XCTAssertEqual(averages[0].count, 2)
        XCTAssertEqual(averages[1].systolic, 140, accuracy: 0.001)
    }

    func testMonthlyAverages() throws {
        let samples = [
            BPSample(measuredAt: date(9, 5, hour: 7), systolic: 120, diastolic: 80),
            BPSample(measuredAt: date(9, 25, hour: 7), systolic: 130, diastolic: 84),
            BPSample(measuredAt: date(10, 2, hour: 7), systolic: 150, diastolic: 92)
        ]

        let averages = BPAggregator.averages(samples, by: .month, calendar: calendar)

        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages[0].systolic, 125, accuracy: 0.001)
        XCTAssertEqual(averages[1].systolic, 150, accuracy: 0.001)
        let septemberStart = try XCTUnwrap(calendar.dateInterval(of: .month, for: date(9, 5))?.start)
        XCTAssertEqual(averages[0].date, septemberStart)
    }

    func testSlotFilteringForCharts() {
        let samples = [
            sample(10, 1, hour: 7),   // 朝
            sample(10, 1, hour: 13),  // 昼
            sample(10, 1, hour: 21),  // 晩
            sample(10, 2, hour: 7)    // 朝
        ]

        XCTAssertEqual(samples.filter { $0.slot == .morning }.count, 2)
        XCTAssertEqual(samples.filter { $0.slot == .noon }.count, 1)
        XCTAssertEqual(samples.filter { $0.slot == .evening }.count, 1)
    }
}
