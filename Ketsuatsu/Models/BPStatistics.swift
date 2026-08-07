import Foundation

/// 集計結果。すべて `BPMeasurement` から計算されるため SwiftData に依存しない。
struct BPStatistics: Equatable, Sendable {
    var count: Int = 0
    var averageSystolic: Double?
    var averageDiastolic: Double?
    var averagePulse: Double?
    var maxSystolic: Int?
    var minSystolic: Int?
    var maxDiastolic: Int?
    var minDiastolic: Int?
    /// 朝の平均（収縮期・拡張期）。
    var morningAverage: AveragePair?
    /// 晩の平均（収縮期・拡張期）。
    var eveningAverage: AveragePair?
    /// 目標値（収縮期・拡張期ともに）以下だった記録の割合。0.0〜1.0。
    var withinTargetRatio: Double?
    /// 記録のうち高血圧（I 度以上）に該当した割合。0.0〜1.0。
    var hypertensiveRatio: Double?
    var categoryCounts: [BPCategory: Int] = [:]

    struct AveragePair: Equatable, Sendable {
        var systolic: Double
        var diastolic: Double
    }

    var isEmpty: Bool { count == 0 }

    /// 朝と晩の収縮期血圧の差。大きいと「モーニングサージ」の傾向。
    var morningEveningDifference: Double? {
        guard let morning = morningAverage, let evening = eveningAverage else { return nil }
        return morning.systolic - evening.systolic
    }

    static func compute(
        _ measurements: [some BPMeasurement],
        targetSystolic: Int,
        targetDiastolic: Int,
        standard: BPStandard
    ) -> BPStatistics {
        var stats = BPStatistics()
        guard !measurements.isEmpty else { return stats }

        stats.count = measurements.count
        let systolics = measurements.map(\.systolic)
        let diastolics = measurements.map(\.diastolic)
        let pulses = measurements.compactMap(\.pulse)

        stats.averageSystolic = Self.average(systolics)
        stats.averageDiastolic = Self.average(diastolics)
        stats.averagePulse = pulses.isEmpty ? nil : Self.average(pulses)
        stats.maxSystolic = systolics.max()
        stats.minSystolic = systolics.min()
        stats.maxDiastolic = diastolics.max()
        stats.minDiastolic = diastolics.min()

        stats.morningAverage = Self.averagePair(measurements.filter { $0.slot == .morning })
        stats.eveningAverage = Self.averagePair(measurements.filter { $0.slot == .evening })

        let withinTarget = measurements.filter { $0.systolic <= targetSystolic && $0.diastolic <= targetDiastolic }
        stats.withinTargetRatio = Double(withinTarget.count) / Double(measurements.count)

        var counts: [BPCategory: Int] = [:]
        for measurement in measurements {
            let category = measurement.category(standard: standard)
            counts[category, default: 0] += 1
        }
        stats.categoryCounts = counts
        let hypertensive = counts.reduce(into: 0) { partial, entry in
            if entry.key.isHypertensive { partial += entry.value }
        }
        stats.hypertensiveRatio = Double(hypertensive) / Double(measurements.count)

        return stats
    }

    private static func average(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func averagePair(_ measurements: [some BPMeasurement]) -> AveragePair? {
        guard let systolic = average(measurements.map(\.systolic)),
              let diastolic = average(measurements.map(\.diastolic)) else { return nil }
        return AveragePair(systolic: systolic, diastolic: diastolic)
    }
}

/// ならした 1 点ぶんの値。グラフの折れ線に使う。
struct AveragePoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    var date: Date
    var systolic: Double
    var diastolic: Double
    var pulse: Double?
    var count: Int
}

/// 平均をまとめる単位。期間が長いときに点が多くなりすぎないよう切り替える。
enum AggregationUnit: String, CaseIterable, Sendable {
    case day
    case week
    case month

    var title: String {
        switch self {
        case .day: return "日ごとの平均"
        case .week: return "週ごとの平均"
        case .month: return "月ごとの平均"
        }
    }

    func periodStart(for date: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    /// 期間の長さから適切な単位を選ぶ。
    static func automatic(forDayCount dayCount: Int) -> AggregationUnit {
        switch dayCount {
        case ..<46: return .day
        case ..<201: return .week
        default: return .month
        }
    }
}

enum BPAggregator {
    /// 日ごとの平均値を古い順で返す。
    static func dailyAverages<M: BPMeasurement>(
        _ measurements: [M],
        calendar: Calendar = .current
    ) -> [AveragePoint] {
        averages(measurements, by: .day, calendar: calendar)
    }

    /// 指定した単位で平均した値を古い順で返す。
    static func averages<M: BPMeasurement>(
        _ measurements: [M],
        by unit: AggregationUnit,
        calendar: Calendar = .current
    ) -> [AveragePoint] {
        let grouped = Dictionary(grouping: measurements) { unit.periodStart(for: $0.measuredAt, calendar: calendar) }
        return grouped.map { date, items in
            let pulses = items.compactMap(\.pulse)
            return AveragePoint(
                date: date,
                systolic: Double(items.map(\.systolic).reduce(0, +)) / Double(items.count),
                diastolic: Double(items.map(\.diastolic).reduce(0, +)) / Double(items.count),
                pulse: pulses.isEmpty ? nil : Double(pulses.reduce(0, +)) / Double(pulses.count),
                count: items.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// 期間で絞り込む（nil なら全期間）。
    static func filter<M: BPMeasurement>(_ measurements: [M], in interval: DateInterval?) -> [M] {
        guard let interval else { return measurements }
        return measurements.filter { interval.contains($0.measuredAt) }
    }

    /// 直近 N 日ぶんの記録だけを取り出す（`days` が nil なら全期間）。
    static func filter<M: BPMeasurement>(
        _ measurements: [M],
        days: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [M] {
        guard let days else { return measurements }
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        return measurements.filter { $0.measuredAt >= start }
    }

    /// 直近の平均が 1 つ前の同じ長さの期間と比べてどれだけ変化したか（収縮期）。
    static func trend<M: BPMeasurement>(
        _ measurements: [M],
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let currentStart = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let previousStart = calendar.date(byAdding: .day, value: -(days * 2 - 1), to: today) else { return nil }

        let current = measurements.filter { $0.measuredAt >= currentStart }
        let previous = measurements.filter { $0.measuredAt >= previousStart && $0.measuredAt < currentStart }
        guard !current.isEmpty, !previous.isEmpty else { return nil }

        let currentAverage = Double(current.map(\.systolic).reduce(0, +)) / Double(current.count)
        let previousAverage = Double(previous.map(\.systolic).reduce(0, +)) / Double(previous.count)
        return currentAverage - previousAverage
    }
}
