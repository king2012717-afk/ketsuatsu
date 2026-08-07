import SwiftUI

/// 測定値・日時・詳細の入力欄。
/// 1 件ずつの記録画面と、まとめて記録するときの編集画面で共通に使う。
struct RecordFormSections: View {
    @Binding var draft: BPDraft
    var standard: BPStandard

    @State private var slotEditedManually = false

    var body: some View {
        Group {
            valuesSection
            timingSection
            detailSection
        }
    }

    private var valuesSection: some View {
        Section {
            NumberFieldRow(
                title: "収縮期（上）",
                unit: "mmHg",
                systemImage: "arrow.up.circle.fill",
                tint: Theme.systolic,
                range: BPValueRange.systolic,
                startValue: 120,
                value: $draft.systolic
            )
            NumberFieldRow(
                title: "拡張期（下）",
                unit: "mmHg",
                systemImage: "arrow.down.circle.fill",
                tint: Theme.diastolic,
                range: BPValueRange.diastolic,
                startValue: 80,
                value: $draft.diastolic
            )
            NumberFieldRow(
                title: "脈拍",
                unit: "bpm",
                systemImage: "heart.fill",
                tint: Theme.pulse,
                range: BPValueRange.pulse,
                startValue: 70,
                value: $draft.pulse
            )

            if let systolic = draft.systolic, let diastolic = draft.diastolic, draft.isValid {
                HStack {
                    Text("判定")
                    Spacer()
                    CategoryBadge(
                        category: BPCategory.classify(
                            systolic: systolic,
                            diastolic: diastolic,
                            standard: standard
                        )
                    )
                }
            } else if let message = draft.validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("測定値")
        } footer: {
            Text("\(standard.title)の基準で判定しています。")
        }
    }

    private var timingSection: some View {
        Section {
            DatePicker(
                "日時",
                selection: $draft.measuredAt,
                in: ...Date().addingTimeInterval(60 * 60),
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.locale, AppFormatter.japanese)
            .onChange(of: draft.measuredAt) { _, newValue in
                // 日時を手で直したら、それは撮影日時そのままではなくなる。
                draft.usesPhotoCaptureDate = false
                guard !slotEditedManually else { return }
                draft.slot = MeasurementSlot.inferred(from: newValue)
            }

            Picker("時間帯", selection: $draft.slot) {
                ForEach(MeasurementSlot.allCases) { slot in
                    Text(slot.title).tag(slot)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.slot) { _, _ in slotEditedManually = true }
        } header: {
            Text("測定した日時")
        } footer: {
            if draft.usesPhotoCaptureDate {
                Label("写真の撮影日時を使っています。", systemImage: "camera.metering.center.weighted")
                    .font(.caption)
                    .foregroundStyle(Theme.brand)
            }
        }
    }

    private var detailSection: some View {
        Section("詳細") {
            Picker("測定した腕", selection: $draft.arm) {
                ForEach(MeasurementArm.allCases) { arm in
                    Text(arm.title).tag(arm)
                }
            }
            Toggle(isOn: $draft.tookMedication) {
                Label("薬を飲んだ", systemImage: "pills.fill")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("メモ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("体調や気づいたこと", text: $draft.note, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }
}
