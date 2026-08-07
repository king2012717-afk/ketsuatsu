import Foundation

/// 集計・表示の対象期間。
enum PeriodFilter: String, CaseIterable, Identifiable, Sendable {
    case week1
    case month1
    case month3
    case month6
    case year1
    case all
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week1: return "1週間"
        case .month1: return "1か月"
        case .month3: return "3か月"
        case .month6: return "半年"
        case .year1: return "1年"
        case .all: return "全期間"
        case .custom: return "期間指定"
        }
    }

    /// 集計対象とする日数（nil は全期間、または開始日と終了日を自分で決める場合）。
    var days: Int? {
        switch self {
        case .week1: return 7
        case .month1: return 30
        case .month3: return 90
        case .month6: return 180
        case .year1: return 365
        case .all, .custom: return nil
        }
    }

    /// 開始日と終了日を選べない画面（履歴の絞り込みなど）で使う選択肢。
    static var standardCases: [PeriodFilter] { allCases.filter { $0 != .custom } }
}

/// 期間の選び方と、そこから決まる実際の日付範囲。
struct PeriodSelection: Equatable, Sendable {
    var filter: PeriodFilter = .month1
    /// 「期間指定」のときに使う開始日・終了日。
    var customStart: Date
    var customEnd: Date

    init(filter: PeriodFilter = .month1, customStart: Date? = nil, customEnd: Date? = nil, now: Date = Date()) {
        self.filter = filter
        self.customEnd = customEnd ?? now
        self.customStart = customStart
            ?? Calendar.current.date(byAdding: .month, value: -1, to: now)
            ?? now
    }

    /// 集計対象の期間。nil なら全期間。
    func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        switch filter {
        case .all:
            return nil

        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let endDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: end)

        default:
            guard let days = filter.days else { return nil }
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        }
    }

    /// 期間の長さ（日数）。全期間の場合は記録の範囲から求める。
    func dayCount(now: Date = Date(), calendar: Calendar = .current, fallbackStart: Date? = nil) -> Int {
        let interval: DateInterval?
        if filter == .all, let fallbackStart {
            interval = DateInterval(start: calendar.startOfDay(for: fallbackStart), end: now)
        } else {
            interval = self.interval(now: now, calendar: calendar)
        }
        guard let interval else { return 0 }
        return max(1, Int(interval.duration / 86_400))
    }

    /// 「10/1 〜 10/25」のような表示。
    var customRangeText: String {
        let start = min(customStart, customEnd)
        let end = max(customStart, customEnd)
        return "\(AppFormatter.shortDate.string(from: start)) 〜 \(AppFormatter.shortDate.string(from: end))"
    }
}
