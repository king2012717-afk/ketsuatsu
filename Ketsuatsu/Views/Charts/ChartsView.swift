import Charts
import SwiftData
import SwiftUI
import UIKit

/// グラフと集計。期間を切り替えながら推移と傾向を確認する。
struct ChartsView: View {
    @Environment(AppSettings.self) private var settings

    @Query(sort: \BPRecord.measuredAt, order: .forward) private var records: [BPRecord]

    @State private var period: PeriodFilter = .month1
    @State private var showsDailyAverage = true

    private var samples: [BPSample] {
        BPAggregator.filter(records.map(\.sample), days: period.days)
    }

    private var dailyAverages: [DailyAverage] {
        BPAggregator.dailyAverages(samples)
    }

    private var statistics: BPStatistics {
        BPStatistics.compute(
            samples,
            targetSystolic: settings.targetSystolic,
            targetDiastolic: settings.targetDiastolic,
            standard: settings.standard
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    periodPicker

                    if samples.isEmpty {
                        ContentUnavailableView(
                            "データがありません",
                            systemImage: "chart.xyaxis.line",
                            description: Text("この期間の記録がまだありません。")
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

    // MARK: - 期間

    private var periodPicker: some View {
        VStack(spacing: 8) {
            Picker("期間", selection: $period) {
                ForEach(PeriodFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Toggle("日ごとの平均で表示", isOn: $showsDailyAverage)
                .font(.caption)
                .toggleStyle(.switch)
        }
    }

    // MARK: - 血圧グラフ

    private var pressureChartSection: some View {
        ChartCard(title: "血圧の推移", subtitle: "点線は目標値（\(settings.targetSystolic)/\(settings.targetDiastolic)）") {
            Chart {
                if showsDailyAverage {
                    ForEach(dailyAverages) { day in
                        LineMark(
                            x: .value("日付", day.date),
                            y: .value("血圧", day.systolic),
                            series: .value("種類", "上")
                        )
                        .foregroundStyle(by: .value("種類", "上"))
                        LineMark(
                            x: .value("日付", day.date),
                            y: .value("血圧", day.diastolic),
                            series: .value("種類", "下")
                        )
                        .foregroundStyle(by: .value("種類", "下"))
                        PointMark(
                            x: .value("日付", day.date),
                            y: .value("血圧", day.systolic)
                        )
                        .foregroundStyle(by: .value("種類", "上"))
                        .symbolSize(28)
                        PointMark(
                            x: .value("日付", day.date),
                            y: .value("血圧", day.diastolic)
                        )
                        .foregroundStyle(by: .value("種類", "下"))
                        .symbolSize(28)
                    }
                } else {
                    ForEach(samples) { sample in
                        PointMark(
                            x: .value("日時", sample.measuredAt),
                            y: .value("血圧", sample.systolic)
                        )
                        .foregroundStyle(by: .value("種類", "上"))
                        .symbolSize(30)
                        PointMark(
                            x: .value("日時", sample.measuredAt),
                            y: .value("血圧", sample.diastolic)
                        )
                        .foregroundStyle(by: .value("種類", "下"))
                        .symbolSize(30)
                    }
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
            .frame(height: 240)
        }
    }

    // MARK: - 脈拍グラフ

    @ViewBuilder
    private var pulseChartSection: some View {
        let pulseData = dailyAverages.filter { $0.pulse != nil }
        if !pulseData.isEmpty {
            ChartCard(title: "脈拍の推移", subtitle: "日ごとの平均") {
                Chart(pulseData) { day in
                    BarMark(
                        x: .value("日付", day.date, unit: .day),
                        y: .value("脈拍", day.pulse ?? 0)
                    )
                    .foregroundStyle(Theme.brandGradient)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            }
        }
    }

    // MARK: - 集計

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この期間のまとめ")
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

    // MARK: - 朝晩の比較

    @ViewBuilder
    private var slotSection: some View {
        if statistics.morningAverage != nil || statistics.eveningAverage != nil {
            ChartCard(title: "朝と晩の平均", subtitle: "家庭血圧は朝晩それぞれの平均で判断します") {
                VStack(spacing: 12) {
                    slotRow(title: "朝", pair: statistics.morningAverage, tint: Theme.categoryHigh)
                    slotRow(title: "晩", pair: statistics.eveningAverage, tint: Theme.diastolic)

                    if let difference = statistics.morningEveningDifference {
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

    private func slotRow(title: String, pair: BPStatistics.AveragePair?, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 32, alignment: .leading)
            if let pair {
                Text("\(Int(pair.systolic.rounded())) / \(Int(pair.diastolic.rounded()))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
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
