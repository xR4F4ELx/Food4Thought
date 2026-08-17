import Foundation

/// The signed balance, read for display.
///
/// The number itself is produced by `recompute_balance` and is not recomputed
/// here — the cap is path-dependent and the database is its only correct
/// author. This type answers the display questions the raw integer cannot:
/// which of the three states it is in, what to call it, and how much of a debt
/// to put in front of someone right now.
public struct BalanceSummary: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case debt
        case square
        case credit
    }

    /// Mirrors `c_credit_cap` in `recompute_balance`. Declared here only to
    /// label a bound the database already enforces — if these two ever
    /// disagree, the database wins and this constant is the bug.
    public static let creditCapKcal = 500

    /// How many of the user's own over-days the "focus" figure is worth.
    public static let focusDays = 2

    public let kcal: Int

    /// What today added to the debt, for 1e's "Debt +275" ring label.
    public let todayOverageKcal: Int

    /// The user's typical over-day, from their own history. Nil when they have
    /// no over-days on record.
    public let averageDailyOverageKcal: Int?

    public init(
        kcal: Int,
        todayOverageKcal: Int = 0,
        averageDailyOverageKcal: Int? = nil
    ) {
        self.kcal = kcal
        self.todayOverageKcal = max(0, todayOverageKcal)
        // Zero is history that says nothing, so it is folded into "none" —
        // otherwise it would produce a focus of 0 against a real debt, which
        // reads as "nothing to do".
        self.averageDailyOverageKcal = averageDailyOverageKcal.flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: - State

    public var state: State {
        if kcal < 0 { return .debt }
        if kcal > 0 { return .credit }
        return .square
    }

    public var owedKcal: Int { max(0, -kcal) }
    public var creditKcal: Int { max(0, kcal) }

    public var isAtCreditCap: Bool { kcal >= Self.creditCapKcal }

    // MARK: - Focus

    /// The slice of the debt worth aiming at today.
    ///
    /// A debt that rolls indefinitely can reach a figure nobody will ever set
    /// out to clear in one go, and "3,200 owed" is the kind of number people
    /// close the app over. Capping the ask at two of the user's own over-days
    /// keeps it to something a walk can actually move — and it is derived from
    /// their history rather than invented, so it is a figure they can check.
    public var focusToClearKcal: Int {
        guard state == .debt else { return 0 }
        guard let average = averageDailyOverageKcal else { return owedKcal }
        return min(owedKcal, average * Self.focusDays)
    }

    /// True when the focus figure is genuinely smaller than the debt, and so
    /// earns the second number on screen. "480 owed · focus 480" says nothing.
    public var isFocusPartial: Bool {
        state == .debt && focusToClearKcal < owedKcal
    }

    // MARK: - Display

    /// Names which side of zero the figure is on.
    ///
    /// "Balance" alone said nothing — it is the label on a ring whose whole
    /// point is the sign, and a bare number beside a neutral noun leaves the
    /// user to guess whether it is good news.
    ///
    /// Deliberately *not* "surplus". In everyday nutrition language a calorie
    /// surplus is eating more than you burn, which is this model's **debt** —
    /// so using it for a positive balance would state the exact opposite of
    /// what happened. Debt and credit are the terms the rest of the copy
    /// already uses, and neither can be read backwards.
    public var ringLabel: String {
        switch state {
        case .debt: "Cal debt"
        case .credit: "Cal credit"
        case .square: "Cal balance"
        }
    }

    /// Spelled out for VoiceOver, where there is no ring and no colour to carry
    /// the meaning and "cal" is read aloud as a word.
    public var accessibilityDescription: String {
        switch state {
        case .debt: "\(owedKcal) calories owed"
        case .credit: "\(creditKcal) calories in credit"
        case .square: "Level — nothing owed, nothing banked"
        }
    }

    /// Carries the sign, using a proper minus rather than a hyphen: "480" alone
    /// could be either side of zero.
    public var ringValue: String {
        switch state {
        case .debt: "−\(owedKcal)"
        case .credit: "+\(creditKcal)"
        case .square: "0"
        }
    }

    /// 0…1, scaled to the credit cap in both directions.
    ///
    /// One scale for both signs because the cap is the only real bound in the
    /// model. Debt is unbounded, so past a day's worth the ring pegs and says
    /// only "a lot" — the figure beside it carries the precision.
    public var ringFraction: Double {
        min(1, Double(abs(kcal)) / Double(Self.creditCapKcal))
    }
}
