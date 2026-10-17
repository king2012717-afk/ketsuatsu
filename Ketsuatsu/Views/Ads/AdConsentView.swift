import SwiftUI

/// 広告の表示方法を選んでもらう画面。初回起動時（アップデート後の初回を含む）に一度だけ出す（仕様書 1-5）。
struct AdConsentView: View {
    @Environment(PrivacyConsentManager.self) private var consent

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppMarkView(size: 64)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                    Text("広告の表示について")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("うちの血圧記録は、無料でお使いいただけるよう、画面の上部に広告を表示しています。")
                        Text("広告を、あなたの興味に合わせて表示してよいかを選んでください。どちらを選んでも、アプリの機能はすべて使えます。")
                        Label {
                            Text("記録した血圧・脈拍・メモなどの健康情報が、広告に使われることはありません。")
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(Theme.brand)
                        }
                        Text("このあと iOS の確認画面が表示されます。")
                            .fontWeight(.semibold)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await consent.select(.personalized) }
                } label: {
                    Text("興味に合わせた広告を表示する")
                }
                .buttonStyle(.brand)

                Button {
                    Task { await consent.select(.nonPersonalized) }
                } label: {
                    Text("興味に合わせない広告にする")
                }
                .buttonStyle(.brandSecondary)

                Text("選んだ内容は、あとから 設定 →「広告」で変えられます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(consent.isProcessing)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Theme.pageBackground)
        .interactiveDismissDisabled()
    }
}
