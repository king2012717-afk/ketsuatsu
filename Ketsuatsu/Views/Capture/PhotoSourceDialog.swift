import SwiftUI

/// 「写真から記録」を押したときに画面の中央へ出す選択ダイアログ。
///
/// 下から出るアクションシートより指を動かす距離が短く、選択肢の説明も添えられるので、
/// 画面中央に大きめのカードとして出している。
struct PhotoSourceDialog: View {
    var showsCamera: Bool = CameraPicker.isAvailable
    var onCamera: () -> Void
    var onLibrary: () -> Void
    var onCancel: () -> Void

    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.black
                .opacity(isVisible ? 0.38 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close(with: onCancel) }

            card
                .scaleEffect(isVisible ? 1 : 0.92)
                .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isVisible = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.brand)
                Text("写真から記録")
                    .font(.title3.weight(.bold))
                Text("血圧計の表示から、上・下・脈拍を自動で読み取ります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 26)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)

            VStack(spacing: 12) {
                if showsCamera {
                    option(
                        title: "血圧計を撮影する",
                        caption: "その場で撮って記録します",
                        systemImage: "camera.fill",
                        isProminent: true,
                        action: onCamera
                    )
                }
                option(
                    title: "写真から選ぶ",
                    caption: "複数選ぶとまとめて記録できます",
                    systemImage: "photo.on.rectangle",
                    isProminent: !showsCamera,
                    action: onLibrary
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            Divider()

            Button {
                close(with: onCancel)
            } label: {
                Text("キャンセル")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 340)
        .background(
            Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 14)
        .padding(.horizontal, 24)
        .accessibilityAddTraits(.isModal)
    }

    private func option(
        title: String,
        caption: String,
        systemImage: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            close(with: action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(caption)
                        .font(.caption2)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isProminent ? Color.white : Theme.brand)
            .background {
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .fill(
                        isProminent
                        ? AnyShapeStyle(Theme.brandGradient)
                        : AnyShapeStyle(Theme.brand.opacity(0.12))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 消えるところまで見せてから、次の画面へ進む。
    private func close(with action: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.16)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: action)
    }
}

#Preview {
    ZStack {
        Theme.pageBackground.ignoresSafeArea()
        PhotoSourceDialog(showsCamera: true, onCamera: {}, onLibrary: {}, onCancel: {})
    }
}
