import SwiftData
import SwiftUI

/// 設定画面。目標値・判定基準・リマインダー・ヘルスケア連携・データ管理。
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ReminderStore.self) private var reminders
    @Environment(\.modelContext) private var modelContext

    @Query private var records: [BPRecord]

    @State private var isWorking = false
    @State private var message: AlertMessage?
    @State private var showsDeleteAllConfirmation = false
    @State private var exportedFile: ExportedFile?

    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private struct ExportedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker("判定の基準", selection: $settings.standard) {
                        ForEach(BPStandard.allCases) { standard in
                            Text(standard.title).tag(standard)
                        }
                    }
                    .onChange(of: settings.standard) { _, _ in
                        settings.resetTargetsToRecommended()
                    }
                } header: {
                    Text("判定")
                } footer: {
                    Text(settings.standard.footnote)
                }

                Section {
                    Stepper(value: $settings.targetSystolic, in: 90...180, step: 1) {
                        LabeledContent("収縮期（上）の目標", value: "\(settings.targetSystolic) mmHg")
                    }
                    Stepper(value: $settings.targetDiastolic, in: 50...120, step: 1) {
                        LabeledContent("拡張期（下）の目標", value: "\(settings.targetDiastolic) mmHg")
                    }
                    Button("推奨値に戻す") {
                        settings.resetTargetsToRecommended()
                    }
                    .font(.callout)
                } header: {
                    Text("目標値")
                } footer: {
                    Text("この値以下の記録を「目標達成」として集計します。治療中の方は主治医の指示に従ってください。")
                }

                Section {
                    NavigationLink {
                        ReminderScheduleView()
                    } label: {
                        LabeledContent("測定のお知らせ", value: reminders.schedule.summaryText)
                    }
                } header: {
                    Text("リマインダー")
                } footer: {
                    Text("1 日に何回でも設定できます。曜日ごとに時刻を変えることもできます。")
                }

                healthKitSection

                Section("入力の初期設定") {
                    Picker("測定する腕", selection: $settings.defaultArm) {
                        ForEach(MeasurementArm.allCases) { arm in
                            Text(arm.title).tag(arm)
                        }
                    }
                    Toggle("読み取りに使った写真も保存する", isOn: $settings.savePhotoWithRecord)
                }

                dataSection

                YutarouLabsRecommendedApps(
                    currentAppID: YutarouAppsConfig.currentAppID,
                    currentCategory: YutarouAppsConfig.currentCategory
                )

                Section {
                    HStack(spacing: 14) {
                        AppMarkView(size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("うちの血圧記録")
                                .font(.headline)
                            Text("バージョン \(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("このアプリについて")
                } footer: {
                    Text("このアプリは医療機器ではありません。記録と傾向の把握を助けるものであり、診断・治療の判断は医師にご相談ください。")
                }
            }
            .navigationTitle("設定")
            .disabled(isWorking)
            .alert(
                message?.title ?? "",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
                presenting: message
            ) { _ in
                Button("OK") { message = nil }
            } message: { info in
                Text(info.body)
            }
            .confirmationDialog(
                "すべての記録を削除しますか？",
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("すべて削除", role: .destructive) { deleteAll() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("\(records.count) 件の記録が削除されます。元に戻すことはできません。")
            }
            .sheet(item: $exportedFile) { file in
                ShareSheet(items: [file.url])
            }
        }
    }

    // MARK: - ヘルスケア

    @ViewBuilder
    private var healthKitSection: some View {
        @Bindable var settings = settings

        Section {
            if HealthKitService.shared.isAvailable {
                Toggle("記録をヘルスケアへ書き出す", isOn: $settings.healthKitSyncEnabled)
                    .onChange(of: settings.healthKitSyncEnabled) { _, isEnabled in
                        guard isEnabled else { return }
                        Task { await enableHealthKit() }
                    }

                Button {
                    Task { await importFromHealthKit() }
                } label: {
                    Label("ヘルスケアから取り込む", systemImage: "square.and.arrow.down")
                }

                Button {
                    Task { await exportPending() }
                } label: {
                    Label("未同期の記録を書き出す", systemImage: "square.and.arrow.up")
                }
                .disabled(!settings.healthKitSyncEnabled)
            } else {
                Text("この端末ではヘルスケアを利用できません。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("ヘルスケア連携")
        } footer: {
            Text("血圧（収縮期・拡張期）と脈拍を Apple のヘルスケア App とやり取りします。取り込みは過去 1 年ぶんが対象です。")
        }
    }

    // MARK: - データ

    private var dataSection: some View {
        Section("データ") {
            LabeledContent("記録件数", value: "\(records.count) 件")

            Button {
                exportCSV()
            } label: {
                Label("CSV で書き出す", systemImage: "square.and.arrow.up")
            }
            .disabled(records.isEmpty)

            Button(role: .destructive) {
                showsDeleteAllConfirmation = true
            } label: {
                Label("すべての記録を削除", systemImage: "trash")
            }
            .disabled(records.isEmpty)
        }
    }

    // MARK: - 表示用の値

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - 操作

    private func enableHealthKit() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
        } catch {
            settings.healthKitSyncEnabled = false
            message = AlertMessage(title: "連携できませんでした", body: error.localizedDescription)
        }
    }

    private func importFromHealthKit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await HealthKitService.shared.requestAuthorization()
            let since = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
            let summary = try await RecordService.importFromHealthKit(
                context: modelContext,
                since: since,
                settings: settings
            )
            message = AlertMessage(
                title: "取り込みが完了しました",
                body: "\(summary.imported) 件を追加しました。\(summary.skipped) 件は重複のため取り込みませんでした。"
            )
        } catch {
            message = AlertMessage(title: "取り込みに失敗しました", body: error.localizedDescription)
        }
    }

    private func exportPending() async {
        isWorking = true
        defer { isWorking = false }
        let count = await RecordService.exportPendingToHealthKit(context: modelContext, settings: settings)
        message = AlertMessage(title: "書き出しが完了しました", body: "\(count) 件をヘルスケアへ送りました。")
    }

    private func exportCSV() {
        do {
            let url = try CSVExporter.writeTemporaryFile(records: records, standard: settings.standard)
            exportedFile = ExportedFile(url: url)
        } catch {
            message = AlertMessage(title: "書き出しに失敗しました", body: error.localizedDescription)
        }
    }

    private func deleteAll() {
        Task {
            isWorking = true
            await RecordService.deleteAll(context: modelContext)
            isWorking = false
        }
    }
}
