import Foundation
import Observation
import Food4ThoughtCore

/// State for the weigh-in sheet, wherever it is opened from.
///
/// One model for both entry points — the Home prompt and Trends — because a
/// weigh-in is the same act either way, and two of these would be two places
/// for the unit conversion to go wrong.
@Observable
@MainActor
final class WeighInViewModel {

    var draft = WeighInDraft(units: Locale.current.measurementSystem == .metric ? .metric : .imperial)

    private(set) var lastWeighIn: WeighIn?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let userID: UUID
    private let weights: WeightRepository
    private let now: @Sendable () -> Date

    init(
        userID: UUID,
        weights: WeightRepository = SupabaseWeightRepository(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
        self.weights = weights
        self.now = now
    }

    var canSave: Bool { draft.validatedKg != nil && !isSaving }

    /// Shown only once the user has typed something wrong — an empty field
    /// reports `""` so the button is disabled without an accusation.
    var problem: String? {
        guard let problem = draft.problem, !problem.isEmpty else { return nil }
        return problem
    }

    /// Pre-fills with the last recorded weight.
    ///
    /// Weight moves by grams day to day, so the previous figure is nearly the
    /// answer: most weigh-ins become an edit of one digit rather than a typed
    /// number. It is a starting value, not a default — nothing is saved until
    /// the user presses the button.
    func load() async {
        do {
            let previous = try await weights.recentWeighIns(userID: userID, limit: 1).first
            lastWeighIn = previous

            if draft.amount.isEmpty, let previous {
                let display = draft.units == .metric
                    ? previous.weightKg
                    : previous.weightKg / WeighInDraft.kgPerPound
                draft.amount = WeighInDraft.format(display)
            }
        } catch {
            // A missing previous weight costs the user a typed number, not the
            // weigh-in itself, so it is not worth an error banner over.
            lastWeighIn = nil
        }
    }

    func select(units: WeighInDraft.Units) {
        draft = draft.converted(to: units)
    }

    /// Returns whether it landed, so the sheet closes on success and stays up
    /// with what was typed on failure.
    func save() async -> Bool {
        guard let kilograms = draft.validatedKg else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await weights.logWeight(kilograms, recordedAt: now(), userID: userID)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
