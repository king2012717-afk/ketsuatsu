import SwiftUI

/// 期間を選ぶ横並びのチップ。選択肢が多いのでセグメントではなく横スクロールにしている。
struct PeriodChips: View {
    @Binding var selection: PeriodFilter
    var cases: [PeriodFilter] = PeriodFilter.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cases) { period in
                    chip(period)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ period: PeriodFilter) -> some View {
        let isSelected = period == selection

        return Button {
            selection = period
        } label: {
            Text(period.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(Theme.brandGradient)
                    } else {
                        Capsule().fill(Color(.secondarySystemFill))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var selection: PeriodFilter = .month1

    VStack(alignment: .leading) {
        PeriodChips(selection: $selection)
        Text(selection.title)
    }
    .padding()
}
