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
    @State private var showsPhotoSourceDialog = false

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
            .background(Theme.pageBackground)
            .navigationTitle("うちの血圧記録")
        }
        .addRecordFlow(route: $route, defaultArm: settings.defaultArm)
        .overlay {
            if showsPhotoSourceDialog {
                PhotoSourceDialog(
                    onCamera: {
                        showsPhotoSourceDialog = false
                        route = .camera
                    },
                    onLibrary: {
                        showsPhotoSourceDialog = false
                        route = .photoLibrary
                    },
                    onCancel: {
                        showsPhotoSourceDialog = false
                    }
                )
            }
        }
    }

    // MARK: - 最新の記録

    @ViewBuilder
    private var latestCard: some View {
        if let latest = records.first {
            let category = latest.category(standard: settings.standard)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("最新の記録", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                    Spacer()
                    Text(AppFormatter.dateTime.string(from: latest.measuredAt))
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.85))

                HStack(alignment: .bottom) {
                    BPReadingView(
                        systolic: latest.systolic,
                        diastolic: latest.diastolic,
                        pulse: latest.pulse,
                        style: .onBrand
                    )
                    Spacer()
                    Text(category.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                        .foregroundStyle(.white)
                }

                Text(category.advice)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let trend = BPAggregator.trend(records.map(\.sample), days: 7) {
                    Label {
                        Text("先週比 \(AppFormatter.signed(trend)) mmHg（上の平均）")
                    } icon: {
                        Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.brandGradientDiagonal,
                in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            )
            .shadow(color: Theme.brandDeep.opacity(0.25), radius: 12, x: 0, y: 6)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            AppMarkView(size: 84)
                .shadow(color: Theme.brandDeep.opacity(0.28), radius: 10, x: 0, y: 5)
            Text("最初の記録をはじめましょう")
                .font(.headline)
            Text("血圧計の表示を撮影すると、上・下・脈拍を自動で読み取ります。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .cardStyle(padding: 0, alignment: .center)
    }

    // MARK: - 記録ボタン

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showsPhotoSourceDialog = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                    Text("写真から記録")
                }
            }
            .buttonStyle(.brand)

            Button {
                route = .manual
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                    Text("手入力")
                }
            }
            .buttonStyle(.brandSecondary)
        }
    }

    // MARK: - 直近 7 日のまとめ

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("直近 7 日")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(
                    title: "平均",
                    value: averageText,
                    unit: "mmHg",
                    caption: "上 / 下",
                    systemImage: "chart.bar.fill",
                    tint: Theme.brand
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
                    tint: Theme.categoryNormal
                )
                StatTile(
                    title: "平均脈拍",
                    value: statistics.averagePulse.map(AppFormatter.decimal) ?? "--",
                    unit: "bpm",
                    systemImage: "heart.fill",
                    tint: Theme.pulse
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
            sectionTitle("直近 2 週間の推移")

            Chart {
                ForEach(dailyAverages) { day in
                    LineMark(
                        x: .value("日付", day.date),
                        y: .value("血圧", day.systolic),
                        series: .value("種類", "上")
                    )
                    .foregroundStyle(Theme.systolic)
                    .symbol(.circle)

                    LineMark(
                        x: .value("日付", day.date),
                        y: .value("血圧", day.diastolic),
                        series: .value("種類", "下")
                    )
                    .foregroundStyle(Theme.diastolic)
                    .symbol(.circle)
                }

                RuleMark(y: .value("目標（上）", settings.targetSystolic))
                    .foregroundStyle(Theme.systolic.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(y: .value("目標（下）", settings.targetDiastolic))
                    .foregroundStyle(Theme.diastolic.opacity(0.35))
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
            .cardStyle(padding: 12)
        }
    }

    // MARK: - 朝晩の比較

    @ViewBuilder
    private var slotComparison: some View {
        if statistics.morningAverage != nil || statistics.eveningAverage != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("朝と晩の平均")

                HStack(spacing: 12) {
                    slotTile(title: "朝", pair: statistics.morningAverage, symbol: "sunrise.fill", tint: Theme.categoryHigh)
                    slotTile(title: "晩", pair: statistics.eveningAverage, symbol: "moon.stars.fill", tint: Theme.diastolic)
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
                    .foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("次のリマインダー・\(reminders.schedule.summaryText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppFormatter.dateTime.string(from: next))
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                if reminders.authorizationStatus != .authorized {
                    Text("通知はオフです")
                        .font(.caption2)
                        .foregroundStyle(Theme.categoryHigh)
                }
            }
            .cardStyle(padding: 14)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
