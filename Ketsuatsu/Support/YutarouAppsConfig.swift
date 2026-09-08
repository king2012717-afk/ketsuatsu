import Foundation

enum YutarouAppsConfig {
    static let endpoint = URL(string: "https://yutaroulabs.com/data/apps.json")!
    static let currentAppID = "ketsuatsu-record"
    static let currentCategory = "health"
    static let recommendationCount = 3
    static let sameCategoryCount = 2
    static let cacheLifetime: TimeInterval = 24 * 60 * 60
}
