import GoogleMobileAds
import SwiftUI
import UIKit

/// 画面上部に置くバナー広告。
///
/// 守っていること（Part 1-4）：
/// - `load()` は生成時（`makeUIViewController`）で一度だけ呼ぶ。
///   画面を行き来するたびに読み込み直さないため、`updateUIViewController` では呼ばない
/// - バナーを載せるビューコントローラを用意し、それ自身を `rootViewController` にする
/// - 高さは最初から確保しておく（読み込めるまで高さ 0 にすると広告が表示されない）
/// - 操作領域との間に背景色を敷き、誤タップを防ぐ
///
/// 呼び出し側は `ConsentManager.canRequestAds` が true になるまで
/// この View を生成しないこと（生成しなければ広告リクエストも発生しない）。
struct AdBanner: View {
    var adUnitID: String = AdConfig.bannerUnitID

    /// 縦向き固定のアプリなので、サイズは生成時に一度決めれば足りる。
    private let adSize: AdSize = currentOrientationAnchoredAdaptiveBanner(
        width: UIScreen.main.bounds.width
    )

    var body: some View {
        if AdConfig.isEnabled {
            AdBannerRepresentable(adUnitID: adUnitID, adSize: adSize)
                .frame(height: adSize.size.height)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .accessibilityLabel("広告")
        }
    }
}

private struct AdBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String
    let adSize: AdSize

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear

        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        // 自分自身をルートにするため、キーウィンドウを探す必要がない。
        banner.rootViewController = controller
        banner.delegate = context.coordinator
        banner.frame = CGRect(origin: .zero, size: adSize.size)

        controller.view.addSubview(banner)
        controller.view.frame = CGRect(origin: .zero, size: adSize.size)
        context.coordinator.banner = banner

        AdConfig.log("読み込みを開始します（\(adUnitID)）")
        banner.load(Request())

        return controller
    }

    /// 何もしない。ここで `load()` を呼ぶと画面遷移のたびに再読み込みされる（Part 1-4）。
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var banner: BannerView?

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AdConfig.log("読み込みに成功しました")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AdConfig.log("読み込みに失敗しました: \(error.localizedDescription)")
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            AdConfig.log("インプレッションを記録しました")
        }
    }
}
