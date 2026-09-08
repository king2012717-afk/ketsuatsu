import Foundation

/// YutarouLabs の公開アプリ情報。
struct YutarouApp: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let category: String
    let iconURL: URL?
    let iosURL: URL?
    let androidURL: URL?
    let published: Bool
    /// 将来の重み付き抽選用。初期版の抽選では使用しない。
    let weight: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case iconURL = "iconUrl"
        case iosURL = "iosUrl"
        case androidURL = "androidUrl"
        case published
        case weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try Self.requiredString(for: .id, in: container)
        name = try Self.requiredString(for: .name, in: container)
        description = try Self.requiredString(for: .description, in: container)
        category = try Self.requiredString(for: .category, in: container)
        iconURL = Self.decodeURL(for: .iconURL, in: container)
        iosURL = Self.decodeURL(for: .iosURL, in: container)
        androidURL = Self.decodeURL(for: .androidURL, in: container)
        published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? false
        weight = max(1, try container.decodeIfPresent(Int.self, forKey: .weight) ?? 1)
    }

    private static func requiredString(
        for key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        let value = try container.decode(String.self, forKey: key)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Required value is empty."
            )
        }
        return value
    }

    private static func decodeURL(
        for key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) -> URL? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key),
              !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }
}
