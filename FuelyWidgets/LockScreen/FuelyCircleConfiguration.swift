import AppIntents
import FuelyCore
import WidgetKit

/// What Fuely Circle shows (DECISIONS G4): the water ring with (+), the sleep score, or workouts x/y.
enum CircleMetricOption: String, AppEnum {
    case water, sleep, workouts

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Metric" }

    static var caseDisplayRepresentations: [CircleMetricOption: DisplayRepresentation] {
        [
            .water: DisplayRepresentation(title: "Water", subtitle: "Ring with (+) to log water",
                                          image: .init(systemName: "drop.fill")),
            .sleep: DisplayRepresentation(title: "Sleep score", image: .init(systemName: "moon.zzz.fill")),
            .workouts: DisplayRepresentation(title: "Workouts", subtitle: "Workout days this week",
                                             image: .init(systemName: "figure.run")),
        ]
    }

    var metric: WidgetMetric {
        switch self {
        case .water: .water
        case .sleep: .sleep
        case .workouts: .workouts
        }
    }
}

struct FuelyCircleConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Fuely Circle" }
    static var description: IntentDescription { "Choose what the circle shows." }

    @Parameter(title: "Show", default: .water)
    var metric: CircleMetricOption

    init() {}

    init(metric: CircleMetricOption) {
        self.metric = metric
    }
}
