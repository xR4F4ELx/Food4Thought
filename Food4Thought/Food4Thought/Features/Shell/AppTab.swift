import Foundation

/// The four destinations either side of the centre log button.
///
/// Activity & balance is deliberately absent: the handoff pushes to it from the
/// Home balance affordance and the Trends debt card, so it stays a detail
/// screen rather than becoming a fifth thing to choose between.
enum AppTab: String, CaseIterable, Identifiable {
    case today
    case trends
    case foods
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .trends: "Trends"
        case .foods: "Foods"
        case .settings: "Settings"
        }
    }

    /// The wireframe draws Foods as a circled plus, which reads as a second add
    /// button next to the FAB. A fork and knife says "your foods" without
    /// competing with the primary action.
    var symbolName: String {
        switch self {
        case .today: "square.grid.2x2"
        case .trends: "chart.line.uptrend.xyaxis"
        case .foods: "fork.knife"
        case .settings: "gearshape"
        }
    }

    var selectedSymbolName: String {
        switch self {
        case .today: "square.grid.2x2.fill"
        case .trends: "chart.line.uptrend.xyaxis"
        case .foods: "fork.knife"
        case .settings: "gearshape.fill"
        }
    }
}
