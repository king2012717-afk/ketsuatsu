import IronSource
import SwiftUI
import UIKit

private enum AdConfig {
    static let appKey = AdConfiguration.appKey
    static let bannerUnitID = AdConfiguration.bannerUnitID
    static let isConfigured = AdConfiguration.isConfigured
}

/// LevelPlay SDK の初期化（アプリ起動中に 1 回だけ）。
/// 同意と ATT が終わってから `PrivacyConsentManager` が呼ぶ（仕様書 1-5）。起動時に直接呼ばない。
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

    /// 読み込みに失敗したときは、間隔を延ばしながら上限回数まで再試行する（仕様書 1-10）。
    /// アプリが背面にいる間は再試行せず、前面に戻ってから試す。
    final class Coordinator: NSObject, LPMBannerAdViewDelegate {
        weak var banner: LPMBannerAdView?
        private var retryPolicy = AdRetryPolicy()
        private var pendingRetry: DispatchWorkItem?
        private var waitsForForeground = false
        private var foregroundObserver: NSObjectProtocol?

        override init() {
            super.init()
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.retryIfWaitingForForeground()
            }
        }

        deinit {
            pendingRetry?.cancel()
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
        }

        func didLoadAd(with adInfo: LPMAdInfo) {
            DispatchQueue.main.async { [weak self] in
                self?.retryPolicy.reset()
            }
        }

        func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
            #if DEBUG
            print("[Ads] バナー読み込み失敗: \(error.localizedDescription)")
            #endif
            DispatchQueue.main.async { [weak self] in
                self?.scheduleRetry()
            }
        }

        private func scheduleRetry() {
            pendingRetry?.cancel()
            guard let delay = retryPolicy.nextDelay() else {
                #if DEBUG
                print("[Ads] 再試行の上限に達したため、バナーの読み込みをやめます")
                #endif
                return
            }
            let work = DispatchWorkItem { [weak self] in
                self?.reload()
            }
            pendingRetry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func reload() {
            guard UIApplication.shared.applicationState == .active else {
                waitsForForeground = true
                return
            }
            guard let banner,
                  let viewController = LevelPlayBannerRepresentable.topViewController()
            else { return }
            banner.loadAd(with: viewController)
        }

        private func retryIfWaitingForForeground() {
            guard waitsForForeground else { return }
            waitsForForeground = false
            reload()
        }
        func didClickAd(with adInfo: LPMAdInfo) {}
        func didDisplayAd(with adInfo: LPMAdInfo) {}
        func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {}
        func didLeaveApp(with adInfo: LPMAdInfo) {}
        func didExpandAd(with adInfo: LPMAdInfo) {}
        func didCollapseAd(with adInfo: LPMAdInfo) {}
    }
}

/// 画面上部の常設バナー。同意と ATT が終わり、SDK の初期化が成功するまで View 自体を作らない（仕様書 1-7）。
struct AdBanner: View {
    @ObservedObject private var controller = LevelPlayBannerController.shared
    @Environment(PrivacyConsentManager.self) private var consent

    var body: some View {
        if AdConfiguration.isEnabled, consent.canRequestAds, controller.isReady {
            LevelPlayBannerRepresentable()
                .frame(width: 320, height: 50)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .accessibilityLabel("広告")
        }
    }
}
