import SwiftData
import SwiftUI
import UIKit

/// 複数の写真をまとめて読み取り、確認してから一括で記録する画面。
struct BatchImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @State private var model: BatchImportModel
    @State private var editingItemID: UUID?

    init(photos: [PickedPhoto], defaultArm: MeasurementArm) {
        _model = State(initialValue: BatchImportModel(photos: photos, defaultArm: defaultArm))
    }

    var body: some View {
        NavigationStack {
            List {
                if model.isAnalyzing {
                    progressSection
                }
                itemsSection
                if !model.isAnalyzing && model.failedCount > 0 {
                    hintSection
                }
            }
            .navigationTitle("まとめて記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("すべて選択") { model.selectAll() }
                        Button("すべて解除") { model.deselectAll() }
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .disabled(model.isAnalyzing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .sheet(item: Binding(
                get: { editingItemID.flatMap { id in model.items.first { $0.id == id } } },
                set: { editingItemID = $0?.id }
            )) { item in
                BatchItemEditView(draft: item.draft, standard: settings.standard) { updated in
                    model.update(updated, for: item.id)
                }
            }
            .task {
                await model.analyze()
            }
            .interactiveDismissDisabled(model.isSaving)
        }
    }

    // MARK: - 読み取りの進み具合

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: model.progress)
                    .tint(Theme.brand)
                Text("\(model.analyzedCount) / \(model.totalCount) 枚を読み取り中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 一覧

    private var itemsSection: some View {
        Section {
            ForEach(model.items) { item in
                row(for: item)
            }
        } header: {
            Text("読み取った内容")
        } footer: {
            Text("値をタップすると修正できます。チェックの付いたものだけが記録されます。")
        }
    }

    private func row(for item: BatchImportModel.Item) -> some View {
        HStack(spacing: 12) {
            Button {
                model.toggleIncluded(for: item.id)
            } label: {
                Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isIncluded ? Theme.brand : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!item.canSave)

            Button {
                editingItemID = item.id
            } label: {
                HStack(spacing: 12) {
                    thumbnail(for: item)

                    VStack(alignment: .leading, spacing: 4) {
                        if item.isAnalyzed {
                            valuesLine(for: item)
                            detailLine(for: item)
                        } else {
                            Text("読み取り待ち…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if item.isAnalyzed {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!item.isAnalyzed)
        }
    }

    @ViewBuilder
    private func thumbnail(for item: BatchImportModel.Item) -> some View {
        if let image = item.thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 48, height: 48)
                .overlay {
                    ProgressView().controlSize(.small)
                }
        }
    }

    @ViewBuilder
    private func valuesLine(for item: BatchImportModel.Item) -> some View {
        if let systolic = item.draft.systolic, let diastolic = item.draft.diastolic {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(systolic)")
                    .font(.title3.weight(.semibold))
                Text("/")
                    .foregroundStyle(.secondary)
                Text("\(diastolic)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                if let pulse = item.draft.pulse {
                    Text("脈 \(pulse)")
                        .font(.caption)
                        .foregroundStyle(Theme.pulse)
                        .padding(.leading, 4)
                }
            }
            .monospacedDigit()
        } else {
            Label("読み取れませんでした", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.categoryHigh)
        }
    }

    private func detailLine(for item: BatchImportModel.Item) -> some View {
        HStack(spacing: 6) {
            Text(AppFormatter.dateTime.string(from: item.draft.measuredAt))
            if item.capturedAt != nil {
                Image(systemName: "camera.metering.center.weighted")
                    .foregroundStyle(Theme.brand)
            }
            if let confidence = item.result?.confidence, item.draft.isValid, confidence < 0.85 {
                Text("要確認")
                    .foregroundStyle(Theme.categoryHigh)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var hintSection: some View {
        Section {
            Label(
                "\(model.failedCount) 枚は数値を読み取れませんでした。タップして手で入力すると記録できます。",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 保存

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button {
                save()
            } label: {
                if model.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(model.selectedCount > 0 ? "\(model.selectedCount) 件を記録する" : "記録する")
                }
            }
            .buttonStyle(.brand)
            .disabled(model.selectedCount == 0 || model.isSaving || model.isAnalyzing)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func save() {
        Task {
            await model.save(context: modelContext, settings: settings)
            dismiss()
        }
    }
}

/// まとめて記録するときの 1 件ぶんの編集画面。
struct BatchItemEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: BPDraft
    @FocusState private var focus: RecordFormSections.Field?
    private let standard: BPStandard
    private let onSave: (BPDraft) -> Void

    init(draft: BPDraft, standard: BPStandard, onSave: @escaping (BPDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.standard = standard
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if let photoData = draft.photoData, let image = UIImage(data: photoData) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                RecordFormSections(draft: $draft, standard: standard, focus: $focus)
            }
            .numberPadToolbar(focus: $focus)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("内容を修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
