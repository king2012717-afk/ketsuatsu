import GoogleMobileAds
import SwiftUI
import UIKit

/// 画面上部に置くバナー広告。
///
/// 広告の読み込みには、画面階層に入った `UIViewController` が必要になる。
/// SwiftUI からキーウィンドウのルートを探すと起動直後は nil になることがあるため、
/// バナー専用のビューコントローラを用意し、それが表示されたタイミングで読み込む。
struct AdBanner: View {
    var adUnitID: String = AdConfiguration.bannerUnitID

    @State private var isLoaded = false

    private var adSize: AdSize {
        currentOrientationAnchoredAdaptiveBanner(width: Self.screenWidth)
    }

    var body: some View {
        Group {
            if AdConfiguration.isEnabled {
                AdBannerRepresentable(adUnitID: adUnitID, adSize: adSize) { loaded in
                    // 読み込めなかったときに枠だけ残らないよう、成功したときだけ高さを与える。
                    if isLoaded != loaded { isLoaded = loaded }
                }
                .frame(height: isLoaded ? adSize.size.height : 0)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color(.secondarySystemBackground))
                .accessibilityLabel("広告")
            }
        }
    }

    private static var screenWidth: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.width ?? UIScreen.main.bounds.width
    }
}

/// `BannerView` を持つだけのビューコントローラを SwiftUI から使う。
private struct AdBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String
    let adSize: AdSize
    var onLoadStateChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> AdBannerHostController {
        let controller = AdBannerHostController()

        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        // 自分自身をルートにするので、キーウィンドウを探す必要がない。
        banner.rootViewController = controller
        banner.translatesAutoresizingMaskIntoConstraints = false

        controller.view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: controller.view.topAnchor),
            banner.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor)
        ])
        controller.banner = banner

        return controller
    }

    func updateUIViewController(_ uiViewController: AdBannerHostController, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadStateChange: onLoadStateChange)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var onLoadStateChange: (Bool) -> Void

        init(onLoadStateChange: @escaping (Bool) -> Void) {
            self.onLoadStateChange = onLoadStateChange
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AdConfiguration.log("バナーを読み込みました")
            onLoadStateChange(true)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AdConfiguration.log("バナーの読み込みに失敗: \(error.localizedDescription)")
            onLoadStateChange(false)
        }
    }
}

/// バナーを載せるためだけのビューコントローラ。画面に出た時点で広告を読み込む。
final class AdBannerHostController: UIViewController {
    var banner: BannerView?

    private var hasRequestedAd = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadAdIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // viewDidAppear が呼ばれない構成でも取りこぼさないよう、ここでも試す。
        loadAdIfNeeded()
    }

    private func loadAdIfNeeded() {
        guard !hasRequestedAd, let banner, view.window != nil else { return }
        hasRequestedAd = true
        AdConfiguration.log("バナーを読み込みます: \(banner.adUnitID ?? "-")")
        banner.load(Request())
    }
}
