import SwiftUI
import WidgetKit

/// Every Fuely widget, in one extension (free team: app + 1 extension, DECISIONS P4).
@main
struct FuelyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FuelyTextWidget()
        FuelyLineWidget()
        FuelyRingsWidget()
        FuelyCircleWidget()
        FuelyHomeWidget()
    }
}
