import SwiftUI
import UIKit
import UserNotifications

/// 測定リマインダーの一覧と編集。
struct ReminderListView: View {
    @Environment(ReminderStore.self) private var store

    @State private var editingReminder: ReminderItem?
    @State private var isAdding = false

    var body: some View {
        List {
            if store.authorizationStatus != .authorized && store.authorizationStatus != .provisional {
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

            Section {
                if store.reminders.isEmpty {
                    Text("リマインダーがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.reminders) { reminder in
                        Button {
                            editingReminder = reminder
                        } label: {
                            row(for: reminder)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        Task { await store.remove(at: offsets) }
                    }
                }
            } footer: {
                Text("朝は起床後 1 時間以内・排尿後、晩は就寝前に測るのが家庭血圧の基本です。")
            }
        }
        .navigationTitle("リマインダー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            ReminderEditView(reminder: ReminderItem(hour: 7, minute: 0)) { reminder in
                Task { await store.add(reminder) }
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditView(reminder: reminder) { updated in
                Task { await store.update(updated) }
            } onDelete: {
                Task { await store.remove(id: reminder.id) }
            }
        }
        .task {
            await store.refreshAuthorizationStatus()
        }
    }

    private func row(for reminder: ReminderItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.slot.symbolName)
                .foregroundStyle(reminder.isEnabled ? Theme.brand : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.timeText)
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(reminder.isEnabled ? .primary : .secondary)
                Text("\(reminder.weekdayText)・\(reminder.slot.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { reminder.isEnabled },
                set: { newValue in Task { await store.setEnabled(newValue, for: reminder.id) } }
            ))
            .labelsHidden()
        }
    }
}

/// リマインダー 1 件の編集フォーム。
struct ReminderEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reminder: ReminderItem
    private let onSave: (ReminderItem) -> Void
    private let onDelete: (() -> Void)?

    init(
        reminder: ReminderItem,
        onSave: @escaping (ReminderItem) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        _reminder = State(initialValue: reminder)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = reminder.hour
                components.minute = reminder.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminder.hour = components.hour ?? reminder.hour
                reminder.minute = components.minute ?? reminder.minute
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

                Section("曜日") {
                    ForEach(1...7, id: \.self) { weekday in
                        Button {
                            toggle(weekday)
                        } label: {
                            HStack {
                                Text(weekdayName(weekday))
                                Spacer()
                                if reminder.weekdays.contains(weekday) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.brand)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("種類") {
                    Picker("時間帯", selection: $reminder.slot) {
                        ForEach(MeasurementSlot.allCases) { slot in
                            Text(slot.title).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("このリマインダーを削除")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle("リマインダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = reminder
                        if updated.weekdays.isEmpty { updated.weekdays = Set(1...7) }
                        updated.isEnabled = true
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggle(_ weekday: Int) {
        if reminder.weekdays.contains(weekday) {
            reminder.weekdays.remove(weekday)
        } else {
            reminder.weekdays.insert(weekday)
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let names = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
        return names[(weekday - 1) % 7]
    }
}
