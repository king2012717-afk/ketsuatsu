import Foundation

/// 記録を CSV に書き出す。医師に見せる・表計算で扱うことを想定している。
enum CSVExporter {
    static let header = "日時,収縮期(mmHg),拡張期(mmHg),脈拍(bpm),時間帯,腕,服薬,判定,メモ,入力方法"

    static func csv(from records: [BPRecord], standard: BPStandard) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        let rows = records
            .sorted { $0.measuredAt < $1.measuredAt }
            .map { record -> String in
                let fields: [String] = [
                    formatter.string(from: record.measuredAt),
                    String(record.systolic),
                    String(record.diastolic),
                    record.pulse.map(String.init) ?? "",
                    record.slot.title,
                    record.arm == .unspecified ? "" : record.arm.title,
                    record.tookMedication ? "あり" : "",
                    record.category(standard: standard).title,
                    record.note,
                    record.source.title
                ]
                return fields.map(escape).joined(separator: ",")
            }

        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }

    /// 共有シート用に一時ファイルへ書き出す。Excel でも文字化けしないよう BOM を付ける。
    static func writeTemporaryFile(records: [BPRecord], standard: BPStandard) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let name = "血圧記録_\(formatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        let bom = "\u{FEFF}"
        let content = bom + csv(from: records, standard: standard)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// CSV のフィールドとして安全な形にする。
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
