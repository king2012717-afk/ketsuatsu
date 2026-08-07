import SwiftUI

/// 数値をキーボードでも +/− ボタンでも入力できる行。
/// 血圧の入力は 1 ずつ調整したい場面が多いのでステッパーを併設している。
struct NumberFieldRow: View {
    let title: String
    let unit: String
    var systemImage: String?
    var tint: Color = .primary
    var range: ClosedRange<Int>
    var placeholder: String = "--"
    /// 未入力の状態で +/− を押したときの起点。
    var startValue: Int?
    @Binding var value: Int?

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(title)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
            }
            .font(.body)

            Spacer(minLength: 8)

            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.title3.weight(.semibold))
                .frame(width: 68)
                .focused($isFocused)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Stepper(
                "",
                onIncrement: { adjust(by: 1) },
                onDecrement: { adjust(by: -1) }
            )
            .labelsHidden()
        }
        .onAppear { syncTextFromValue() }
        .onChange(of: text) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(3))
            if digits != newValue { text = digits }
            value = digits.isEmpty ? nil : Int(digits)
        }
        .onChange(of: value) { _, newValue in
            // ステッパーや外部からの変更をテキストへ反映する（入力中のちらつきは避ける）。
            if Int(text) != newValue { syncTextFromValue() }
        }
    }

    private func syncTextFromValue() {
        text = value.map(String.init) ?? ""
    }

    private func adjust(by delta: Int) {
        let base = value ?? defaultValue
        let updated = min(max(base + delta, range.lowerBound), range.upperBound)
        value = updated
    }

    private var defaultValue: Int {
        let base = startValue ?? (range.lowerBound + range.upperBound) / 2
        return min(max(base, range.lowerBound), range.upperBound)
    }
}

#Preview {
    @Previewable @State var systolic: Int? = 128
    @Previewable @State var pulse: Int?

    Form {
        NumberFieldRow(
            title: "収縮期（上）",
            unit: "mmHg",
            systemImage: "arrow.up.circle.fill",
            tint: .red,
            range: BPValueRange.systolic,
            startValue: 120,
            value: $systolic
        )
        NumberFieldRow(
            title: "脈拍",
            unit: "bpm",
            systemImage: "heart.fill",
            tint: .pink,
            range: BPValueRange.pulse,
            startValue: 70,
            value: $pulse
        )
    }
}
