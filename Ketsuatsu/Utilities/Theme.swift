import SwiftUI

/// アプリアイコン（コーラルレッドの角丸スクエア＋白い血圧計）に合わせた配色と装飾。
///
/// アイコンの背景グラデーションをそのまま基準色にしているので、
/// ホームのカードやボタンがアイコンと地続きに見えるようにしている。
enum Theme {

    // MARK: - ブランドカラー（アイコンのグラデーションから採色）

    /// #FA657A — アイコン上端
    static let brandLight = Color(red: 250 / 255, green: 101 / 255, blue: 122 / 255)
    /// #F35064 — アイコン中央。アクセントカラーと同じ。
    static let brand = Color(red: 243 / 255, green: 80 / 255, blue: 100 / 255)
    /// #ED3B4E — アイコン下端
    static let brandDeep = Color(red: 237 / 255, green: 59 / 255, blue: 78 / 255)

    /// アイコンと同じ縦方向のグラデーション。
    static let brandGradient = LinearGradient(
        colors: [brandLight, brandDeep],
        startPoint: .top,
        endPoint: .bottom
    )

    /// カードなど広い面に敷くときの斜めグラデーション。
    static let brandGradientDiagonal = LinearGradient(
        colors: [brandLight, brandDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 数値の色

    /// 収縮期（上）。アイコンと同じコーラルレッド。
    static let systolic = brand
    /// 拡張期（下）。コーラルと相性のよい落ち着いた青。
    static let diastolic = Color(red: 63 / 255, green: 123 / 255, blue: 216 / 255)
    /// 脈拍。ブランドカラーを明るくしたピンク。
    static let pulse = Color(red: 255 / 255, green: 143 / 255, blue: 163 / 255)

    // MARK: - 判定区分の色（緑 → 琥珀 → コーラル → ベリー）

    static let categoryLow = Color(red: 53 / 255, green: 184 / 255, blue: 199 / 255)
    static let categoryNormal = Color(red: 47 / 255, green: 180 / 255, blue: 124 / 255)
    static let categoryElevated = Color(red: 124 / 255, green: 194 / 255, blue: 78 / 255)
    static let categoryHigh = Color(red: 240 / 255, green: 169 / 255, blue: 59 / 255)
    static let categoryGrade1 = Color(red: 245 / 255, green: 118 / 255, blue: 63 / 255)
    static let categoryGrade2 = brand
    static let categoryGrade3 = Color(red: 178 / 255, green: 33 / 255, blue: 74 / 255)

    // MARK: - かたち

    /// アイコンの角丸に合わせた、やわらかい連続角丸。
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 14

    static var cardBackground: Color { Color(.secondarySystemGroupedBackground) }
    static var pageBackground: Color { Color(.systemGroupedBackground) }
}

// MARK: - 共通のスタイル

extension View {
    /// 白いカード。角丸はアイコンと同じ連続曲線。
    func cardStyle(padding: CGFloat = 16, alignment: Alignment = .leading) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(
                Theme.cardBackground,
                in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            )
    }
}

/// アイコンのグラデーションをそのまま使う主要ボタン。
struct BrandButtonStyle: ButtonStyle {
    var isProminent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Theme.brand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .fill(isProminent ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.brand.opacity(0.12)))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
    static var brandSecondary: BrandButtonStyle { BrandButtonStyle(isProminent: false) }
}

/// アプリアイコンと同じマーク。
struct AppMarkView: View {
    var size: CGFloat = 44

    var body: some View {
        Image("AppMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        AppMarkView(size: 96)
        Button("写真から記録") {}
            .buttonStyle(.brand)
        Button("手入力") {}
            .buttonStyle(.brandSecondary)
        Text("カード")
            .cardStyle()
    }
    .padding()
    .background(Theme.pageBackground)
}
