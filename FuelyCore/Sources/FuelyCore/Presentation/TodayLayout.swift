import Foundation

/// The one drink row Today shows under the water card (DECISIONS T5), and whether "Show All"
/// appears beside the "Today's drinks" title.
public enum TodayDrinkRow: Equatable, Sendable {
    /// Today's newest drink logged in Fuely (swipe to delete, W7).
    case fuely(WaterEntry)
    /// No Fuely drink yet, but water from other apps today: the read-only row.
    case otherApps(ml: Int)
    /// Nothing today: "No drinks logged yet today."
    case none

    /// `entries` are today's Fuely drinks in any order; `externalML` is other apps' water today.
    public init(entries: [WaterEntry], externalML: Int) {
        if let newest = entries.max(by: { $0.date < $1.date }) {
            self = .fuely(newest)
        } else if externalML > 0 {
            self = .otherApps(ml: externalML)
        } else {
            self = .none
        }
    }

    /// "Show All" appears whenever there is at least one drink today, even just one (T5).
    public var showsAll: Bool { self != .none }
}

/// Today's size rules (DECISIONS T4d, T5a): the drinks title and its row stay above the fold on
/// every supported iPhone, so the drop shrinks on short screens.
public enum TodayLayout {
    /// The drop at the default text size on regular screens.
    public static let regularDropHeight = 176.0
    /// The cap for large text sizes on regular screens (T4d).
    public static let maxDropHeight = 220.0
    /// The drop at the default text size on short screens (T5a).
    public static let compactDropHeight = 140.0
    /// The cap for large text sizes on short screens; Today scrolls there anyway.
    public static let compactMaxDropHeight = 176.0
    /// Screens up to this height (points, whole screen) count as short: the 4.7" iPhone SE
    /// (667) and Display Zoom on the smaller Face ID iPhones (693).
    public static let shortScreenMaxHeight = 700.0

    /// Whether a screen of this height (points) is short. 0 (not measured yet) is not.
    public static func isShortScreen(height: Double) -> Bool {
        height > 0 && height <= shortScreenMaxHeight
    }

    /// The drop height for a Dynamic Type–scaled height (`regularDropHeight` at the default text
    /// size) on a screen of `screenHeight` points.
    public static func dropHeight(scaledHeight: Double, screenHeight: Double) -> Double {
        guard isShortScreen(height: screenHeight) else { return min(scaledHeight, maxDropHeight) }
        return min(scaledHeight * compactDropHeight / regularDropHeight, compactMaxDropHeight)
    }
}
