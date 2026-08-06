extension MealSchedule {
    /// Offered during onboarding so nobody has to hand-build a schedule.
    public enum Preset: String, CaseIterable, Sendable {
        case threeMeals = "three_meals"
        case noBreakfast = "no_breakfast"
        case oneMealADay = "one_meal_a_day"
        case timeRestricted16_8 = "time_restricted_16_8"

        public var displayName: String {
            switch self {
            case .threeMeals: "Three meals a day"
            case .noBreakfast: "No breakfast"
            case .oneMealADay: "One meal a day (OMAD)"
            case .timeRestricted16_8: "16:8 eating window"
            }
        }

        public var schedule: MealSchedule {
            switch self {
            case .threeMeals:
                MealSchedule(slots: [
                    MealSlot(key: "breakfast", label: "Breakfast", typicalTime: TimeOfDay(hour: 8, minute: 0), expectedShare: 0.20),
                    MealSlot(key: "lunch", label: "Lunch", typicalTime: TimeOfDay(hour: 12, minute: 30), expectedShare: 0.30),
                    MealSlot(key: "snack", label: "Snack", typicalTime: TimeOfDay(hour: 16, minute: 0), expectedShare: 0.15),
                    MealSlot(key: "dinner", label: "Dinner", typicalTime: TimeOfDay(hour: 19, minute: 0), expectedShare: 0.35)
                ])

            case .noBreakfast:
                MealSchedule(slots: [
                    MealSlot(key: "lunch", label: "Lunch", typicalTime: TimeOfDay(hour: 12, minute: 30), expectedShare: 0.45),
                    MealSlot(key: "snack", label: "Snack", typicalTime: TimeOfDay(hour: 16, minute: 0), expectedShare: 0.15),
                    MealSlot(key: "dinner", label: "Dinner", typicalTime: TimeOfDay(hour: 19, minute: 0), expectedShare: 0.40)
                ])

            case .oneMealADay:
                MealSchedule(slots: [
                    MealSlot(key: "meal", label: "Meal", typicalTime: TimeOfDay(hour: 18, minute: 0), expectedShare: 1.0)
                ])

            case .timeRestricted16_8:
                MealSchedule(slots: [
                    MealSlot(key: "first_meal", label: "First meal", typicalTime: TimeOfDay(hour: 12, minute: 0), expectedShare: 0.40),
                    MealSlot(key: "snack", label: "Snack", typicalTime: TimeOfDay(hour: 15, minute: 30), expectedShare: 0.15),
                    MealSlot(key: "last_meal", label: "Last meal", typicalTime: TimeOfDay(hour: 19, minute: 30), expectedShare: 0.45)
                ])
            }
        }
    }
}
