import FirebaseAnalytics
import FirebaseCore
import Foundation

/// YutarouLabs 共通の Firebase Analytics 薄いラッパー。
/// イベント名と共通パラメータをここへ集約し、各アプリへ横展開しやすくする。
enum AnalyticsService {
    static let sourceApp = "ketsuatsu"

    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    static func log(_ name: String, parameters: [String: Any] = [:]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }

    static func onboardingCompleted() {
        log("onboarding_complete")
    }

    static func mainActionCompleted(action: String) {
        log("main_action_complete", parameters: ["action": action])
    }

    static func recommendedAppImpression(destinationApp: String, placement: String, campaign: String) {
        log("recommended_app_impression", parameters: recommendationParameters(
            destinationApp: destinationApp,
            placement: placement,
            campaign: campaign
        ))
    }

    static func recommendedAppClick(destinationApp: String, placement: String, campaign: String) {
        log("recommended_app_click", parameters: recommendationParameters(
            destinationApp: destinationApp,
            placement: placement,
            campaign: campaign
        ))
    }

    private static func recommendationParameters(
        destinationApp: String,
        placement: String,
        campaign: String
    ) -> [String: Any] {
        [
            "source_app": sourceApp,
            "destination_app": destinationApp,
            "placement": placement,
            "campaign": campaign,
        ]
    }
}
