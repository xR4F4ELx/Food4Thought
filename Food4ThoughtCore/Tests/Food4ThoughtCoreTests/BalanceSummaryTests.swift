import Testing
@testable import Food4ThoughtCore

/// The signed balance, turned into the three things the UI needs: which state
/// it is in, what to call it, and how much of it to put in front of the user
/// right now.
@Suite("Balance summary")
struct BalanceSummaryTests {

    // MARK: - The three states

    @Test("a negative balance is debt owed")
    func negativeIsDebt() {
        let summary = BalanceSummary(kcal: -480)

        #expect(summary.state == .debt)
        #expect(summary.owedKcal == 480)
        #expect(summary.creditKcal == 0)
    }

    @Test("zero is square, and is neither debt nor credit")
    func zeroIsSquare() {
        let summary = BalanceSummary(kcal: 0)

        #expect(summary.state == .square)
        #expect(summary.owedKcal == 0)
        #expect(summary.creditKcal == 0)
    }

    @Test("a positive balance is credit")
    func positiveIsCredit() {
        let summary = BalanceSummary(kcal: 320)

        #expect(summary.state == .credit)
        #expect(summary.creditKcal == 320)
        #expect(summary.owedKcal == 0)
    }

    // MARK: - Focus

    @Test("focus caps the debt at two days of the user's own overage")
    func focusCapsAtTwoDaysOfOverage() {
        // 1e: 755 owed, focus 480, on a user whose over-days run ~240.
        let summary = BalanceSummary(kcal: -755, averageDailyOverageKcal: 240)

        #expect(summary.owedKcal == 755)
        #expect(summary.focusToClearKcal == 480)
        #expect(summary.isFocusPartial)
    }

    @Test("a debt smaller than the cap is shown whole, and is not partial")
    func smallDebtIsNotCapped() {
        // Showing "480 owed · focus 480" twice says nothing; the second figure
        // only earns its place when it is smaller than the first.
        let summary = BalanceSummary(kcal: -300, averageDailyOverageKcal: 240)

        #expect(summary.focusToClearKcal == 300)
        #expect(summary.isFocusPartial == false)
    }

    @Test("with no over-days on record the whole debt is the focus")
    func noOverageHistoryShowsWholeDebt() {
        // Rather than inventing a daily figure. A first over-day has no history
        // to average, and a made-up cap would be a number the user can't check.
        let summary = BalanceSummary(kcal: -755, averageDailyOverageKcal: nil)

        #expect(summary.focusToClearKcal == 755)
        #expect(summary.isFocusPartial == false)
    }

    @Test("an average of zero is treated as no history rather than a zero focus")
    func zeroAverageDoesNotZeroTheFocus() {
        // A focus of 0 against 755 owed would read as "nothing to do".
        let summary = BalanceSummary(kcal: -755, averageDailyOverageKcal: 0)

        #expect(summary.focusToClearKcal == 755)
        #expect(summary.isFocusPartial == false)
    }

    @Test("credit has no focus figure")
    func creditHasNoFocus() {
        let summary = BalanceSummary(kcal: 320, averageDailyOverageKcal: 240)

        #expect(summary.focusToClearKcal == 0)
        #expect(summary.isFocusPartial == false)
    }

    // MARK: - The cap

    @Test("credit at the cap is flagged so the meter can say so")
    func creditAtCapIsFlagged() {
        #expect(BalanceSummary(kcal: 500).isAtCreditCap)
        #expect(BalanceSummary(kcal: 320).isAtCreditCap == false)
        #expect(BalanceSummary(kcal: -480).isAtCreditCap == false)
    }

    @Test("the cap matches the one recompute_balance enforces")
    func capMatchesTheDatabase() {
        // The database is the authority — this constant only labels what it
        // already did. Drifting apart would put a cap meter on the screen that
        // disagrees with the number beside it.
        #expect(BalanceSummary.creditCapKcal == 500)
    }

    // MARK: - Display

    @Test("the ring label names which side of zero the figure is on")
    func ringLabel() {
        // "Balance" alone was the label on a ring whose whole point is the
        // sign, leaving the user to guess whether the number was good news.
        #expect(BalanceSummary(kcal: -480).ringLabel == "Cal debt")
        #expect(BalanceSummary(kcal: 320).ringLabel == "Cal credit")
        #expect(BalanceSummary(kcal: 0).ringLabel == "Cal balance")
    }

    @Test("a positive balance is never called a surplus")
    func creditIsNotCalledSurplus() {
        // In everyday nutrition language a calorie surplus is eating more than
        // you burn — this model's debt. Using it for credit would tell the user
        // the exact opposite of what happened.
        let credit = BalanceSummary(kcal: 320)
        #expect(credit.ringLabel.lowercased().contains("surplus") == false)
        #expect(credit.accessibilityDescription.lowercased().contains("surplus") == false)
    }

    @Test("VoiceOver gets whole words, not the ring's abbreviation")
    func accessibilityDescriptionIsSpokenPlainly() {
        #expect(BalanceSummary(kcal: -480).accessibilityDescription == "480 calories owed")
        #expect(BalanceSummary(kcal: 320).accessibilityDescription == "320 calories in credit")
        #expect(BalanceSummary(kcal: 0).accessibilityDescription.contains("Level"))
    }

    @Test("the ring value carries its sign")
    func ringValueIsSigned() {
        // The sign is the state. "480" alone could be either side of zero.
        #expect(BalanceSummary(kcal: -480).ringValue == "−480")
        #expect(BalanceSummary(kcal: 320).ringValue == "+320")
        #expect(BalanceSummary(kcal: 0).ringValue == "0")
    }

    @Test("today's addition is carried for the banner, not crammed onto the ring")
    func todaysAdditionIsAvailableSeparately() {
        // 1e wanted the day's own contribution on the ring as "Debt +275", but
        // the ring caption has 64pt to say what the figure *is* — which matters
        // more than what today added. The banner below has room and context.
        let summary = BalanceSummary(kcal: -755, todayOverageKcal: 275)
        #expect(summary.ringLabel == "Cal debt")
        #expect(summary.todayOverageKcal == 275)

        let quiet = BalanceSummary(kcal: -755, todayOverageKcal: 0)
        #expect(quiet.todayOverageKcal == 0)
    }

    @Test("the ring is scaled to the credit cap in both directions")
    func ringFraction() {
        // One scale for both signs, and the cap is the only figure in the model
        // that is a real bound. 10a draws +320 at roughly two thirds, which is
        // 320/500. Debt is unbounded, so past a day's worth the ring says only
        // "a lot" and the number beside it carries the precision.
        #expect(abs(BalanceSummary(kcal: 320).ringFraction - 0.64) < 0.001)
        #expect(BalanceSummary(kcal: 500).ringFraction == 1)
        #expect(BalanceSummary(kcal: 0).ringFraction == 0)

        #expect(abs(BalanceSummary(kcal: -240).ringFraction - 0.48) < 0.001)
        #expect(BalanceSummary(kcal: -755).ringFraction == 1)
    }
}
