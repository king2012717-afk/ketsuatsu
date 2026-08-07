import SwiftData
import SwiftUI
import UIKit

/// 記録の一覧。日付ごとにまとめて表示し、検索・絞り込み・CSV 書き出しができる。
struct HistoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BPRecord.measuredAt, order: .reverse) private var records: [BPRecord]

    @State private var route: AddRecordRoute?
    @State private var editingRecord: BPRecord?
    @State private var slotFilter: SlotFilter = .all
    @State private var periodFilter: PeriodFilter = .month3
    @State private var searchText = ""
    @State private var exportedFile: ExportedFile?
    @State private var exportError: String?

    private enum SlotFilter: String, CaseIterable, Identifiable {
        case all, morning, noon, evening

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "すべて"
            case .morning: return "朝"
            case .noon: return "昼"
            case .evening: return "晩"
            }
        }

        var slot: MeasurementSlot? {
            switch self {
            case .all: return nil
            case .morning: return .morning
            case .noon: return .noon
            case .evening: return .evening
            }
        }
    }

    private struct ExportedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredRecords.isEmpty {
                    ContentUnavailableView {
                        Label("記録がありません", systemImage: "list.bullet.rectangle.portrait")
                    } description: {
                        Text(records.isEmpty ? "右上の＋から最初の記録を追加してください。" : "条件に合う記録がありません。")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("履歴")
            .searchable(text: $searchText, prompt: "メモや数値で検索")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddRecordMenu(route: $route) {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if slotFilter != .all || periodFilter != .month3 {
                    activeFilterBar
                }
            }
        }
        .addRecordFlow(route: $route, defaultArm: settings.defaultArm)
        .sheet(item: $editingRecord) { record in
            RecordEditView(mode: .edit(record))
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert(
            "書き出しに失敗しました",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - 一覧

    private var list: some View {
        List {
            ForEach(groupedRecords, id: \.date) { group in
                Section {
                    ForEach(group.records) { record in
                        Button {
                            editingRecord = record
                        } label: {
                            RecordRow(record: record, standard: settings.standard)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(record)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(AppFormatter.relativeDayHeader(for: group.date))
                        Spacer()
                        Text(dayAverageText(group.records))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var activeFilterBar: some View {
        HStack(spacing: 8) {
            Text("\(periodFilter.title)・\(slotFilter.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("条件をリセット") {
                slotFilter = .all
                periodFilter = .month3
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var filterMenu: some View {
        Menu {
            Picker("期間", selection: $periodFilter) {
                ForEach(PeriodFilter.standardCases) { period in
                    Text(period.title).tag(period)
                }
            }
            Picker("時間帯", selection: $slotFilter) {
                ForEach(SlotFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            Divider()
            Button {
                exportCSV()
            } label: {
                Label("CSV で書き出す", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - 絞り込み

    private var filteredRecords: [BPRecord] {
        var result = records

        if let days = periodFilter.days {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
            result = result.filter { $0.measuredAt >= start }
        }
        if let slot = slotFilter.slot {
            result = result.filter { $0.slot == slot }
        }
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            result = result.filter { record in
                record.note.localizedCaseInsensitiveContains(keyword)
                    || String(record.systolic).contains(keyword)
                    || String(record.diastolic).contains(keyword)
            }
        }
        return result
    }

    private struct DayGroup {
        let date: Date
        let records: [BPRecord]
    }

    private var groupedRecords: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecords) { calendar.startOfDay(for: $0.measuredAt) }
        return grouped
            .map { DayGroup(date: $0.key, records: $0.value.sorted { $0.measuredAt > $1.measuredAt }) }
            .sorted { $0.date > $1.date }
    }

    private func dayAverageText(_ records: [BPRecord]) -> String {
        guard !records.isEmpty else { return "" }
        let systolic = Double(records.map(\.systolic).reduce(0, +)) / Double(records.count)
        let diastolic = Double(records.map(\.diastolic).reduce(0, +)) / Double(records.count)
        return "平均 \(Int(systolic.rounded()))/\(Int(diastolic.rounded()))"
    }

    // MARK: - 操作

    private func delete(_ record: BPRecord) {
        Task { await RecordService.delete(record, context: modelContext) }
    }

    private func exportCSV() {
        do {
            let url = try CSVExporter.writeTemporaryFile(records: filteredRecords, standard: settings.standard)
            exportedFile = ExportedFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
