import Charts
import SwiftData
import SwiftUI
import UIKit

/// グラフと集計。期間と表示する系列（朝／昼／晩／平均）を切り替えて傾向を確認する。
struct ChartsView: View {
    @Environment(AppSettings.self) private var settings

    @Query(sort: \BPRecord.measuredAt, order: .forward) private var records: [BPRecord]

    @State private var period = PeriodSelection(filter: .month1)
    @State private var series: ChartSeries = .average

    /// グラフに出す系列。
    enum ChartSeries: String, CaseIterable, Identifiable, Sendable {
        case average
        case morning
        case noon
        case evening
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .average: return "平均"
            case .morning: return "朝"
            case .noon: return "昼"
            case .evening: return "晩"
            case .all: return "すべて"
            }
        }

        /// 絞り込む時間帯（nil なら絞り込まない）。
        var slot: MeasurementSlot? {
            switch self {
            case .morning: return .morning
            case .noon: return .noon
            case .evening: return .evening
            case .average, .all: return nil
            }
        }

        /// 個々の測定値をそのまま点で出すか。
        var showsRawPoints: Bool { self == .all }
    }

    // MARK: - 対象データ

    private var allSamples: [BPSample] { records.map(\.sample) }

    /// 期間で絞ったすべての記録。
    private var periodSamples: [BPSample] {
        BPAggregator.filter(allSamples, in: period.interval())
    }

    /// さらに時間帯で絞った、グラフと集計の対象。
    private var seriesSamples: [BPSample] {
        guard let slot = series.slot else { return periodSamples }
        return periodSamples.filter { $0.slot == slot }
    }

    /// 期間の長さに応じた平均の単位（日 / 週 / 月）。
    private var aggregationUnit: AggregationUnit {
        AggregationUnit.automatic(
            forDayCount: period.dayCount(fallbackStart: allSamples.first?.measuredAt)
        )
    }

    /// 生の測定値を点で出すか、ならして折れ線にするか。
    private var usesRawPoints: Bool {
        series.showsRawPoints && aggregationUnit == .day
    }

    private var chartPoints: [AveragePoint] {
        guard !usesRawPoints else {
            return seriesSamples.map { sample in
                AveragePoint(
                    date: sample.measuredAt,
                    systolic: Double(sample.systolic),
                    diastolic: Double(sample.diastolic),
                    pulse: sample.pulse.map(Double.init),
                    count: 1
                )
            }
        }
        return BPAggregator.averages(seriesSamples, by: aggregationUnit)
    }

    private var statistics: BPStatistics {
        BPStatistics.compute(
            seriesSamples,
            targetSystolic: settings.targetSystolic,
            targetDiastolic: settings.targetDiastolic,
            standard: settings.standard
        )
    }

    /// 朝晩の差は、時間帯で絞る前のデータで見る。
    private var periodStatistics: BPStatistics {
        BPStatistics.compute(
            periodSamples,
            targetSystolic: settings.targetSystolic,
            targetDiastolic: settings.targetDiastolic,
            standard: settings.standard
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    periodSection
                    seriesPicker

                    if seriesSamples.isEmpty {
                        ContentUnavailableView(
                            "データがありません",
                            systemImage: "chart.xyaxis.line",
                            description: Text(emptyDescription)
                        )
                        .padding(.top, 40)
                    } else {
                        pressureChartSection
                        pulseChartSection
                        statisticsSection
                        distributionSection
                        slotSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.pageBackground)
            .navigationTitle("グラフ")
        }
    }

    private var emptyDescription: String {
        switch series {
        case .average, .all:
            return "この期間の記録がまだありません。"
        default:
            return "この期間に「\(series.title)」の記録がありません。"
        }
    }

    // MARK: - 期間

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PeriodChips(selection: $period.filter)

            if period.filter == .custom {
                VStack(spacing: 8) {
                    DatePicker(
                        "開始日",
                        selection: $period.customStart,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "終了日",
                        selection: $period.customEnd,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }
                .environment(\.locale, AppFormatter.japanese)
                .font(.subheadline)
                .cardStyle(padding: 12)
            }

            Text(periodDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var periodDescription: String {
        let count = seriesSamples.count
        switch period.filter {
        case .all:
            return "全期間・\(count) 件"
        case .custom:
            return "\(period.customRangeText)・\(count) 件"
        default:
            return "\(period.filter.title)・\(count) 件"
        }
    }

    // MARK: - 系列

    private var seriesPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("表示", selection: $series) {
                ForEach(ChartSeries.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(seriesDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var seriesDescription: String {
        switch series {
        case .average:
            return "1 日のすべての測定を\(aggregationUnit.title)にしています。"
        case .all:
            return usesRawPoints
                ? "1 回ごとの測定値をそのまま表示しています。"
                : "期間が長いため\(aggregationUnit.title)で表示しています。"
        default:
            return aggregationUnit == .day
                ? "「\(series.title)」に記録した測定値です。"
                : "「\(series.title)」の記録を\(aggregationUnit.title)にしています。"
        }
    }

    // MARK: - 血圧グラフ

    private var pressureChartSection: some View {
        ChartCard(
            title: "血圧の推移",
            subtitle: "点線は目標値（\(settings.targetSystolic)/\(settings.targetDiastolic)）"
        ) {
            Chart {
                ForEach(chartPoints) { point in
                    if !usesRawPoints {
                        LineMark(
                            x: .value("日付", point.date),
                            y: .value("血圧", point.systolic),
                            series: .value("種類", "上")
                        )
                        .foregroundStyle(by: .value("種類", "上"))
                        LineMark(
                            x: .value("日付", point.date),
                            y: .value("血圧", point.diastolic),
                            series: .value("種類", "下")
                        )
                        .foregroundStyle(by: .value("種類", "下"))
                    }
                    PointMark(
                        x: .value("日付", point.date),
                        y: .value("血圧", point.systolic)
                    )
                    .foregroundStyle(by: .value("種類", "上"))
                    .symbolSize(usesRawPoints ? 26 : 30)
                    PointMark(
                        x: .value("日付", point.date),
                        y: .value("血圧", point.diastolic)
                    )
                    .foregroundStyle(by: .value("種類", "下"))
                    .symbolSize(usesRawPoints ? 26 : 30)
                }

                RuleMark(y: .value("目標（上）", settings.targetSystolic))
                    .foregroundStyle(Theme.systolic.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                RuleMark(y: .value("目標（下）", settings.targetDiastolic))
                    .foregroundStyle(Theme.diastolic.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartForegroundStyleScale(["上": Theme.systolic, "下": Theme.diastolic])
            .chartXAxis { dateAxis }
            .frame(height: 240)
        }
    }

    // MARK: - 脈拍グラフ

    @ViewBuilder
    private var pulseChartSection: some View {
        let pulsePoints = chartPoints.filter { $0.pulse != nil }
        if !pulsePoints.isEmpty {
            ChartCard(
                title: "脈拍の推移",
                subtitle: usesRawPoints ? "1 回ごとの測定値" : aggregationUnit.title
            ) {
                Chart(pulsePoints) { point in
                    LineMark(
                        x: .value("日付", point.date),
                        y: .value("脈拍", point.pulse ?? 0)
                    )
                    .foregroundStyle(Theme.pulse)
                    PointMark(
                        x: .value("日付", point.date),
                        y: .value("脈拍", point.pulse ?? 0)
                    )
                    .foregroundStyle(Theme.pulse)
                    .symbolSize(24)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { dateAxis }
                .frame(height: 160)
            }
        }
    }

    // MARK: - 横軸

    /// 期間の長さに応じて目盛りの間隔と表記を変える。
    private var dateAxis: some AxisContent {
        let stride = axisStride
        return AxisMarks(values: .stride(by: stride.component, count: stride.count)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(
                        stride.component == .day
                        ? AppFormatter.shortDate.string(from: date)
                        : AppFormatter.monthLabel.string(from: date)
                    )
                }
            }
        }
    }

    private var axisStride: (component: Calendar.Component, count: Int) {
        switch period.dayCount(fallbackStart: allSamples.first?.measuredAt) {
        case ..<10: return (.day, 2)
        case ..<25: return (.day, 5)
        case ..<46: return (.day, 7)
        case ..<130: return (.month, 1)
        case ..<400: return (.month, 2)
        default: return (.month, 6)
        }
    }

    // MARK: - 集計

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(series.slot == nil ? "この期間のまとめ" : "「\(series.title)」のまとめ")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(
                    title: "平均（上）",
                    value: statistics.averageSystolic.map(AppFormatter.decimal) ?? "--",
                    unit: "mmHg",
                    caption: rangeText(min: statistics.minSystolic, max: statistics.maxSystolic),
                    systemImage: "arrow.up.circle.fill",
                    tint: Theme.systolic
                )
                StatTile(
                    title: "平均（下）",
                    value: statistics.averageDiastolic.map(AppFormatter.decimal) ?? "--",
                    unit: "mmHg",
                    caption: rangeText(min: statistics.minDiastolic, max: statistics.maxDiastolic),
                    systemImage: "arrow.down.circle.fill",
                    tint: Theme.diastolic
                )
                StatTile(
                    title: "測定回数",
                    value: "\(statistics.count)",
                    unit: "回",
                    caption: statistics.averagePulse.map { "平均脈拍 \(AppFormatter.decimal($0)) bpm" },
                    systemImage: "list.bullet.rectangle"
                )
                StatTile(
                    title: "目標達成率",
                    value: statistics.withinTargetRatio.map(AppFormatter.percent) ?? "--",
                    caption: "高血圧域 \(statistics.hypertensiveRatio.map(AppFormatter.percent) ?? "--")",
                    systemImage: "target",
                    tint: Theme.categoryNormal
                )
            }
        }
    }

    private func rangeText(min: Int?, max: Int?) -> String? {
        guard let min, let max else { return nil }
        return "最低 \(min) / 最高 \(max)"
    }

    // MARK: - 分類の内訳

    private struct CategoryCount: Identifiable {
        var category: BPCategory
        var count: Int

        var id: Int { category.rawValue }
    }

    private var distributionSection: some View {
        let entries = BPCategory.allCases
            .map { CategoryCount(category: $0, count: statistics.categoryCounts[$0] ?? 0) }
            .filter { $0.count > 0 }

        return ChartCard(title: "判定の内訳", subtitle: "\(settings.standard.title)の基準") {
            Chart(entries) { entry in
                BarMark(
                    x: .value("件数", entry.count),
                    y: .value("判定", entry.category.title)
                )
                .foregroundStyle(entry.category.color)
                .annotation(position: .trailing) {
                    Text("\(entry.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(entries.count) * 34 + 20)
        }
    }

    // MARK: - 時間帯ごとの平均

    private struct SlotAverage: Identifiable {
        var slot: MeasurementSlot
        var pair: BPStatistics.AveragePair?

        var id: String { slot.rawValue }
    }

    @ViewBuilder
    private var slotSection: some View {
        let averages: [SlotAverage] = [.morning, .noon, .evening].map {
            SlotAverage(slot: $0, pair: slotAverage(for: $0))
        }

        if averages.contains(where: { $0.pair != nil }) {
            ChartCard(title: "時間帯ごとの平均", subtitle: "この期間のすべての記録から計算しています") {
                VStack(spacing: 12) {
                    ForEach(averages) { entry in
                        slotRow(slot: entry.slot, pair: entry.pair)
                    }

                    if let difference = periodStatistics.morningEveningDifference {
                        HStack {
                            Text("朝晩の差（上）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(AppFormatter.signed(difference)) mmHg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(abs(difference) >= 15 ? Theme.categoryHigh : .primary)
                        }
                    }
                }
            }
        }
    }

    private func slotAverage(for slot: MeasurementSlot) -> BPStatistics.AveragePair? {
        let samples = periodSamples.filter { $0.slot == slot }
        guard !samples.isEmpty else { return nil }
        return BPStatistics.AveragePair(
            systolic: Double(samples.map(\.systolic).reduce(0, +)) / Double(samples.count),
            diastolic: Double(samples.map(\.diastolic).reduce(0, +)) / Double(samples.count)
        )
    }

    private func slotRow(slot: MeasurementSlot, pair: BPStatistics.AveragePair?) -> some View {
        HStack {
            Label(slot.title, systemImage: slot.symbolName)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .frame(width: 68, alignment: .leading)

            if let pair {
                Text("\(Int(pair.systolic.rounded())) / \(Int(pair.diastolic.rounded()))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.brand)
                Text("mmHg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                CategoryBadge(
                    category: BPCategory.classify(
                        systolic: Int(pair.systolic.rounded()),
                        diastolic: Int(pair.diastolic.rounded()),
                        standard: settings.standard
                    ),
                    compact: true
                )
            } else {
                Text("記録なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

/// グラフを囲む共通のカード。
struct ChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .cardStyle(padding: 14)
    }
}
