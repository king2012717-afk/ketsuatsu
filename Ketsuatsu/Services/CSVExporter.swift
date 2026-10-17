import Foundation

/// 記録を CSV に書き出す。医師に見せる・表計算で扱うことを想定している。
enum CSVExporter {
    static let header = "日時,収縮期(mmHg),拡張期(mmHg),脈拍(bpm),時間帯,腕,服薬,判定,メモ,入力方法"

    /// 共有用の一時ファイルを置くフォルダの名前の先頭。書き出しのたびに推測しにくい名前のフォルダを作る。
    private static let exportFolderPrefix = "CSVExport-"

    /// 日付の書式を固定する（仕様書 2-19）。暦は端末の設定（和暦など）に関わらず西暦、時刻は端末のタイムゾーン。
    static func makeDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter
    }

    static func csv(from records: [BPRecord], standard: BPStandard) -> String {
        let formatter = makeDateFormatter(format: "yyyy/MM/dd HH:mm")

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
    /// ファイルはアプリ専用の一時領域の、書き出しのたびに作る推測しにくい名前のフォルダに置く（仕様書 2-19）。
    /// 共有が終わったら `removeTemporaryFiles()` で消す。
    static func writeTemporaryFile(records: [BPRecord], standard: BPStandard) throws -> URL {
        removeTemporaryFiles()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFolderPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let name = "血圧記録_\(makeDateFormatter(format: "yyyyMMdd").string(from: Date())).csv"
        let url = folder.appendingPathComponent(name)

        let bom = "\u{FEFF}"
        let content = bom + csv(from: records, standard: standard)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// CSV のフィールドとして安全な形にする。
    /// 書き出した一時ファイルを消す。共有シートを閉じたときに呼ぶ。
    static func removeTemporaryFiles() {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
        guard let entries = try? fileManager.contentsOfDirectory(atPath: temporary.path) else { return }
        for entry in entries where entry.hasPrefix(exportFolderPrefix) {
            try? fileManager.removeItem(at: temporary.appendingPathComponent(entry))
        }
    }

    /// 書き出す前に表示する注意書き（仕様書 2-19：健康情報を含むことを共有前に示す）。
    static let privacyNotice = "書き出したファイルには、血圧・脈拍・服薬・メモなどの健康に関する情報が含まれます。送る相手や保存先にご注意ください。"

    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
