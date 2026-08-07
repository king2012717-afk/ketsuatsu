import XCTest
@testable import Ketsuatsu

final class CSVExporterTests: XCTestCase {

    private func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2024
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components) ?? Date()
    }

    func testHeaderAndRowCount() {
        let records = [
            BPRecord(measuredAt: date(day: 2, hour: 7), systolic: 128, diastolic: 82, pulse: 68),
            BPRecord(measuredAt: date(day: 1, hour: 21), systolic: 132, diastolic: 85)
        ]

        let csv = CSVExporter.csv(from: records, standard: .home)
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0]), CSVExporter.header)
        XCTAssertTrue(String(lines[1]).contains("132"), "古い記録から順に並ぶ")
        XCTAssertTrue(String(lines[2]).contains("128"))
    }

    func testPulseIsEmptyWhenMissing() {
        let record = BPRecord(measuredAt: date(day: 1, hour: 7), systolic: 120, diastolic: 78)
        let csv = CSVExporter.csv(from: [record], standard: .home)

        XCTAssertTrue(csv.contains("120,78,,"), "脈拍が無い場合は空欄になる")
    }

    func testEscapesSpecialCharacters() {
        XCTAssertEqual(CSVExporter.escape("ふつうのメモ"), "ふつうのメモ")
        XCTAssertEqual(CSVExporter.escape("朝, 起床後"), "\"朝, 起床後\"")
        XCTAssertEqual(CSVExporter.escape("\"引用\""), "\"\"\"引用\"\"\"")
        XCTAssertEqual(CSVExporter.escape("改行\nあり"), "\"改行\nあり\"")
    }

    func testNoteWithCommaIsQuoted() {
        let record = BPRecord(
            measuredAt: date(day: 1, hour: 7),
            systolic: 120,
            diastolic: 78,
            note: "散歩のあと, 少し疲れた"
        )

        let csv = CSVExporter.csv(from: [record], standard: .home)

        XCTAssertTrue(csv.contains("\"散歩のあと, 少し疲れた\""))
    }

    func testIncludesCategoryForStandard() {
        let record = BPRecord(measuredAt: date(day: 1, hour: 7), systolic: 136, diastolic: 84)

        XCTAssertTrue(CSVExporter.csv(from: [record], standard: .home).contains("I 度高血圧"))
        XCTAssertTrue(CSVExporter.csv(from: [record], standard: .office).contains("高値血圧"))
    }
}
