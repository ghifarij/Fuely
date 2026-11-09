import Foundation

extension WaterLogging {
    /// Accepted custom amounts in the quick-log sheet.
    public static let customAmountRangeML = 1...5000

    /// Parses the custom amount field: digits only (spaces and a trailing "ml" allowed), inside
    /// `customAmountRangeML`. nil when it isn't a valid amount.
    public static func parseCustomAmount(_ text: String) -> Int? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("ml") { text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        guard !text.isEmpty, text.allSatisfy(\.isASCIIDigit), text.count <= 6, let value = Int(text),
              customAmountRangeML.contains(value) else { return nil }
        return value
    }
}

extension WaterLog {
    /// The entry Undo removes (DECISIONS W7): the newest Fuely entry, if it is from today.
    /// Yesterday's last drink is not offered for undo.
    public func undoCandidate(now: Date, calendar: Calendar) -> WaterEntry? {
        guard let latest = latestEntry, calendar.isDate(latest.date, inSameDayAs: now) else { return nil }
        return latest
    }
}

/// URLs that open the app at a given place, e.g. from a widget tap (DECISIONS G2: tapping the
/// Line widget's text opens the quick-log sheet).
public enum FuelyDeepLink: String, Sendable, Hashable, CaseIterable {
    case today
    case quickLog = "quick-log"

    public static let scheme = "fuely"

    public var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased(),
              let link = FuelyDeepLink(rawValue: host) else { return nil }
        self = link
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
