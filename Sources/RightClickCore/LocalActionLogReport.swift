import Foundation

public enum LocalActionLogReport {
    public static func make(
        hostRecords: [LocalActionRecord],
        extensionRecords: [LocalActionRecord],
        appVersion: String,
        generatedAt: Date = Date(),
        maximumRecordCount: Int = LocalActionLogStore.defaultMaximumRecordCount
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let records = (hostRecords + extensionRecords)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    let leftRank = resultSortRank(lhs.result)
                    let rightRank = resultSortRank(rhs.result)
                    if leftRank != rightRank { return leftRank < rightRank }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.date < rhs.date
            }
            .suffix(max(1, maximumRecordCount))
        var lines = [
            "RightClick Local Action Log",
            "Version: \(appVersion)",
            "Generated: \(formatter.string(from: generatedAt))",
            "Privacy: action names, outcomes, and error categories only; no paths, filenames, commands, arguments, or deep-link URLs.",
            "Timestamp\tSource\tAction\tResult\tError category"
        ]
        lines += records.map { record in
            [
                formatter.string(from: record.date),
                record.source.rawValue,
                record.action.rawValue,
                record.result.rawValue,
                record.errorCategory?.rawValue ?? "-"
            ].joined(separator: "\t")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func resultSortRank(_ result: LocalActionResult) -> Int {
        switch result {
        case .started, .received: 0
        case .forwarded, .succeeded, .failed: 1
        }
    }
}
