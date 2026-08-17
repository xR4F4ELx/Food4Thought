import Testing
@testable import Food4ThoughtCore

/// Turning "30 minutes of brisk walking" into a kcal figure.
///
/// This is the one number in the app the user cannot look up, so it is the one
/// the app has to produce — and it feeds the balance, which is the mechanic the
/// whole product turns on. Getting it systematically wrong would inflate
/// everyone's credit.
@Suite("Exercise estimator")
struct ExerciseEstimatorTests {

    // MARK: - The active-energy correction

    @Test("the estimate is active energy, not total energy")
    func subtractsRestingEnergy() {
        // A MET is total energy including the resting burn that was happening
        // anyway. TDEE already prices resting metabolism in, so crediting the
        // whole figure would pay the user twice for lying still.
        //
        // Brisk walking is 3.5 METs. For 70 kg over an hour:
        //   total  = 3.5 × 70 = 245 kcal
        //   active = 2.5 × 70 = 175 kcal
        let estimate = ExerciseEstimator.activeKcal(
            for: .walking,
            minutes: 60,
            weightKg: 70
        )

        #expect(abs(estimate - 175) < 0.5)
    }

    @Test("half the time is half the energy")
    func scalesLinearlyWithDuration() {
        let hour = ExerciseEstimator.activeKcal(for: .running, minutes: 60, weightKg: 70)
        let half = ExerciseEstimator.activeKcal(for: .running, minutes: 30, weightKg: 70)

        #expect(abs(half - hour / 2) < 0.001)
    }

    @Test("a heavier body burns more for the same work")
    func scalesWithWeight() {
        let lighter = ExerciseEstimator.activeKcal(for: .cycling, minutes: 45, weightKg: 60)
        let heavier = ExerciseEstimator.activeKcal(for: .cycling, minutes: 45, weightKg: 90)

        #expect(heavier > lighter)
        #expect(abs(heavier / lighter - 1.5) < 0.001)
    }

    @Test("a gentle activity still burns something")
    func lowMetActivitiesAreNotZero() {
        // Yoga is 2.5 METs, so active energy is 1.5 — small, but not nothing,
        // and rounding it away would make the entry look like it failed.
        let estimate = ExerciseEstimator.activeKcal(for: .yoga, minutes: 60, weightKg: 70)

        #expect(estimate > 0)
        #expect(abs(estimate - 105) < 0.5)
    }

    // MARK: - Guards

    @Test("zero or negative duration is zero, not a negative burn")
    func nonPositiveDurationIsZero() {
        // A negative burn would *add* to the debt, which is the opposite of
        // what logging exercise means.
        #expect(ExerciseEstimator.activeKcal(for: .running, minutes: 0, weightKg: 70) == 0)
        #expect(ExerciseEstimator.activeKcal(for: .running, minutes: -30, weightKg: 70) == 0)
    }

    @Test("a missing weight falls back to a stated default rather than zero")
    func missingWeightUsesADefault() {
        // A zero estimate reads as "that workout counted for nothing". The
        // fallback is documented and the figure is labelled an estimate either
        // way — but the user is told when it is running on a default.
        let withWeight = ExerciseEstimator.activeKcal(for: .running, minutes: 30, weightKg: nil)

        #expect(withWeight > 0)
        #expect(abs(withWeight - ExerciseEstimator.activeKcal(
            for: .running, minutes: 30, weightKg: ExerciseEstimator.fallbackWeightKg
        )) < 0.001)
    }

    @Test("a nonsense weight is ignored in favour of the default")
    func nonPositiveWeightUsesTheDefault() {
        let zero = ExerciseEstimator.activeKcal(for: .running, minutes: 30, weightKg: 0)
        let fallback = ExerciseEstimator.activeKcal(
            for: .running, minutes: 30, weightKg: ExerciseEstimator.fallbackWeightKg
        )

        #expect(abs(zero - fallback) < 0.001)
    }

    // MARK: - The types themselves

    @Test("every activity type has a MET above resting")
    func allTypesBurnSomething() {
        // A MET at or below 1 would make the correction produce zero or a
        // negative, and there is no activity worth logging that qualifies.
        for type in ExerciseType.allCases {
            #expect(type.met > 1, "\(type.rawValue) has a MET of \(type.met)")
        }
    }

    @Test("every activity type is labelled and has an icon")
    func allTypesAreDisplayable() {
        for type in ExerciseType.allCases {
            #expect(type.label.isEmpty == false)
            #expect(type.symbolName.isEmpty == false)
        }
    }

    @Test("the stored value round-trips, since activity_type is free text")
    func typesRoundTripThroughTheColumn() {
        // activity_entries.activity_type is deliberately free text so a future
        // HealthKit sync can write its own taxonomy. That means reading a row
        // back has to tolerate a value this enum has never heard of.
        for type in ExerciseType.allCases {
            #expect(ExerciseType(rawValue: type.rawValue) == type)
        }

        #expect(ExerciseType(rawValue: "HKWorkoutActivityTypeSurfing") == nil)
    }

    // MARK: - Effort, the other direction

    @Test("effort answers how long a burn would take")
    func minutesToBurn() {
        // The debt banner wants "≈ 42 min walk clears this". Same model,
        // inverted, so the two figures can never disagree.
        let minutes = ExerciseEstimator.minutes(toBurn: 175, with: .walking, weightKg: 70)

        #expect(abs(minutes - 60) < 0.5)
    }

    @Test("a burn of nothing takes no time, and never divides by zero")
    func minutesForNothing() {
        #expect(ExerciseEstimator.minutes(toBurn: 0, with: .walking, weightKg: 70) == 0)
        #expect(ExerciseEstimator.minutes(toBurn: -100, with: .walking, weightKg: 70) == 0)
    }
}
