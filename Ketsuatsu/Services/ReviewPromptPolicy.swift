import Foundation

/// App Store の評価のお願い（iOS 標準の評価画面）を出してよいかを決める。
///
/// - 記録を 5 件保存した後から対象にする（使い方が分かり、役に立った人に聞く）。
/// - 同じバージョンでは 1 回まで。前回から 120 日あける。通算 3 回まで。
///   （iOS 側も 1 年に 3 回までしか表示しない。こちらでも控えめにする）
/// - 実際に画面が出るかどうかは iOS が決める。ここでは「お願いしてよいか」だけを判定する。
/// - 値は UserDefaults に保存する。件数は `EntryMilestoneTracker.completedEntries` を使う。
struct ReviewPromptPolicy {
    static let minimumEntries = 5
    static let minimumInterval: TimeInterval = 120 * 24 * 60 * 60
    static let maximumRequests = 3

    enum Key {
        static let requestCount = "review.prompt.requestCount.v1"
        static let lastRequestedAt = "review.prompt.lastRequestedAt.v1"
        static let lastRequestedVersion = "review.prompt.lastRequestedVersion.v1"
    }

    let defaults: UserDefaults
    let appVersion: String

    init(
        defaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
    }

    var requestCount: Int { defaults.integer(forKey: Key.requestCount) }

    /// 保存済みの件数と今の時刻から、評価のお願いを出してよいかを返す。
    func shouldRequest(completedEntries: Int, now: Date = Date()) -> Bool {
        guard completedEntries >= Self.minimumEntries else { return false }
        guard requestCount < Self.maximumRequests else { return false }
        if let version = defaults.string(forKey: Key.lastRequestedVersion), version == appVersion {
            return false
        }
        let last = defaults.double(forKey: Key.lastRequestedAt)
        if last > 0, now.timeIntervalSince1970 - last < Self.minimumInterval {
            return false
        }
        return true
    }

    /// お願いを出したことを記録する。
    func markRequested(now: Date = Date()) {
        defaults.set(requestCount + 1, forKey: Key.requestCount)
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastRequestedAt)
        defaults.set(appVersion, forKey: Key.lastRequestedVersion)
    }
}
