import SwiftUI

/// 「128 / 82」を大きく見せる表示。ホームと読み取り結果の確認で使う。
struct BPReadingView: View {
    let systolic: Int?
    let diastolic: Int?
    var pulse: Int?
    var size: Size = .large
    var style: Style = .standard

    enum Size {
        case large
        case medium

        var valueFont: Font {
            switch self {
            case .large: return .system(size: 52, weight: .bold, design: .rounded)
            case .medium: return .system(size: 32, weight: .semibold, design: .rounded)
            }
        }

        var separatorFont: Font {
            switch self {
            case .large: return .system(size: 34, weight: .light, design: .rounded)
            case .medium: return .system(size: 22, weight: .light, design: .rounded)
            }
        }
    }

    /// 通常の背景に置くか、ブランドカラーのカードに白抜きで置くか。
    enum Style {
        case standard
        case onBrand

        var systolicColor: Color {
            switch self {
            case .standard: return .primary
            case .onBrand: return .white
            }
        }

        var diastolicColor: Color {
            switch self {
            case .standard: return .secondary
            case .onBrand: return .white.opacity(0.85)
            }
        }

        var unitColor: Color {
            switch self {
            case .standard: return .secondary
            case .onBrand: return .white.opacity(0.75)
            }
        }

        var pulseColor: Color {
            switch self {
            case .standard: return Theme.pulse
            case .onBrand: return .white.opacity(0.9)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text(systolic))
                    .font(size.valueFont)
                    .foregroundStyle(style.systolicColor)
                Text("/")
                    .font(size.separatorFont)
                    .foregroundStyle(style.unitColor)
                Text(text(diastolic))
                    .font(size.valueFont)
                    .foregroundStyle(style.diastolicColor)
                Text("mmHg")
                    .font(.caption)
                    .foregroundStyle(style.unitColor)
            }
            .monospacedDigit()
            .contentTransition(.numericText())

            if let pulse {
                Label("\(pulse) bpm", systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(style.pulseColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func text(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    private var accessibilityText: String {
        var parts = ["上 \(text(systolic))、下 \(text(diastolic)) ミリメートル水銀柱"]
        if let pulse { parts.append("脈拍 \(pulse)") }
        return parts.joined(separator: "、")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        BPReadingView(systolic: 128, diastolic: 82, pulse: 68)
        BPReadingView(systolic: nil, diastolic: nil, size: .medium)
        BPReadingView(systolic: 142, diastolic: 91, pulse: 74, style: .onBrand)
            .padding()
            .background(Theme.brandGradientDiagonal, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .padding()
}
