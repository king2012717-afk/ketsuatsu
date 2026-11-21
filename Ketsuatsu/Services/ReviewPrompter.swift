import StoreKit
import UIKit

/// 記録の保存に成功した後、条件を満たしていれば iOS 標準の評価画面をお願いする。
/// 保存の画面が閉じてから出るよう、少し待ってから呼ぶ。
@MainActor
enum ReviewPrompter {
    /// 保存の画面が閉じるのを待つ時間（秒）。
    static let delay: Duration = .seconds(1.5)

    /// 待っている間に保存が続いても、お願いを二重に予約しないための印。
    private static var isPending = false

    static func requestIfAppropriate(completedEntries: Int, policy: ReviewPromptPolicy = ReviewPromptPolicy()) {
        guard !isPending, policy.shouldRequest(completedEntries: completedEntries) else { return }
        isPending = true
        Task { @MainActor in
            defer { isPending = false }
            try? await Task.sleep(for: delay)
            // 待っている間にアプリが裏に回った・画面がロックされたときは、お願いしたことにしない（次の保存でまた判定する）
            guard let scene = activeScene() else { return }
            policy.markRequested()
            AppStore.requestReview(in: scene)
        }
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
