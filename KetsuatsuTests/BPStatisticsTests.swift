import XCTest
@testable import Ketsuatsu

final class BPStatisticsTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2024
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }

    private func sample(day: Int, hour: Int, systolic: Int, diastolic: Int, pulse: Int? = nil) -> BPSample {
        BPSample(
            measuredAt: date(day, hour: hour),
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            slot: MeasurementSlot.inferred(from: date(day, hour: hour), calendar: calendar)
        )
    }

    func testEmptyStatistics() {
        let stats = BPStatistics.compute(
            [BPSample](),
            targetSystolic: 135,
            targetDiastolic: 85,
            standard: .home
        )

        XCTAssertTrue(stats.isEmpty)
        XCTAssertNil(stats.averageSystolic)
        XCTAssertNil(stats.withinTargetRatio)
    }

    func testAverages() {
        let samples = [
            sample(day: 1, hour: 7, systolic: 130, diastolic: 80, pulse: 70),
            sample(day: 1, hour: 21, systolic: 120, diastolic: 76, pulse: 66),
            sample(day: 2, hour: 7, systolic: 140, diastolic: 90)
        ]

        let stats = BPStatistics.compute(samples, targetSystolic: 135, targetDiastolic: 85, standard: .home)

        XCTAssertEqual(stats.count, 3)
        XCTAssertEqual(stats.averageSystolic ?? 0, 130, accuracy: 0.001)
        XCTAssertEqual(stats.averageDiastolic ?? 0, 82, accuracy: 0.001)
        XCTAssertEqual(stats.averagePulse ?? 0, 68, accuracy: 0.001, "脈拍が無い記録は平均に含めない")
        XCTAssertEqual(stats.maxSystolic, 140)
        XCTAssertEqual(stats.minSystolic, 120)
    }

    func testMorningAndEveningAverages() {
        let samples = [
            sample(day: 1, hour: 7, systolic: 140, diastolic: 88),
            sample(day: 2, hour: 7, systolic: 136, diastolic: 86),
            sample(day: 1, hour: 21, systolic: 124, diastolic: 78)
        ]

        let stats = BPStatistics.compute(samples, targetSystolic: 135, targetDiastolic: 85, standard: .home)

        XCTAssertEqual(stats.morningAverage?.systolic ?? 0, 138, accuracy: 0.001)
        XCTAssertEqual(stats.eveningAverage?.systolic ?? 0, 124, accuracy: 0.001)
        XCTAssertEqual(stats.morningEveningDifference ?? 0, 14, accuracy: 0.001)
    }

    func testTargetAndCategoryRatios() {
        let samples = [
            sample(day: 1, hour: 7, systolic: 130, diastolic: 80),   // 目標内・高値
            sample(day: 2, hour: 7, systolic: 150, diastolic: 95),   // 目標外・II 度
            sample(day: 3, hour: 7, systolic: 120, diastolic: 70),   // 目標内・正常高値
            sample(day: 4, hour: 7, systolic: 138, diastolic: 88)    // 目標外・I 度
        ]

        let stats = BPStatistics.compute(samples, targetSystolic: 135, targetDiastolic: 85, standard: .home)

        XCTAssertEqual(stats.withinTargetRatio ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.hypertensiveRatio ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.categoryCounts[.grade1], 1)
        XCTAssertEqual(stats.categoryCounts[.grade2], 1)
    }

    func testDailyAverages() {
        let samples = [
            sample(day: 1, hour: 7, systolic: 130, diastolic: 80, pulse: 70),
            sample(day: 1, hour: 21, systolic: 120, diastolic: 70, pulse: 60),
            sample(day: 2, hour: 7, systolic: 140, diastolic: 90)
        ]

        let averages = BPAggregator.dailyAverages(samples, calendar: calendar)

        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages[0].systolic, 125, accuracy: 0.001)
        XCTAssertEqual(averages[0].count, 2)
        XCTAssertEqual(averages[0].pulse ?? 0, 65, accuracy: 0.001)
        XCTAssertEqual(averages[1].systolic, 140, accuracy: 0.001)
        XCTAssertNil(averages[1].pulse)
        XCTAssertLessThan(averages[0].date, averages[1].date, "古い順に並ぶ")
    }

    func testFilterByPeriod() {
        let now = date(10, hour: 12)
        let samples = [
            sample(day: 1, hour: 7, systolic: 130, diastolic: 80),
            sample(day: 8, hour: 7, systolic: 132, diastolic: 82),
            sample(day: 10, hour: 7, systolic: 128, diastolic: 78)
        ]

        let recent = BPAggregator.filter(samples, days: 7, now: now, calendar: calendar)

        XCTAssertEqual(recent.count, 2, "10 月 4 日以降の記録だけが残る")
        XCTAssertEqual(BPAggregator.filter(samples, days: nil, now: now, calendar: calendar).count, 3)
    }

    func testTrendComparesWithPreviousPeriod() {
        let now = date(14, hour: 12)
        let samples = [
            // 前の 7 日（10/1〜10/7）: 平均 120
            sample(day: 3, hour: 7, systolic: 120, diastolic: 80),
            sample(day: 5, hour: 7, systolic: 120, diastolic: 80),
            // 直近 7 日（10/8〜10/14）: 平均 130
            sample(day: 10, hour: 7, systolic: 128, diastolic: 82),
            sample(day: 12, hour: 7, systolic: 132, diastolic: 84)
        ]

        let trend = BPAggregator.trend(samples, days: 7, now: now, calendar: calendar)

        XCTAssertEqual(trend ?? 0, 10, accuracy: 0.001)
    }

    func testSlotInference() {
        XCTAssertEqual(MeasurementSlot.inferred(from: date(1, hour: 7), calendar: calendar), .morning)
        XCTAssertEqual(MeasurementSlot.inferred(from: date(1, hour: 21), calendar: calendar), .evening)
        XCTAssertEqual(MeasurementSlot.inferred(from: date(1, hour: 14), calendar: calendar), .other)
        XCTAssertEqual(MeasurementSlot.inferred(from: date(1, hour: 1), calendar: calendar), .evening)
    }

    func testDerivedValues() {
        let measurement = sample(day: 1, hour: 7, systolic: 130, diastolic: 82)

        XCTAssertEqual(measurement.pulsePressure, 48)
        XCTAssertEqual(measurement.meanArterialPressure, 98, accuracy: 0.001)
    }
}
