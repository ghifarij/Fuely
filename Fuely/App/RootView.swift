import SwiftUI

/// Navigation: a single Today screen in a navigation stack. Week and Settings are pushed from
/// the toolbar; onboarding covers everything on first launch (DECISIONS O1, T3).
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
        .sheet(isPresented: $model.isQuickLogPresented) {
            QuickLogSheet()
        }
        // The flag lives in `FuelySettings` (App Group store), the single source of truth.
        .fullScreenCover(isPresented: .constant(model.needsOnboarding)) {
            OnboardingView()
                .fontDesign(.rounded)
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
