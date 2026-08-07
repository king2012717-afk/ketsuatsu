import Charts
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// ホーム。最新の記録・直近のまとめ・記録ボタンをまとめた画面。
struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ReminderStore.self) private var reminders

    @Query(sort: \BPRecord.measuredAt, order: .reverse) private var records: [BPRecord]

    @State private var route: AddRecordRoute?

    private var recentSamples: [BPSample] {
        BPAggregator.filter(records.map(\.sample), days: 7)
    }

    private var statistics: BPStatistics {
        BPStatistics.compute(
            recentSamples,
            targetSystolic: settings.targetSystolic,
            targetDiastolic: settings.targetDiastolic,
            standard: settings.standard
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    latestCard
                    actionButtons
                    if !recentSamples.isEmpty {
                        summarySection
                        miniChart
                        slotComparison
                    }
                    reminderCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("血圧ノート")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddRecordMenu(route: $route) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
        }
        .addRecordFlow(route: $route, defaultArm: settings.defaultArm)
    }

    // MARK: - 最新の記録

    @ViewBuilder
    private var latestCard: some View {
        if let latest = records.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("最新の記録", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(AppFormatter.dateTime.string(from: latest.measuredAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom) {
                    BPReadingView(
                        systolic: latest.systolic,
                        diastolic: latest.diastolic,
                        pulse: latest.pulse
                    )
                    Spacer()
                    CategoryBadge(category: latest.category(standard: settings.standard))
                }

                Text(latest.category(standard: settings.standard).advice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let trend = BPAggregator.trend(records.map(\.sample), days: 7) {
                    Label {
                        Text("先週比 \(AppFormatter.signed(trend)) mmHg（上の平均）")
                    } icon: {
                        Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(.caption)
                    .foregroundStyle(trend > 0 ? .orange : .green)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text("最初の記録をはじめましょう")
                .font(.headline)
            Text("血圧計の表示を撮影すると、上・下・脈拍を自動で読み取ります。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 記録ボタン

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                route = CameraPicker.isAvailable ? .camera : .photoLibrary
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                    Text("写真から記録")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                route = .manual
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                    Text("手入力")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 直近 7 日のまとめ

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("直近 7 日")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(
                    title: "平均",
                    value: averageText,
                    unit: "mmHg",
                    caption: "上 / 下",
                    systemImage: "chart.bar.fill"
                )
                StatTile(
                    title: "測定回数",
                    value: "\(statistics.count)",
                    unit: "回",
                    caption: "1 日あたり \(AppFormatter.decimal(Double(statistics.count) / 7.0)) 回",
                    systemImage: "list.bullet.rectangle"
                )
                StatTile(
                    title: "目標達成率",
                    value: statistics.withinTargetRatio.map(AppFormatter.percent) ?? "--",
                    caption: "目標 \(settings.targetSystolic)/\(settings.targetDiastolic) 以下",
                    systemImage: "target",
                    tint: .green
                )
                StatTile(
                    title: "平均脈拍",
                    value: statistics.averagePulse.map(AppFormatter.decimal) ?? "--",
                    unit: "bpm",
                    systemImage: "heart.fill",
                    tint: .pink
                )
            }
        }
    }

    private var averageText: String {
        guard let systolic = statistics.averageSystolic, let diastolic = statistics.averageDiastolic else {
            return "--"
        }
        return "\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))"
    }

    // MARK: - ミニグラフ

    private var miniChart: some View {
        let dailyAverages = BPAggregator.dailyAverages(BPAggregator.filter(records.map(\.sample), days: 14))

        return VStack(alignment: .leading, spacing: 8) {
            Text("直近 2 週間の推移")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(dailyAverages) { day in
                    LineMark(
                        x: .value("日付", day.date),
                        y: .value("収縮期", day.systolic),
                        series: .value("種類", "上")
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)

                    LineMark(
                        x: .value("日付", day.date),
                        y: .value("拡張期", day.diastolic),
                        series: .value("種類", "下")
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }

                RuleMark(y: .value("目標（上）", settings.targetSystolic))
                    .foregroundStyle(.red.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(y: .value("目標（下）", settings.targetDiastolic))
                    .foregroundStyle(.blue.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(AppFormatter.shortDate.string(from: date))
                        }
                    }
                }
            }
            .frame(height: 180)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 朝晩の比較

    @ViewBuilder
    private var slotComparison: some View {
        if statistics.morningAverage != nil || statistics.eveningAverage != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("朝と晩の平均")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    slotTile(title: "朝", pair: statistics.morningAverage, symbol: "sunrise.fill", tint: .orange)
                    slotTile(title: "晩", pair: statistics.eveningAverage, symbol: "moon.stars.fill", tint: .indigo)
                }

                if let difference = statistics.morningEveningDifference {
                    Text(morningSurgeText(difference))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func slotTile(title: String, pair: BPStatistics.AveragePair?, symbol: String, tint: Color) -> some View {
        StatTile(
            title: title,
            value: pair.map { "\(Int($0.systolic.rounded()))/\(Int($0.diastolic.rounded()))" } ?? "--",
            unit: "mmHg",
            systemImage: symbol,
            tint: tint
        )
    }

    private func morningSurgeText(_ difference: Double) -> String {
        if difference >= 15 {
            return "朝の血圧が晩より \(AppFormatter.decimal(difference)) mmHg 高めです。朝の高血圧は心血管リスクと関連するといわれています。"
        } else if difference <= -15 {
            return "晩の血圧が朝より \(AppFormatter.decimal(abs(difference))) mmHg 高めです。"
        }
        return "朝と晩の差は \(AppFormatter.decimal(abs(difference))) mmHg です。"
    }

    // MARK: - リマインダー

    @ViewBuilder
    private var reminderCard: some View {
        if let next = reminders.nextReminderDate {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("次のリマインダー")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppFormatter.dateTime.string(from: next))
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                if reminders.authorizationStatus != .authorized {
                    Text("通知はオフです")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
