import SwiftUI

/// 保存してある記録を開けなかったときに、通常の画面の代わりに出す。
/// この状態で記録させると、保存できたように見えて終了時に消えるため、入力はさせない（仕様書 4-2）。
struct StoreUnavailableView: View {
    /// 開けなかった理由（問い合わせ用）。
    let detail: String?
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("記録を開けませんでした", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text("保存してある記録を読み込めなかったため、いまは記録や閲覧ができません。これまでの記録は消していません。")
                Text("iPhone の空き容量を確認し、アプリを終了してからもう一度開いてください。")
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        } actions: {
            Button("もう一度試す", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    StoreUnavailableView(detail: "The file couldn’t be opened.") {}
}
