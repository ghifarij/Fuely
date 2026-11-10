import FuelyCore
import SwiftUI
import UserNotifications

@main
struct FuelyApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            mainView
        }
        // Best effort only (R5): iOS decides whether this ever runs.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }

    /// The normal app: Today with Week and Settings.
    private var mainView: some View {
        RootView()
            .environment(model)
            .onOpenURL { model.handle($0) }
            // Covers launch (the scene becomes active) and every return to the foreground.
            // `refresh` also reschedules the reminders (R5).
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    model.sceneDidBecomeActive()
                    model.reload()
                    Task { await model.refresh() }
                case .background:
                    model.sceneDidEnterBackground()
                    BackgroundRefresh.schedule()
                default:
                    break
                }
            }
    }
}
