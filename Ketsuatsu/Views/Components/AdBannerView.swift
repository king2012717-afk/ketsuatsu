import GoogleMobileAds
import SwiftUI
import UIKit

/// 画面上部に置くバナー広告。
///
/// 読み込みに失敗したときは高さ 0 にして、空白が残らないようにしている。
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
                    // 失敗した場合に枠だけ残らないよう、読み込めたときだけ高さを与える。
                    if isLoaded != loaded { isLoaded = loaded }
                }
                .frame(width: adSize.size.width, height: isLoaded ? adSize.size.height : 0)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color(.secondarySystemBackground))
            }
        }
        .accessibilityLabel("広告")
    }

    private static var screenWidth: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.screen.bounds.width ?? UIScreen.main.bounds.width
    }
}

/// `BannerView`（UIKit）を SwiftUI から使えるようにする。
private struct AdBannerRepresentable: UIViewRepresentable {
    let adUnitID: String
    let adSize: AdSize
    var onLoadStateChange: (Bool) -> Void

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = Self.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        if uiView.rootViewController == nil {
            uiView.rootViewController = Self.rootViewController
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadStateChange: onLoadStateChange)
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var onLoadStateChange: (Bool) -> Void

        init(onLoadStateChange: @escaping (Bool) -> Void) {
            self.onLoadStateChange = onLoadStateChange
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onLoadStateChange(true)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onLoadStateChange(false)
        }
    }
}
