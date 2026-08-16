import Foundation

/// Adding and removing meals after onboarding.
///
/// The questionnaire picks a schedule once, and it is wrong the first time
/// someone eats supper. These are the edits that let it change without
/// re-running the whole thing — including the one-day meal, which exists so an
/// impromptu birthday cake has somewhere to go that isn't a permanent empty row
/// on Home.
extension MealSchedule {

    /// False when removing would empty the schedule.
    ///
    /// An empty schedule has no slot to log against, and `mealSchedule()`
    /// throws on one, so allowing it would lock the user out of logging.
    public var canRemoveSlot: Bool { slots.count > 1 }

    /// The meals in force on `day`, shares renormalised.
    ///
    /// `day` is an ISO `yyyy-MM-dd` string, compared lexically — which is exact
    /// for that format and avoids dragging a Calendar through the model. The
    /// slot is in force up to and including its expiry day.
    public func active(on day: String) -> MealSchedule {
        let inForce = slots.filter { $0.expiresOn.map { $0 >= day } ?? true }
        guard inForce.count != slots.count else { return normalised() }
        return MealSchedule(slots: inForce).normalised()
    }

    /// Adds a meal and rebalances.
    ///
    /// The new meal takes the average of the existing shares. A share of zero
    /// would make the pace pill expect nothing at supper and read "ahead" the
    /// moment one is eaten; the average keeps an evenly-split schedule evenly
    /// split, which is the only case with an obviously right answer.
    ///
    /// This is a pace heuristic, not a nutrition figure — it moves what the app
    /// expects by a given hour, and never what it claims the user ate.
    public func addingSlot(
        label: String,
        typicalTime: TimeOfDay,
        expiresOn: String? = nil
    ) -> MealSchedule {
        let total = slots.reduce(0) { $0 + $1.expectedShare }
        let share = slots.isEmpty ? 1 : total / Double(slots.count)

        let slot = MealSlot(
            key: Self.uniqueKey(for: label, avoiding: Set(slots.map(\.key))),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            typicalTime: typicalTime,
            expectedShare: share,
            expiresOn: expiresOn
        )

        return MealSchedule(slots: slots + [slot]).normalised()
    }

    /// Removes a meal and rebalances. A no-op when it would empty the schedule,
    /// or when nothing matches.
    ///
    /// Entries already logged to the key keep it — `food_log_entries.meal_key`
    /// is free text and history is never rewritten. They surface under "Other"
    /// on Home rather than disappearing from a day that still counts them.
    public func removingSlot(key: String) -> MealSchedule {
        guard canRemoveSlot, slots.contains(where: { $0.key == key }) else { return self }
        return MealSchedule(slots: slots.filter { $0.key != key }).normalised()
    }

    // MARK: - Keys

    /// A stable, collision-free key derived from the label.
    ///
    /// `meal_key` is free text on the entry, so two meals sharing a key would
    /// silently merge into one row on Home — and the key is what past entries
    /// are already stored against, so it can never be reassigned.
    static func uniqueKey(for label: String, avoiding taken: Set<String>) -> String {
        let base = slug(label)
        guard taken.contains(base) else { return base }

        // Starts at 2 because the unsuffixed key is the first one.
        var suffix = 2
        while taken.contains("\(base)_\(suffix)") { suffix += 1 }
        return "\(base)_\(suffix)"
    }

    private static func slug(_ label: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = label.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }

        let collapsed = String(scalars)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")

        // A label with nothing alphanumeric in it — "🍜" is a perfectly
        // reasonable name for a meal — must still produce a key, or every entry
        // logged to it lands in a slot nothing can look up.
        return collapsed.isEmpty ? "meal" : collapsed
    }
}
