import Foundation

enum AdConfiguration {
    static let appKey = plistString("LevelPlayAppKey")
    static let bannerUnitID = plistString("LevelPlayBannerAdUnitID")
    static var isEnabled: Bool { true }
    static var isConfigured: Bool { !appKey.isEmpty && !bannerUnitID.isEmpty }

    private static func plistString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func log(_ message: String) {
        #if DEBUG
        print("[AdBanner] \(message)")
        #endif
    }
}
