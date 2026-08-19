import Foundation

/// The four destinations either side of the centre log button.
///
/// Activity earns a tab where the food library does not, which is a deliberate
/// departure from the handoff's IA. That IA put Activity behind Trends because
/// it assumed HealthKit would sync workouts on its own, making Activity a place
/// you *review*. Without that entitlement, logging a workout is a daily action —
/// and a daily action does not belong inside a weekly-review tab.
///
/// The food library moves into the log sheet, as the "My foods" shelf. It was
/// always a list of foods to log from that also happened to be editable, and
/// the sheet is where someone is already looking at lists of foods — creating,
/// correcting and removing one now happen next to the search that failed to
/// find it, rather than a tab away.
enum AppTab: String, CaseIterable, Identifiable {
    case today
    case trends
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .trends: "Trends"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "square.grid.2x2"
        case .trends: "chart.line.uptrend.xyaxis"
        case .activity: "figure.walk"
        case .settings: "gearshape"
        }
    }

    var selectedSymbolName: String {
        switch self {
        case .today: "square.grid.2x2.fill"
        case .trends: "chart.line.uptrend.xyaxis"
        case .activity: "figure.walk"
        case .settings: "gearshape.fill"
        }
    }
}
