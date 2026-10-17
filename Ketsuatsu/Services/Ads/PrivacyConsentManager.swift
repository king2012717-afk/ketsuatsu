import AppTrackingTransparency
import Foundation
import IronSource
import Observation

/// 広告の同意と ATT（トラッキングの確認）を管理し、終わってから広告 SDK を起動する（仕様書 1-5）。
///
/// 順序は「同意画面での選択 → LevelPlay のプライバシー設定 → ATT → SDK 初期化」。
/// - ATT は同意画面でどちらを選んでも、未決定なら必ず 1 回出す（2026-09-22 美術館の審査差し戻しの再発防止）。
///   パーソナライズするかどうかは LevelPlay 側の同意設定で決まるので、
///   「興味に合わせない」を選んだ人が ATT で許可しても、広告はパーソナライズされない。
/// - 選択が済むまで広告 SDK を起動せず、バナーも作らない。
@MainActor
@Observable
final class PrivacyConsentManager {

    enum Choice: String, Sendable {
        /// 興味に合わせた広告を表示する
        case personalized
        /// 興味に合わせない広告にする
        case nonPersonalized
    }

    static let shared = PrivacyConsentManager()

    private static let choiceKey = "ads.consent.choice.v1"

    /// 同意画面で選んだ内容。まだ選んでいなければ nil。
    private(set) var choice: Choice?

    /// 同意と ATT の確認が終わり、広告を読み込んでよい状態か。
    private(set) var canRequestAds = false

    /// 同意画面での選択、または起動時の再開の処理中か（二重に進めないため）。
    private(set) var isProcessing = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.choice = defaults.string(forKey: Self.choiceKey).flatMap(Choice.init(rawValue:))
    }

    /// 同意画面を出す必要があるか。
    var needsConsent: Bool { choice == nil }

    /// 同意画面で選んだとき。ATT は同意画面を閉じる前に出す（画面の切り替え中だと表示されないことがあるため）。
    func select(_ choice: Choice) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        applyPrivacySettings(for: choice, beforeInitialization: true)
        await requestTrackingIfNeeded()

        self.choice = choice
        defaults.set(choice.rawValue, forKey: Self.choiceKey)
        startAds()
    }

    /// アプリが前面に出たときに呼ぶ。同意済みなら、ATT（未決定のときだけ）→ SDK 初期化へ進む。
    func resumeIfConsented() async {
        guard let choice, !canRequestAds, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        applyPrivacySettings(for: choice, beforeInitialization: true)
        await requestTrackingIfNeeded()
        startAds()
    }

    /// 設定画面で選び直したとき。SDK の起動後でも反映できる GDPR／CCPA の設定だけを更新する。
    func change(to choice: Choice) {
        self.choice = choice
        defaults.set(choice.rawValue, forKey: Self.choiceKey)
        applyPrivacySettings(for: choice, beforeInitialization: false)
    }

    // MARK: - 内部

    private func applyPrivacySettings(for choice: Choice, beforeInitialization: Bool) {
        if beforeInitialization {
            // 子ども向けのアプリではない。COPPA の設定は SDK の初期化前にしか効かない。
            LPMPrivacySettings.setCOPPA(false)
        }
        LPMPrivacySettings.setGDPRConsent(choice == .personalized)
        // 「興味に合わせない」を選んだ人は、個人情報の販売・共有を拒否したものとして扱う。
        LPMPrivacySettings.setCCPA(choice != .personalized)
    }

    private func requestTrackingIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    private func startAds() {
        canRequestAds = true
        LevelPlayBannerController.shared.start()
    }
}
