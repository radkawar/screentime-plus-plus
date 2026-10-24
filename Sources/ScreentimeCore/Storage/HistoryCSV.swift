import Foundation

public enum HistoryCSV {
    /// RFC 4180 rows, UTC ISO 8601 dates, and locale-independent seconds.
    /// Deleted rules retain their UUID so historical matches remain identifiable.
    public static func encode(_ segments: [Segment], ruleNames: [UUID: String] = [:]) -> String {
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var csv = "start,end,duration_seconds,app,bundle_id,domain,surface,category,rule\r\n"
        for segment in segments {
            let fields = [
                dates.string(from: segment.start), dates.string(from: segment.end),
                String(segment.duration), segment.appName, segment.bundleID,
                segment.domain ?? "", segment.surface ?? "", segment.category.rawValue,
                segment.ruleID.map { ruleNames[$0] ?? $0.uuidString } ?? "",
            ]
            csv += fields.map(quoted).joined(separator: ",") + "\r\n"
        }
        return csv
    }

    private static func quoted(_ field: String) -> String {
        guard field.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
