import Foundation
import SwiftUI
import AppTrackingTransparency
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

/// 広告の同意取得を管理する。
///
/// 流れ（Googleの推奨順）：
/// 1. UMP同意フォーム（GDPR等。EU圏で必要なら表示）
/// 2. ATT（Appの追跡許可ダイアログ）
/// 3. 広告SDKの初期化
@MainActor
final class ConsentManager: ObservableObject {
    static let shared = ConsentManager()
    private var didRun = false

    /// 広告を要求してよい状態か。
    /// これが true になるまでSDKを開始せず、バナーViewも生成しない。
    @Published private(set) var canRequestAds = false

    /// アプリのUIが表示された後に一度だけ呼ぶ。
    func startOnce() {
        guard !didRun else { return }
        didRun = true
        gatherUMPConsent()
    }

    private func gatherUMPConsent() {
        #if canImport(UserMessagingPlatform)
        let params = RequestParameters()
        params.isTaggedForUnderAgeOfConsent = false
        let debugIDs = AdConfig.testDeviceIdentifiers
        if !debugIDs.isEmpty {
            let debugSettings = DebugSettings()
            debugSettings.testDeviceIdentifiers = debugIDs
            params.debugSettings = debugSettings
        }
        ConsentInformation.shared.requestConsentInfoUpdate(with: params) { [weak self] error in
            Task { @MainActor in
                guard error == nil, let root = Self.rootVC() else {
                    // 更新に失敗しても無条件で広告を開始しない
                    self?.finishConsent()
                    return
                }
                ConsentForm.loadAndPresentIfRequired(from: root) { _ in
                    Task { @MainActor in self?.finishConsent() }
                }
            }
        }
        #else
        canRequestAds = false
        #endif
    }

    private func finishConsent() {
        #if canImport(UserMessagingPlatform)
        guard ConsentInformation.shared.canRequestAds else {
            canRequestAds = false
            return
        }
        #endif
        requestATTThenStartAds()
    }

    private func requestATTThenStartAds() {
        ATTrackingManager.requestTrackingAuthorization { _ in
            Task { @MainActor in
                // SDK は start() 以降のリクエストを内部でキューイングするため完了は待たない
                Self.startAdsSDK()
                self.canRequestAds = true
            }
        }
    }

    private static func startAdsSDK() {
        #if canImport(GoogleMobileAds)
        let ids = AdConfig.testDeviceIdentifiers
        if !ids.isEmpty {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ids
        }
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }

    private static func rootVC() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
