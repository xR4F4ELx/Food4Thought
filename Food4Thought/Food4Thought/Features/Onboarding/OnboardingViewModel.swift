import Foundation
import Observation
import Food4ThoughtCore

@Observable
@MainActor
final class OnboardingViewModel {

    /// Below this the two paces are the same plan wearing different labels, so
    /// asking would be a decision with no consequence.
    private static let indistinguishablePaceKgPerWeek = 0.05

    /// Mifflin-St Jeor is not validated for children, and the RPC refuses
    /// younger callers outright.
    static let minimumAgeYears = 13

    private(set) var step: OnboardingStep = .aboutYou
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    var draft = OnboardingDraft()

    private let appState: AppState
    private let calendar: Calendar

    init(appState: AppState, calendar: Calendar = .current) {
        self.appState = appState
        self.calendar = calendar
    }

    // MARK: - Derived state

    var latestAllowedBirthDate: Date {
        calendar.date(byAdding: .year, value: -Self.minimumAgeYears, to: .now) ?? .now
    }

    /// Where the wheel opens. The age floor is a terrible starting guess — it
    /// would hand every adult who doesn't scroll an age of 13 — so open near
    /// the middle of the likely range instead.
    var defaultBirthDate: Date {
        calendar.date(byAdding: .year, value: -30, to: .now) ?? latestAllowedBirthDate
    }

    var progress: Double {
        Double(step.rawValue) / Double(OnboardingStep.questionCount)
    }

    var canGoBack: Bool {
        step != .aboutYou && !isSaving
    }

    /// Whether the current screen has enough to move on.
    var canAdvance: Bool {
        switch step {
        case .aboutYou: draft.birthDate != nil && draft.sex != nil
        case .body: draft.heightCm != nil && draft.weightKg != nil
        case .activity: draft.activityLevel != nil
        case .goalDirection: draft.direction != nil
        case .pace, .mealRhythm: true
        case .plan: plan != nil
        }
    }

    /// The plan as it will be stored, or nil while answers are missing.
    var plan: GoalPlan? {
        draft.goalInputs.map { TDEECalculator.plan(for: $0, calendar: calendar) }
    }

    func planPreview(for pace: GoalPace) -> GoalPlan? {
        var preview = draft
        preview.pace = pace
        return preview.goalInputs.map { TDEECalculator.plan(for: $0, calendar: calendar) }
    }

    /// True when the calorie floors have clamped an aggressive target back to
    /// roughly the steady one. Worth saying out loud rather than offering a
    /// choice that changes nothing.
    var pacesAreIndistinguishable: Bool {
        guard let steady = planPreview(for: .steady)?.projectedWeeklyWeightChangeKg,
              let aggressive = planPreview(for: .aggressive)?.projectedWeeklyWeightChangeKg
        else { return false }

        return abs(aggressive - steady) < Self.indistinguishablePaceKgPerWeek
    }

    // MARK: - Navigation

    func advance() {
        guard canAdvance, let next = step(after: step) else { return }
        errorMessage = nil
        step = next
    }

    func goBack() {
        guard canGoBack, let previous = step(before: step) else { return }
        errorMessage = nil
        step = previous
    }

    /// Choice screens commit and move on in one tap.
    func select(_ apply: (inout OnboardingDraft) -> Void) {
        apply(&draft)
        advance()
    }

    private func shouldSkip(_ candidate: OnboardingStep) -> Bool {
        guard candidate == .pace else { return false }
        guard draft.direction?.offersPaceChoice == true else { return true }
        return pacesAreIndistinguishable
    }

    private func step(after current: OnboardingStep) -> OnboardingStep? {
        var next = OnboardingStep(rawValue: current.rawValue + 1)
        while let candidate = next, shouldSkip(candidate) {
            next = OnboardingStep(rawValue: candidate.rawValue + 1)
        }
        return next
    }

    private func step(before current: OnboardingStep) -> OnboardingStep? {
        var previous = OnboardingStep(rawValue: current.rawValue - 1)
        while let candidate = previous, shouldSkip(candidate) {
            previous = OnboardingStep(rawValue: candidate.rawValue - 1)
        }
        return previous
    }

    // MARK: - Saving

    func submit() async {
        guard let inputs = draft.goalInputs, let plan, !isSaving else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await appState.completeOnboarding(
                OnboardingSubmission(
                    inputs: inputs,
                    plan: plan,
                    mealSchedule: draft.mealPreset.schedule
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
