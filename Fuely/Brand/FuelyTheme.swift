import SwiftUI

/// Fuely's brand palette (DECISIONS D1: calm & fresh, deep ocean blue + aqua). Every color is an
/// asset-catalog color set with a light and a dark variant, so views never branch on color scheme.
enum FuelyColor {
    /// Deep ocean blue: headings and brand ink.
    static let ocean = Color(.fuelyOcean)
    /// Water (aqua). Graphics and large text only; body text stays `.primary`/`.secondary`.
    static let water = Color(.fuelyAqua)
    static let sleep = Color(.fuelySleep)
    static let workout = Color(.fuelyWorkout)
    /// Gentle "behind pace" and hint color. Encouraging, not alarming (DECISIONS R4 tone).
    static let nudge = Color(.fuelyNudge)
    /// Filled call-to-action buttons (aqua, dark enough for white text in both modes).
    static let action = Color(.fuelyAction)
    /// Ring and bar tracks, used at low opacity.
    static let track = Color(.fuelyTrack).opacity(0.12)

    /// The calm ocean gradient behind every screen.
    static let background = LinearGradient(
        colors: [Color(.fuelyBackgroundTop), Color(.fuelyBackgroundBottom)],
        startPoint: .top, endPoint: .bottom)
}

/// Spacing and shape tokens (4-pt grid).
enum FuelySpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    /// Screen side margin.
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 18
}

/// Typography: SF Pro Rounded on top of system text styles, so Dynamic Type always applies
/// (DECISIONS D1, D2). The app root also sets `.fontDesign(.rounded)`.
enum FuelyFont {
    /// Big hero numbers (water total, sleep score).
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .bold)
    /// Card values (workout days, ring centre).
    static let value = Font.system(.title2, design: .rounded, weight: .bold)
    static let cardTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .rounded)
    static let detail = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded, weight: .medium)
}

extension View {
    /// The screen background: ocean gradient edge to edge.
    func fuelyScreenBackground() -> some View {
        background(FuelyColor.background.ignoresSafeArea())
    }
}
