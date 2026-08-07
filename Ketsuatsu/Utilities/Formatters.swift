import Foundation

enum AppFormatter {
    static let japanese = Locale(identifier: "ja_JP")

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = japanese
        formatter.dateFormat = "M月d日(E) HH:mm"
        return formatter
    }()

    static let dayHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = japanese
        formatter.dateFormat = "yyyy年M月d日(E)"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = japanese
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = japanese
        formatter.dateFormat = "M/d"
        return formatter
    }()

    /// 平均値などの小数表示（小数第 1 位まで）。
    static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// 「+3.2」「-1.5」のように符号付きで表示する。
    static func signed(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    static func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }

    /// 「今日」「昨日」などの相対表記を優先した日付見出し。
    static func relativeDayHeader(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "今日" }
        if calendar.isDateInYesterday(date) { return "昨日" }
        return dayHeader.string(from: date)
    }
}
