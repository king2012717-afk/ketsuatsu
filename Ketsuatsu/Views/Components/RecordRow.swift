import SwiftUI

/// 履歴一覧の 1 行。
struct RecordRow: View {
    let record: BPRecord
    let standard: BPStandard

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppFormatter.time.string(from: record.measuredAt))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Label(record.slot.title, systemImage: record.slot.symbolName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(record.systolic)")
                        .font(.title3.weight(.semibold))
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text("\(record.diastolic)")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let pulse = record.pulse {
                        Text("脈 \(pulse)")
                            .font(.caption)
                            .foregroundStyle(.pink)
                            .padding(.leading, 4)
                    }
                }
                .monospacedDigit()

                if !record.note.isEmpty {
                    Text(record.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                CategoryBadge(category: record.category(standard: standard), compact: true)
                HStack(spacing: 4) {
                    if record.tookMedication {
                        Image(systemName: "pills.fill")
                            .foregroundStyle(.purple)
                    }
                    if record.source != .manual {
                        Image(systemName: record.source.symbolName)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}
