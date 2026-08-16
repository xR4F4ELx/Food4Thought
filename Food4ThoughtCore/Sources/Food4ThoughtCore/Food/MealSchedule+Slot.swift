extension MealSchedule {
    /// The slot a log at `time` belongs to, with nothing asked of the user.
    ///
    /// The centre + button has to guess, and guessing wrong costs a tap on
    /// every entry — which is most of a ten-second budget. The rule: the first
    /// slot that hasn't yet run out its grace period, so 13:15 is still lunch;
    /// and past the last slot it stays there rather than rolling to tomorrow's
    /// breakfast, because an 11 pm log is a late dinner, not an early one.
    public func slot(at time: TimeOfDay, graceMinutes: Int = defaultGraceMinutes) -> MealSlot? {
        let ordered = slots.sorted { $0.typicalTime < $1.typicalTime }
        let now = time.minutesSinceMidnight

        return ordered.first { now <= $0.typicalTime.minutesSinceMidnight + graceMinutes }
            ?? ordered.last
    }
}
