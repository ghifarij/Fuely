import Foundation

/// The locale for showing dates and times (DECISIONS D3): the phone's region format, always in
/// English words (P-English only).
public enum DisplayLocale {
    /// The phone's locale, kept as-is when it's English (so its region, 12/24-hour and other
    /// preferences apply), otherwise English with the same region ("nl_NL" → "en_NL").
    public static func english(keepingRegionOf locale: Locale = .autoupdatingCurrent) -> Locale {
        guard locale.language.languageCode != .english else { return locale }
        guard let region = locale.region else { return Locale(identifier: "en") }
        return Locale(languageCode: .english, languageRegion: region)
    }
}
