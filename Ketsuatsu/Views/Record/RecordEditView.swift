import SwiftData
import SwiftUI
import UIKit

/// 記録の新規作成・編集フォーム。写真から読み取った場合はその結果も表示する。
struct RecordEditView: View {
    enum Mode {
        case create(BPDraft)
        case edit(BPRecord)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    private let mode: Mode
    private let ocrResult: BPParseResult?
    private let recognizedLines: [String]

    @State private var draft: BPDraft
    @State private var slotEditedManually = false
    @State private var showsDeleteConfirmation = false
    @State private var showsRecognizedText = false
    @State private var isSaving = false

    init(mode: Mode, ocrResult: BPParseResult? = nil, recognizedLines: [String] = []) {
        self.mode = mode
        self.ocrResult = ocrResult
        self.recognizedLines = recognizedLines
        switch mode {
        case .create(let draft):
            _draft = State(initialValue: draft)
        case .edit(let record):
            _draft = State(initialValue: BPDraft(record: record))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let ocrResult {
                    ocrSection(ocrResult)
                }
                valuesSection
                timingSection
                detailSection
                if let photoData = draft.photoData, let image = UIImage(data: photoData) {
                    photoSection(image)
                }
                if isEditing {
                    deleteSection
                }
            }
            .navigationTitle(isEditing ? "記録を編集" : "血圧を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(!draft.isValid || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("この記録を削除しますか？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive, action: delete)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("削除すると元に戻せません。")
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - セクション

    @ViewBuilder
    private func ocrSection(_ result: BPParseResult) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: result.hasBloodPressure ? "text.viewfinder" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(result.hasBloodPressure ? Theme.brand : Theme.categoryHigh)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.hasBloodPressure ? "写真から読み取りました" : "うまく読み取れませんでした")
                        .font(.subheadline.weight(.semibold))
                    Text(result.hasBloodPressure
                         ? "\(result.explanation)（確度 \(AppFormatter.percent(result.confidence))）"
                         : "お手数ですが手で入力してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if result.confidence < 0.85 && result.hasBloodPressure {
                Label("値が正しいか確認してください。", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(Theme.categoryHigh)
            }

            if !recognizedLines.isEmpty {
                DisclosureGroup("読み取った文字を見る", isExpanded: $showsRecognizedText) {
                    Text(recognizedLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
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
                            standard: settings.standard
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
            Text("\(settings.standard.title)の基準で判定しています。")
        }
    }

    private var timingSection: some View {
        Section("測定した日時") {
            DatePicker(
                "日時",
                selection: $draft.measuredAt,
                in: ...Date().addingTimeInterval(60 * 60),
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.locale, AppFormatter.japanese)
            .onChange(of: draft.measuredAt) { _, newValue in
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

    private func photoSection(_ image: UIImage) -> some View {
        Section("読み取りに使った写真") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(role: .destructive) {
                draft.photoData = nil
            } label: {
                Label("写真を削除", systemImage: "trash")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("この記録を削除", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - 操作

    private func save() {
        guard draft.isValid, !isSaving else { return }
        isSaving = true
        Task {
            switch mode {
            case .create:
                await RecordService.create(from: draft, context: modelContext, settings: settings)
            case .edit(let record):
                await RecordService.update(record, with: draft, context: modelContext, settings: settings)
            }
            isSaving = false
            dismiss()
        }
    }

    private func delete() {
        guard case .edit(let record) = mode else { return }
        Task {
            await RecordService.delete(record, context: modelContext)
            dismiss()
        }
    }
}
