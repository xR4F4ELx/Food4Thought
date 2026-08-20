import Foundation
import Observation
import Food4ThoughtCore

/// State for editing the answers onboarding gathered.
///
/// The same questions, on one screen instead of seven: this user has already
/// been through the flow and is here to change one number, so making them walk
/// the whole questionnaire again would be a punishment for having grown.
///
/// Saving goes through `complete_onboarding`, the same RPC the questionnaire
/// uses. It closes the open goal set and opens a new one, so history keeps a
/// record of what the targets used to be and when they changed — which is the
/// behaviour recalibration will need anyway.
@Observable
@MainActor
final class EditDetailsViewModel {

    // MARK: - State

    var birthDate = Date()
    var sex: BiologicalSex = .female
    var activityLevel: ActivityLevel = .sedentary
    var direction: GoalDirection = .maintain
    var pace: GoalPace = .steady

    /// Height and weight are text, and carry their own units, for the same
    /// reason onboarding does: the conversion is where the mistakes are.
    var usesMetric = Locale.current.measurementSystem == .metric
    var heightText = ""
    var weightText = ""

    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// What the user's plan looks like right now, before any edits.
    private(set) var currentTarget: Int?

    private var details: ProfileDetails?

    // MARK: - Dependencies

    private let userID: UUID
    private let profiles: ProfileRepository
    private let weights: WeightRepository
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        userID: UUID,
        profiles: ProfileRepository = SupabaseProfileRepository(),
        weights: WeightRepository = SupabaseWeightRepository(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
        self.profiles = profiles
        self.weights = weights
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let details = try await profiles.currentDetails(userID: userID) else {
                errorMessage = "Your details aren't set up yet. Finish onboarding first."
                return
            }
            self.details = details

            birthDate = details.birthDate
            sex = details.sex
            activityLevel = details.activityLevel
            direction = details.goal.direction
            pace = details.goal.pace
            heightText = WeighInDraft.format(displayHeight(details.heightCm))

            let latestWeight = try await weights.recentWeighIns(userID: userID, limit: 1).first
            weightText = latestWeight.map { WeighInDraft.format(displayWeight($0.weightKg)) } ?? ""

            currentTarget = plan?.dailyCalorieTarget
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Derived

    var heightUnit: String { usesMetric ? "cm" : "in" }
    var weightUnit: String { usesMetric ? "kg" : "lb" }

    var offersPaceChoice: Bool { direction.offersPaceChoice }

    /// The plan the current answers produce, recomputed as they are edited so
    /// the user sees what Save is about to do before pressing it.
    var plan: GoalPlan? {
        guard let inputs else { return nil }
        return TDEECalculator.plan(for: inputs, asOf: now(), calendar: calendar)
    }

    var canSave: Bool { inputs != nil && !isSaving }

    /// Nil once every field is usable — the same "unfinished is not an error"
    /// rule the weigh-in sheet follows.
    var problem: String? {
        guard heightCm != nil else { return "Enter your height as a number." }
        guard let weightKg else { return "Enter your weight as a number." }
        guard WeighInDraft.plausibleKg.contains(weightKg) else {
            return "That weight looks off — check the units."
        }
        return nil
    }

    private var inputs: GoalInputs? {
        guard problem == nil, let heightCm, let weightKg, details != nil else { return nil }

        return GoalInputs(
            birthDate: birthDate,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
            goal: GoalType(direction: direction, pace: pace)
        )
    }

    // MARK: - Saving

    /// Returns whether it landed, so the screen dismisses on success and stays
    /// put with the edits on failure.
    func save() async -> Bool {
        guard let inputs, let plan, let details else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await profiles.completeOnboarding(
                OnboardingSubmission(
                    inputs: inputs,
                    plan: plan,
                    // Carried through untouched: meal times are edited on Home,
                    // and re-sending what is stored keeps this screen from
                    // quietly reverting a schedule changed there.
                    mealSchedule: details.mealSchedule,
                    displayName: details.displayName
                )
            )
            currentTarget = plan.dailyCalorieTarget
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    // MARK: - Units

    /// Converts what is in the fields rather than reinterpreting it, so
    /// switching to imperial turns 178 cm into 70 in, not 178 in.
    func setUsesMetric(_ newValue: Bool) {
        guard newValue != usesMetric else { return }

        let currentHeightCm = heightCm
        let currentWeightKg = weightKg
        usesMetric = newValue

        if let currentHeightCm {
            heightText = WeighInDraft.format(displayHeight(currentHeightCm))
        }
        if let currentWeightKg {
            weightText = WeighInDraft.format(displayWeight(currentWeightKg))
        }
    }

    private static let cmPerInch = 2.54

    private var heightCm: Double? {
        guard let entered = number(heightText), entered > 0 else { return nil }
        return usesMetric ? entered : entered * Self.cmPerInch
    }

    private var weightKg: Double? {
        guard let entered = number(weightText), entered > 0 else { return nil }
        return usesMetric ? entered : entered * WeighInDraft.kgPerPound
    }

    private func displayHeight(_ centimetres: Double) -> Double {
        usesMetric ? centimetres : centimetres / Self.cmPerInch
    }

    private func displayWeight(_ kilograms: Double) -> Double {
        usesMetric ? kilograms : kilograms / WeighInDraft.kgPerPound
    }

    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
