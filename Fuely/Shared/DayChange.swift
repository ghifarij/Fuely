import Combine
import SwiftUI
import UIKit

extension View {
    /// Runs `action` when the calendar day may have changed while the screen is showing: at local
    /// midnight, after a time zone or clock change, and when the app comes back to the foreground
    /// (a suspended app can miss midnight). Screens use it to re-check what is still today (W7a).
    func onDayChange(perform action: @escaping () -> Void) -> some View {
        modifier(DayChangeModifier(action: action))
    }
}

private struct DayChangeModifier: ViewModifier {
    var action: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    private static let dayChanges = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
        .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
        .receive(on: RunLoop.main)

    func body(content: Content) -> some View {
        content
            .onReceive(Self.dayChanges) { _ in action() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { action() }
            }
    }
}
