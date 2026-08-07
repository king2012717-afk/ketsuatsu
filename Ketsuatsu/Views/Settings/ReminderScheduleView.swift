import SwiftUI
import UIKit
import UserNotifications

/// 測定リマインダーの設定。
///
/// 「まとめて」で毎日同じ時刻に通知するか、「曜日ごと」で曜日別に時刻を変えるかを選べる。
/// どちらのモードでも 1 日に何回でも時刻を追加できる。
struct ReminderScheduleView: View {
    @Environment(ReminderStore.self) private var store

    @State private var selectedWeekday = Calendar.current.component(.weekday, from: Date())
    @State private var editingTime: EditingTime?
    @State private var showsCopyConfirmation = false

    /// 編集中の時刻。`weekday` が nil なら「まとめて」の時刻。
    private struct EditingTime: Identifiable {
        var time: ReminderTime
        var weekday: Int?
        var isNew: Bool

        var id: UUID { time.id }
    }

    private var schedule: ReminderSchedule { store.schedule }

    /// いま編集している対象の曜日（「まとめて」のときは nil）。
    private var editingWeekday: Int? {
        schedule.mode == .perWeekday ? selectedWeekday : nil
    }

    var body: some View {
        List {
            if !store.isAuthorized {
                authorizationSection
            }

            enabledSection

            if schedule.isEnabled {
                modeSection
                if schedule.mode == .perWeekday {
                    weekdaySection
                }
                timesSection
                presetSection
            }
        }
        .navigationTitle("リマインダー")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTime) { editing in
            editSheet(for: editing)
        }
        .task {
            await store.refreshAuthorizationStatus()
        }
    }

    private func editSheet(for editing: EditingTime) -> some View {
        let deleteAction: (() -> Void)? = editing.isNew ? nil : {
            store.modify { $0.removeTime(id: editing.time.id, weekday: editing.weekday) }
        }

        return ReminderTimeEditView(
            time: editing.time,
            isNew: editing.isNew,
            onSave: { updated in
                store.modify { schedule in
                    if editing.isNew {
                        schedule.addTime(updated, weekday: editing.weekday)
                    } else {
                        schedule.updateTime(updated, weekday: editing.weekday)
                    }
                }
            },
            onDelete: deleteAction
        )
    }

    // MARK: - 通知の許可

    private var authorizationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("通知が許可されていません", systemImage: "bell.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.categoryHigh)
                Text("リマインダーを受け取るには通知を許可してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.authorizationStatus == .denied {
                    Button("設定 App を開く") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .font(.callout)
                } else {
                    Button("通知を許可する") {
                        Task { await store.requestAuthorization() }
                    }
                    .font(.callout)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - オン / オフ

    private var enabledSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { schedule.isEnabled },
                set: { newValue in store.modify { $0.isEnabled = newValue } }
            )) {
                Label("測定リマインダー", systemImage: "bell.badge.fill")
            }
        } footer: {
            if schedule.isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(footerSummary)
                    if store.exceedsNotificationLimit {
                        Text("iOS の上限（\(ReminderStore.notificationLimit) 件）を超えているため、遅い時刻の通知は登録されません。回数を減らしてください。")
                            .foregroundStyle(Theme.categoryGrade2)
                    }
                }
            }
        }
    }

    private var footerSummary: String {
        let weekly = schedule.weeklyCount
        guard weekly > 0 else { return "通知する時刻がありません。" }
        switch schedule.mode {
        case .uniform:
            return "毎日 \(schedule.times(forEditing: nil).filter(\.isEnabled).count) 回・週 \(weekly) 回の通知を登録します。"
        case .perWeekday:
            return "週 \(weekly) 回の通知を登録します。"
        }
    }

    // MARK: - 設定方法

    private var modeSection: some View {
        Section {
            Picker("設定方法", selection: Binding(
                get: { schedule.mode },
                set: { newValue in store.modify { $0.switchMode(to: newValue) } }
            )) {
                ForEach(ReminderSchedule.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("設定方法")
        } footer: {
            Text(schedule.mode.footnote)
        }
    }

    // MARK: - 曜日の選択

    private var weekdaySection: some View {
        Section {
            Picker("曜日", selection: $selectedWeekday) {
                ForEach(ReminderSchedule.allWeekdays, id: \.self) { weekday in
                    Text(ReminderSchedule.weekdayName(weekday)).tag(weekday)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                ForEach(ReminderSchedule.allWeekdays, id: \.self) { weekday in
                    let count = schedule.times(for: weekday).filter(\.isEnabled).count
                    Text(count > 0 ? "\(count)回" : "-")
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(weekday == selectedWeekday ? Theme.brand : .secondary)
                }
            }
        } footer: {
            Text("曜日を選ぶと、その曜日の時刻を編集できます。")
        }
    }

    // MARK: - 時刻の一覧

    private var timesSection: some View {
        let times = schedule.times(forEditing: editingWeekday)

        return Section {
            if times.isEmpty {
                Text("時刻がありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(times) { time in
                    timeRow(time)
                }
            }

            Button {
                editingTime = EditingTime(
                    time: schedule.suggestedNewTime(for: editingWeekday),
                    weekday: editingWeekday,
                    isNew: true
                )
            } label: {
                Label("時刻を追加", systemImage: "plus.circle.fill")
            }

            if schedule.mode == .perWeekday {
                Button {
                    showsCopyConfirmation = true
                } label: {
                    Label("この曜日の時刻を他の曜日にも反映", systemImage: "doc.on.doc")
                }
                .disabled(times.isEmpty)
                .confirmationDialog(
                    "\(ReminderSchedule.weekdayName(selectedWeekday, short: false))の時刻をどこにコピーしますか？",
                    isPresented: $showsCopyConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("すべての曜日") { copyTimes(to: ReminderSchedule.allWeekdays) }
                    Button("平日（月〜金）") { copyTimes(to: [2, 3, 4, 5, 6]) }
                    Button("土日") { copyTimes(to: [1, 7]) }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("コピー先の時刻は置き換えられます。")
                }
            }
        } header: {
            Text(timesSectionTitle)
        } footer: {
            Text("朝は起床後 1 時間以内・排尿後、晩は就寝前に測るのが家庭血圧の基本です。")
        }
    }

    private var timesSectionTitle: String {
        switch schedule.mode {
        case .uniform: return "通知する時刻（毎日）"
        case .perWeekday: return "\(ReminderSchedule.weekdayName(selectedWeekday, short: false))の時刻"
        }
    }

    private func timeRow(_ time: ReminderTime) -> some View {
        let weekday = editingWeekday

        return Button {
            editingTime = EditingTime(time: time, weekday: weekday, isNew: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: time.slot.symbolName)
                    .foregroundStyle(time.isEnabled ? Theme.brand : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(time.timeText)
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(time.isEnabled ? .primary : .secondary)
                    Text(time.slot.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { time.isEnabled },
                    set: { newValue in
                        store.modify { $0.setEnabled(newValue, timeID: time.id, weekday: weekday) }
                    }
                ))
                .labelsHidden()
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.modify { $0.removeTime(id: time.id, weekday: weekday) }
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - かんたん設定

    private var presetSection: some View {
        Section {
            ForEach(ReminderPreset.allCases) { preset in
                Button {
                    store.modify { $0.apply(preset) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                            Text(preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(Theme.brand)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("かんたん設定")
        } footer: {
            Text(
                schedule.mode == .uniform
                ? "選ぶと、いまの時刻の設定を置き換えます。"
                : "選ぶと、すべての曜日の時刻を置き換えます。"
            )
        }
    }

    private func copyTimes(to weekdays: [Int]) {
        store.modify { $0.copyTimes(from: selectedWeekday, to: weekdays) }
    }
}

/// 時刻 1 件の編集フォーム。
struct ReminderTimeEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var time: ReminderTime
    @State private var slotEditedManually = false

    private let isNew: Bool
    private let onSave: (ReminderTime) -> Void
    private let onDelete: (() -> Void)?

    init(
        time: ReminderTime,
        isNew: Bool,
        onSave: @escaping (ReminderTime) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        _time = State(initialValue: time)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                time.hour = components.hour ?? time.hour
                time.minute = components.minute ?? time.minute
                // 時間帯を手で変えていなければ、時刻に合わせて自動で切り替える。
                if !slotEditedManually {
                    time.slot = MeasurementSlot.inferred(fromHour: time.hour)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("時刻", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .environment(\.locale, AppFormatter.japanese)
                }

                Section {
                    // 手で選んだときだけ自動判定を止める（時刻の変更による切り替えでは止めない）。
                    Picker("時間帯", selection: Binding(
                        get: { time.slot },
                        set: { newValue in
                            time.slot = newValue
                            slotEditedManually = true
                        }
                    )) {
                        ForEach(MeasurementSlot.allCases) { slot in
                            Text(slot.title).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("時間帯")
                } footer: {
                    Text("通知の文面と、記録するときの初期値に使います。")
                }

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("この時刻を削除")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "時刻を追加" : "時刻を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = time
                        updated.isEnabled = true
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
