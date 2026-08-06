/// Distinct from gender identity — this drives the Mifflin-St Jeor constant only,
/// and must be labelled as such wherever it is collected.
public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case male
    case female

    var mifflinStJeorOffset: Double {
        switch self {
        case .male: 5
        case .female: -161
        }
    }

    var minimumDailyCalories: Double {
        switch self {
        case .male: 1500
        case .female: 1200
        }
    }
}
