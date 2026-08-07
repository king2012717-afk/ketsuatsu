import Foundation

/// 測定した時間帯。家庭血圧は「朝」「晩」を分けて評価するのが基本のため、
/// 記録ごとに保持して集計・グラフで区別できるようにしている。
enum MeasurementSlot: String, CaseIterable, Codable, Identifiable, Sendable {
    case morning
    case noon
    case evening
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "朝"
        case .noon: return "昼"
        case .evening: return "晩"
        case .other: return "その他"
        }
    }

    var symbolName: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .noon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        case .other: return "clock"
        }
    }

    /// 測定時刻から時間帯を推定する。朝は 3:00〜10:59、昼は 11:00〜16:59、晩は 17:00〜翌 2:59。
    static func inferred(from date: Date, calendar: Calendar = .current) -> MeasurementSlot {
        inferred(fromHour: calendar.component(.hour, from: date))
    }

    static func inferred(fromHour hour: Int) -> MeasurementSlot {
        switch hour {
        case 3..<11: return .morning
        case 11..<17: return .noon
        case 17..<24, 0..<3: return .evening
        default: return .other
        }
    }
}

/// 測定した腕。左右で 10mmHg 前後の差が出ることがあるため記録できるようにしている。
enum MeasurementArm: String, CaseIterable, Codable, Identifiable, Sendable {
    case left
    case right
    case unspecified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "左腕"
        case .right: return "右腕"
        case .unspecified: return "未設定"
        }
    }
}

/// 記録の入力経路。写真から読み取った記録を後から見分けられるようにする。
enum RecordSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case manual
    case photo
    case healthKit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "手入力"
        case .photo: return "写真から読み取り"
        case .healthKit: return "ヘルスケアから取り込み"
        }
    }

    var symbolName: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .photo: return "camera.viewfinder"
        case .healthKit: return "heart.fill"
        }
    }
}
