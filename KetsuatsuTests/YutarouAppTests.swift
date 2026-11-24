import XCTest
@testable import Ketsuatsu

final class YutarouAppTests: XCTestCase {

    private func decode(iosUrl: String?, iconUrl: String? = "https://yutaroulabs.com/icons/book.png") throws -> YutarouApp {
        var fields: [String: Any] = [
            "id": "book", "name": "うちの本棚", "description": "本の記録", "category": "記録", "published": true,
        ]
        fields["iosUrl"] = iosUrl
        fields["iconUrl"] = iconUrl
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(YutarouApp.self, from: data)
    }

    func testAcceptsAppStoreURL() throws {
        let app = try decode(iosUrl: "https://apps.apple.com/jp/app/id6799039547")

        XCTAssertEqual(app.iosURL?.absoluteString, "https://apps.apple.com/jp/app/id6799039547")
        XCTAssertEqual(try decode(iosUrl: "https://APPS.APPLE.COM/jp/app/id1").iosURL?.host?.lowercased(), "apps.apple.com")
    }

    /// 遷移先は https の App Store のページだけ。それ以外は採用しない（おすすめにも出なくなる）。
    func testRejectsURLsOutsideTheAppStore() throws {
        let rejected = [
            "http://apps.apple.com/jp/app/id6799039547",          // http
            "https://example.com/app",                            // 別のドメイン
            "https://apps.apple.com.example.com/jp/app/id1",      // 似せたドメイン
            "https://example.com/?next=apps.apple.com",
            "itms-apps://apps.apple.com/app/id1",                 // 独自スキーム
            "javascript:alert(1)",
            "apps.apple.com/jp/app/id1",                          // スキームなし
            "",
        ]
        for value in rejected {
            XCTAssertNil(try decode(iosUrl: value).iosURL, value)
        }
        XCTAssertNil(try decode(iosUrl: nil).iosURL)
    }

    /// アイコンは https ならどのドメインでもよいが、http は採用しない。
    func testIconRequiresHTTPS() throws {
        XCTAssertNotNil(try decode(iosUrl: nil, iconUrl: "https://yutaroulabs.com/icons/book.png").iconURL)
        XCTAssertNil(try decode(iosUrl: nil, iconUrl: "http://yutaroulabs.com/icons/book.png").iconURL)
    }

    /// App Store 以外の遷移先を持つアプリは、おすすめの候補から外れる。
    func testRecommendationsSkipAppsWithoutAppStoreURL() throws {
        let valid = try decode(iosUrl: "https://apps.apple.com/jp/app/id1")
        let invalid = try JSONDecoder().decode(YutarouApp.self, from: JSONSerialization.data(withJSONObject: [
            "id": "other", "name": "別のアプリ", "description": "説明", "category": "記録", "published": true,
            "iosUrl": "https://example.com/app",
        ]))

        let selected = YutarouAppsService.selectRecommendations(
            from: [valid, invalid], currentAppID: "ketsuatsu-record", currentCategory: "記録"
        )

        XCTAssertEqual(selected.map(\.id), ["book"])
    }
}
