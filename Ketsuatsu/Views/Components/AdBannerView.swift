import IronSource
import SwiftUI
import UIKit

private enum AdConfig {
    static let appKey = AdConfiguration.appKey
    static let bannerUnitID = AdConfiguration.bannerUnitID
    static let isConfigured = AdConfiguration.isConfigured
}

final class LevelPlayBannerController: ObservableObject {
    static let shared = LevelPlayBannerController()

    @Published private(set) var isReady = false
    private var isStarting = false

    private init() {}

    func start() {
        guard !isReady, !isStarting, AdConfig.isConfigured else { return }
        isStarting = true
        #if DEBUG
        LevelPlay.setAdaptersDebug(true)
        #endif
        let request = LPMInitRequestBuilder(appKey: AdConfig.appKey).build()
        LevelPlay.initWith(request) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isStarting = false
                if let error {
                    #if DEBUG
                    print("[Ads] LevelPlay 初期化失敗: \(error.localizedDescription)")
                    #endif
                    return
                }
                self.isReady = true
            }
        }
    }
}

private struct LevelPlayBannerRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LPMBannerAdView {
        let banner = LPMBannerAdView(adUnitId: AdConfig.bannerUnitID)
        context.coordinator.banner = banner
        banner.setDelegate(context.coordinator)
        if let viewController = Self.topViewController() {
            banner.loadAd(with: viewController)
        }
        return banner
    }

    func updateUIView(_ uiView: LPMBannerAdView, context: Context) {}

    static func dismantleUIView(_ uiView: LPMBannerAdView, coordinator: Coordinator) {
        coordinator.banner = nil
        uiView.destroy()
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var current = root
        while let presented = current?.presentedViewController { current = presented }
        return current
    }

    final class Coordinator: NSObject, LPMBannerAdViewDelegate {
        weak var banner: LPMBannerAdView?
        func didLoadAd(with adInfo: LPMAdInfo) {}
        func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
            #if DEBUG
            print("[Ads] バナー読み込み失敗: \(error.localizedDescription)")
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let banner = self?.banner,
                      let viewController = LevelPlayBannerRepresentable.topViewController()
                else { return }
                banner.loadAd(with: viewController)
            }
        }
        func didClickAd(with adInfo: LPMAdInfo) {}
        func didDisplayAd(with adInfo: LPMAdInfo) {}
        func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {}
        func didLeaveApp(with adInfo: LPMAdInfo) {}
        func didExpandAd(with adInfo: LPMAdInfo) {}
        func didCollapseAd(with adInfo: LPMAdInfo) {}
    }
}

struct AdBanner: View {
    @ObservedObject private var controller = LevelPlayBannerController.shared

    var body: some View {
        if AdConfiguration.isEnabled, controller.isReady {
            LevelPlayBannerRepresentable()
                .frame(width: 320, height: 50)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .accessibilityLabel("広告")
        }
    }
}
