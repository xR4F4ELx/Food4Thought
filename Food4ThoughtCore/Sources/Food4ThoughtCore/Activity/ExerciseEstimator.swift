import Foundation

/// The activities the manual logger offers, with the MET each is worth.
///
/// A short list on purpose. `activity_entries.activity_type` is free text so a
/// HealthKit sync can later write its own taxonomy, but a picker with ninety
/// entries is a picker nobody scrolls — these cover what people actually log,
/// and "Other" catches the rest.
///
/// MET values are the Compendium of Physical Activities' published figures for
/// a moderate effort. They are not tuned, guessed, or averaged from anywhere
/// else: an estimate the user cannot check is worse than no estimate.
public enum ExerciseType: String, CaseIterable, Identifiable, Sendable {
    case walking
    case running
    case cycling
    case swimming
    case strength
    case hiit
    case sport
    case yoga
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .walking: "Walk"
        case .running: "Run"
        case .cycling: "Cycle"
        case .swimming: "Swim"
        case .strength: "Strength"
        case .hiit: "HIIT"
        case .sport: "Sport"
        case .yoga: "Yoga"
        case .other: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "dumbbell"
        case .hiit: "figure.highintensity.intervaltraining"
        case .sport: "figure.tennis"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }

    /// Metabolic equivalent of task — multiples of resting energy expenditure.
    public var met: Double {
        switch self {
        case .walking: 3.5   // brisk, ~5 km/h
        case .running: 8.3   // ~8 km/h
        case .cycling: 7.5   // moderate effort
        case .swimming: 5.8  // freestyle, moderate
        case .strength: 5.0  // vigorous free weights
        case .hiit: 8.0
        case .sport: 7.0     // general court/field sport
        case .yoga: 2.5      // hatha
        case .other: 4.0     // unspecified moderate effort
        }
    }
}

/// Estimates the active energy of a workout, and the inverse.
///
/// Every figure this produces is an estimate and is labelled as one wherever it
/// is shown — the schema comment on `activity_entries.active_energy_kcal` says
/// the same thing. It exists because the burn figure is the one number a user
/// without a watch cannot look up, and refusing to offer one would make manual
/// logging a dead end.
public enum ExerciseEstimator {

    /// Used when the profile has no body metrics yet. Roughly the adult mean;
    /// the UI says when it is in play rather than passing the figure off as
    /// personal.
    public static let fallbackWeightKg: Double = 70

    /// Active energy in kcal.
    ///
    /// `(MET − 1)`, not `MET`. A MET is *total* energy including the resting
    /// burn that was happening anyway, and TDEE already prices resting
    /// metabolism — and habitual activity — into the daily target through
    /// `ActivityLevel`. Crediting the full figure would pay the user a second
    /// time for being alive, and would inflate every balance in the app.
    public static func activeKcal(
        for type: ExerciseType,
        minutes: Double,
        weightKg: Double?
    ) -> Double {
        guard minutes > 0 else { return 0 }

        let weight = resolvedWeight(weightKg)
        return (type.met - 1) * weight * (minutes / 60)
    }

    /// How long `kcal` of active energy would take at this activity.
    ///
    /// The inverse of `activeKcal`, deliberately sharing its model so the debt
    /// banner's "≈ 42 min walk clears this" can never disagree with what
    /// logging that walk actually credits.
    public static func minutes(
        toBurn kcal: Double,
        with type: ExerciseType,
        weightKg: Double?
    ) -> Double {
        guard kcal > 0 else { return 0 }

        let weight = resolvedWeight(weightKg)
        let perHour = (type.met - 1) * weight
        guard perHour > 0 else { return 0 }

        return kcal / perHour * 60
    }

    private static func resolvedWeight(_ weightKg: Double?) -> Double {
        guard let weightKg, weightKg > 0 else { return fallbackWeightKg }
        return weightKg
    }
}
