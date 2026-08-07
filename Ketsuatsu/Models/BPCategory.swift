import Foundation
import SwiftUI

/// 判定に使う基準値。家庭血圧と診察室血圧では基準が 5mmHg ずれる（JSH2019）。
enum BPStandard: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case office

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "家庭血圧"
        case .office: return "診察室血圧"
        }
    }

    var footnote: String {
        switch self {
        case .home: return "自宅で測る血圧の基準（高血圧は 135/85mmHg 以上）"
        case .office: return "医療機関で測る血圧の基準（高血圧は 140/90mmHg 以上）"
        }
    }
}

/// 血圧の分類。日本高血圧学会「高血圧治療ガイドライン 2019」の区分に準拠。
enum BPCategory: Int, CaseIterable, Comparable, Identifiable, Sendable {
    case low            // 低血圧
    case normal         // 正常血圧
    case elevated       // 正常高値血圧
    case high           // 高値血圧
    case grade1         // I 度高血圧
    case grade2         // II 度高血圧
    case grade3         // III 度高血圧

    var id: Int { rawValue }

    static func < (lhs: BPCategory, rhs: BPCategory) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .low: return "低血圧"
        case .normal: return "正常血圧"
        case .elevated: return "正常高値血圧"
        case .high: return "高値血圧"
        case .grade1: return "I 度高血圧"
        case .grade2: return "II 度高血圧"
        case .grade3: return "III 度高血圧"
        }
    }

    var shortTitle: String {
        switch self {
        case .low: return "低"
        case .normal: return "正常"
        case .elevated: return "正常高値"
        case .high: return "高値"
        case .grade1: return "I 度"
        case .grade2: return "II 度"
        case .grade3: return "III 度"
        }
    }

    /// 緑 → 琥珀 → コーラル（アイコンと同色）→ ベリー、と段階的に濃くなる配色。
    var color: Color {
        switch self {
        case .low: return Theme.categoryLow
        case .normal: return Theme.categoryNormal
        case .elevated: return Theme.categoryElevated
        case .high: return Theme.categoryHigh
        case .grade1: return Theme.categoryGrade1
        case .grade2: return Theme.categoryGrade2
        case .grade3: return Theme.categoryGrade3
        }
    }

    /// 高血圧に該当するか（I 度以上）。
    var isHypertensive: Bool { self >= .grade1 }

    var advice: String {
        switch self {
        case .low:
            return "血圧が低めです。立ちくらみやだるさが続く場合は医師に相談してください。"
        case .normal:
            return "良好な範囲です。この習慣を続けましょう。"
        case .elevated:
            return "正常範囲ですが油断は禁物です。減塩と運動を意識しましょう。"
        case .high:
            return "高血圧の一歩手前です。生活習慣の見直しをおすすめします。"
        case .grade1:
            return "I 度高血圧です。継続して記録し、医師に相談することをおすすめします。"
        case .grade2:
            return "II 度高血圧です。早めに医療機関を受診してください。"
        case .grade3:
            return "III 度高血圧です。速やかに医療機関を受診してください。"
        }
    }

    /// 収縮期・拡張期のうち高いほうの区分を採用する（ガイドラインの判定方法）。
    static func classify(systolic: Int, diastolic: Int, standard: BPStandard) -> BPCategory {
        let t = Thresholds(standard: standard)

        if systolic >= t.grade3Systolic || diastolic >= t.grade3Diastolic { return .grade3 }
        if systolic >= t.grade2Systolic || diastolic >= t.grade2Diastolic { return .grade2 }
        if systolic >= t.grade1Systolic || diastolic >= t.grade1Diastolic { return .grade1 }
        if systolic >= t.highSystolic || diastolic >= t.highDiastolic { return .high }
        if systolic < t.lowSystolic { return .low }
        if systolic >= t.elevatedSystolic { return .elevated }
        return .normal
    }

    /// 各区分の下限値。
    struct Thresholds {
        let lowSystolic: Int
        let elevatedSystolic: Int
        let highSystolic: Int
        let highDiastolic: Int
        let grade1Systolic: Int
        let grade1Diastolic: Int
        let grade2Systolic: Int
        let grade2Diastolic: Int
        let grade3Systolic: Int
        let grade3Diastolic: Int

        init(standard: BPStandard) {
            switch standard {
            case .home:
                lowSystolic = 90
                elevatedSystolic = 115
                highSystolic = 125
                highDiastolic = 75
                grade1Systolic = 135
                grade1Diastolic = 85
                grade2Systolic = 145
                grade2Diastolic = 90
                grade3Systolic = 160
                grade3Diastolic = 100
            case .office:
                lowSystolic = 90
                elevatedSystolic = 120
                highSystolic = 130
                highDiastolic = 80
                grade1Systolic = 140
                grade1Diastolic = 90
                grade2Systolic = 160
                grade2Diastolic = 100
                grade3Systolic = 180
                grade3Diastolic = 110
            }
        }
    }

    /// 高血圧と判定される境界値（目標値の初期値にも使う）。
    static func hypertensionThreshold(for standard: BPStandard) -> (systolic: Int, diastolic: Int) {
        let t = Thresholds(standard: standard)
        return (t.grade1Systolic, t.grade1Diastolic)
    }
}
