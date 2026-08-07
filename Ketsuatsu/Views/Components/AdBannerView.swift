import GoogleMobileAds
import SwiftUI
import UIKit

/// 画面上部に置くバナー広告。
///
/// Google のサンプルに合わせて、次の 2 点を守っている。
/// - バナーを載せるビューコントローラを用意し、それ自身を `rootViewController` にする
/// - 生成した時点で `load()` を呼び、高さは最初から確保しておく
///   （読み込めるまで高さ 0 にしていると、そもそも広告が表示されない）
struct AdBanner: View {
    var adUnitID: String = AdConfiguration.bannerUnitID

    @State private var adSize: AdSize = currentOrientationAnchoredAdaptiveBanner(
        width: UIScreen.main.bounds.width
    )

    var body: some View {
        if AdConfiguration.isEnabled {
            GeometryReader { proxy in
                AdBannerRepresentable(adUnitID: adUnitID, adSize: adSize)
                    .frame(width: adSize.size.width, height: adSize.size.height)
                    .frame(maxWidth: .infinity)
                    .onAppear { updateSize(width: proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in updateSize(width: width) }
            }
            .frame(height: adSize.size.height)
            .background(Color(.secondarySystemBackground))
            .accessibilityLabel("広告")
        }
    }

    private func updateSize(width: CGFloat) {
        guard width > 0 else { return }
        let updated = currentOrientationAnchoredAdaptiveBanner(width: width)
        if updated.size != adSize.size { adSize = updated }
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

        AdConfiguration.log("読み込みを開始します（\(adUnitID)）")
        banner.load(Request())

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let banner = context.coordinator.banner else { return }
        guard banner.adSize.size != adSize.size else { return }

        // 画面の幅が変わったとき（回転など）はサイズを作り直して読み込み直す。
        banner.adSize = adSize
        banner.frame = CGRect(origin: .zero, size: adSize.size)
        uiViewController.view.frame = CGRect(origin: .zero, size: adSize.size)
        banner.load(Request())
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var banner: BannerView?

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AdConfiguration.log("読み込みに成功しました")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AdConfiguration.log("読み込みに失敗しました: \(error.localizedDescription)")
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            AdConfiguration.log("インプレッションを記録しました")
        }
    }
}
