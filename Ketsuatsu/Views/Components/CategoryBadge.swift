import SwiftUI

/// 血圧の判定区分を色付きのラベルで表示する。
struct CategoryBadge: View {
    let category: BPCategory
    var compact = false

    var body: some View {
        Text(compact ? category.shortTitle : category.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .background(category.color.opacity(0.18), in: Capsule())
            .foregroundStyle(category.color)
            .accessibilityLabel("判定 \(category.title)")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(BPCategory.allCases) { category in
            CategoryBadge(category: category)
        }
    }
    .padding()
}
