import ImageIO
import XCTest
@testable import Ketsuatsu

final class PhotoCaptureDateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_730_000_000) // 2024-10-27

    /// 夏時間の影響を受けないよう、固定オフセットのタイムゾーンで基準の日時を作る。
    private func date(_ text: String, offsetHours: Double) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: Int(offsetHours * 3600))
        return formatter.date(from: text)
    }

    // MARK: - 文字列の解析

    func testParsesExifDateWithOffset() {
        let parsed = PhotoCaptureDate.parse("2024:10:25 07:35:12", offset: "+09:00")

        XCTAssertEqual(parsed, date("2024:10:25 07:35:12", offsetHours: 9))
    }

    func testParsesExifDateWithNegativeOffset() {
        let parsed = PhotoCaptureDate.parse("2024:10:25 07:35:12", offset: "-05:00")

        XCTAssertEqual(parsed, date("2024:10:25 07:35:12", offsetHours: -5))
    }

    func testParsesExifDateWithoutOffsetUsesLocalTimeZone() {
        let parsed = PhotoCaptureDate.parse("2024:10:25 07:35:12")

        var components = DateComponents()
        components.year = 2024
        components.month = 10
        components.day = 25
        components.hour = 7
        components.minute = 35
        components.second = 12
        XCTAssertEqual(parsed, Calendar.current.date(from: components))
    }

    func testRejectsMalformedText() {
        XCTAssertNil(PhotoCaptureDate.parse("2024-10-25 07:35:12"), "Exif の書式でなければ読まない")
        XCTAssertNil(PhotoCaptureDate.parse(""))
    }

    func testTimeZoneFromOffset() {
        XCTAssertEqual(PhotoCaptureDate.timeZone(fromOffset: "+09:00")?.secondsFromGMT(), 9 * 3600)
        XCTAssertEqual(PhotoCaptureDate.timeZone(fromOffset: "-03:30")?.secondsFromGMT(), -(3 * 3600 + 30 * 60))
        XCTAssertNil(PhotoCaptureDate.timeZone(fromOffset: "09:00"), "符号がなければ扱わない")
    }

    // MARK: - 妥当性

    func testRejectsFutureAndAncientDates() {
        XCTAssertTrue(PhotoCaptureDate.isReasonable(now.addingTimeInterval(-86_400), now: now))
        XCTAssertFalse(
            PhotoCaptureDate.isReasonable(now.addingTimeInterval(86_400), now: now),
            "未来の日時は採用しない"
        )
        XCTAssertFalse(
            PhotoCaptureDate.isReasonable(Date(timeIntervalSince1970: 0), now: now),
            "1970 年のような日時は採用しない"
        )
    }

    // MARK: - メタデータからの取り出し

    func testExtractsDateTimeOriginalFirst() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:10:25 07:35:12",
                kCGImagePropertyExifDateTimeDigitized: "2024:10:26 12:00:00",
                "OffsetTimeOriginal" as CFString: "+09:00"
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFDateTime: "2024:10:27 20:00:00"
            ] as [CFString: Any]
        ]

        let extracted = PhotoCaptureDate.extract(from: properties, now: now)

        XCTAssertEqual(extracted, date("2024:10:25 07:35:12", offsetHours: 9))
    }

    func testFallsBackToTiffDateTime() {
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFDateTime: "2024:10:20 21:10:00"
            ] as [CFString: Any]
        ]

        XCTAssertNotNil(PhotoCaptureDate.extract(from: properties, now: now))
    }

    func testReturnsNilWhenMetadataHasNoDate() {
        XCTAssertNil(PhotoCaptureDate.extract(from: [:], now: now))
        XCTAssertNil(
            PhotoCaptureDate.extract(
                from: [kCGImagePropertyExifDictionary: [:] as [CFString: Any]],
                now: now
            ),
            "Exif はあるが日時がない場合も nil"
        )
    }

    func testIgnoresFutureDateInMetadata() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2099:01:01 00:00:00"
            ] as [CFString: Any]
        ]

        XCTAssertNil(PhotoCaptureDate.extract(from: properties, now: now))
    }

    // MARK: - 下書きへの反映

    func testDraftUsesCaptureDate() throws {
        let captured = try XCTUnwrap(date("2024:10:25 07:35:12", offsetHours: 9))
        var result = BPParseResult.empty
        result.systolic = 128
        result.diastolic = 82

        let draft = BPDraft(parseResult: result, photoData: nil, capturedAt: captured)

        XCTAssertEqual(draft.measuredAt, captured)
        XCTAssertTrue(draft.usesPhotoCaptureDate)
        XCTAssertEqual(draft.source, .photo)
    }

    func testDraftFallsBackToNowWithoutCaptureDate() {
        var result = BPParseResult.empty
        result.systolic = 128
        result.diastolic = 82

        let draft = BPDraft(parseResult: result, photoData: nil, capturedAt: nil)

        XCTAssertFalse(draft.usesPhotoCaptureDate)
        XCTAssertEqual(draft.measuredAt.timeIntervalSinceNow, 0, accuracy: 5)
    }
}
