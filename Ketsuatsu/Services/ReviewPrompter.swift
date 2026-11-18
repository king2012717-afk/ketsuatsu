import StoreKit
import UIKit

/// 記録の保存に成功した後、条件を満たしていれば iOS 標準の評価画面をお願いする。
/// 保存の画面が閉じてから出るよう、少し待ってから呼ぶ。
@MainActor
enum ReviewPrompter {
    /// 保存の画面が閉じるのを待つ時間（秒）。
    static let delay: Duration = .seconds(1.5)

    static func requestIfAppropriate(completedEntries: Int, policy: ReviewPromptPolicy = ReviewPromptPolicy()) {
        guard policy.shouldRequest(completedEntries: completedEntries) else { return }
        policy.markRequested()
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard let scene = activeScene() else { return }
            AppStore.requestReview(in: scene)
        }
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
