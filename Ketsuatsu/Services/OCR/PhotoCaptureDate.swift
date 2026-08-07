import Foundation
import ImageIO

/// 写真の Exif から撮影日時を取り出す。
///
/// あとから写真を選んで記録するとき、「読み込んだ時刻」ではなく「撮影した時刻」を
/// 測定日時に使えるようにするためのもの。
/// 解析部分は辞書と文字列だけを相手にしているので単体テストできる。
enum PhotoCaptureDate {

    /// Exif の日時表記（例: `2024:10:25 07:35:12`）。
    private static let exifFormat = "yyyy:MM:dd HH:mm:ss"

    /// Exif に載っていない環境もあるため、見つからなければ nil を返す。
    static func extract(from imageData: Data, now: Date = Date()) -> Date? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return extract(from: properties, now: now)
    }

    static func extract(from properties: [CFString: Any], now: Date = Date()) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        // iOS 14 以降の写真にはタイムゾーンのオフセットも入っている。
        let offset = (exif?["OffsetTimeOriginal" as CFString] as? String)
            ?? (exif?["OffsetTimeDigitized" as CFString] as? String)
            ?? (exif?["OffsetTime" as CFString] as? String)

        let candidates = [
            exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
            tiff?[kCGImagePropertyTIFFDateTime] as? String
        ]

        for text in candidates.compactMap({ $0 }) {
            if let date = parse(text, offset: offset), isReasonable(date, now: now) {
                return date
            }
        }
        return nil
    }

    static func parse(_ text: String, offset: String? = nil) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = exifFormat
        formatter.timeZone = offset.flatMap(timeZone(fromOffset:)) ?? .current
        return formatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// `+09:00` のような表記からタイムゾーンを作る。
    static func timeZone(fromOffset offset: String) -> TimeZone? {
        let text = offset.trimmingCharacters(in: .whitespaces)
        guard let signCharacter = text.first, signCharacter == "+" || signCharacter == "-" else { return nil }

        let numbers = text.dropFirst().split(separator: ":")
        guard let hours = numbers.first.flatMap({ Int($0) }) else { return nil }
        let minutes = numbers.count > 1 ? (Int(numbers[1]) ?? 0) : 0

        let sign = signCharacter == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }

    /// 明らかにおかしい日時（未来や 2000 年より前）は採用しない。
    static func isReasonable(_ date: Date, now: Date = Date()) -> Bool {
        let lowerBound = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
        return date >= lowerBound && date <= now.addingTimeInterval(60 * 60)
    }
}
