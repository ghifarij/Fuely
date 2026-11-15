import FuelyCore
import SwiftUI

/// Navigation: a single Today screen in a navigation stack. Week and Settings are pushed from
/// the toolbar; onboarding covers everything on first launch (DECISIONS O1, T3). The weekly recap
/// covers everything too, from the model (WR7 pop-up, WR9 Week button).
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            TodayView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .week: WeekView()
                    case .settings: SettingsView()
                    }
                }
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $model.isQuickLogPresented, onDismiss: model.quickLogDidDismiss) {
            QuickLogSheet()
        }
        // The flag lives in `FuelySettings` (App Group store), the single source of truth.
        .fullScreenCover(isPresented: .constant(model.needsOnboarding)) {
            OnboardingView()
                .fontDesign(.rounded)
        }
        // "Start this week" is the only way out (WR3), so the binding never clears it by itself.
        .fullScreenCover(item: Binding(get: { model.presentedRecap }, set: { if $0 == nil { model.closeRecap() } }),
                         onDismiss: model.recapDidDismiss) { recap in
            WeeklyRecapView(recap: recap, onClose: model.closeRecap)
                .environment(\.calendar, model.calendarForDisplay)
                .onAppear(perform: model.recapDidAppear)
        }
    }
}

enum AppRoute: Hashable {
    case week, settings
}

#Preview("Root") {
    RootView()
        .environment(PreviewData.model(.onTrack))
}
