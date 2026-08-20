import Foundation
@testable import Food4Thought

/// Daily macro totals in memory.
actor FakeMacroHistoryRepository: MacroHistoryRepository {
    var days: [DailyMacros]
    private var failure: (any Error)?

    init(days: [DailyMacros] = [], failure: (any Error)? = nil) {
        self.days = days
        self.failure = failure
    }

    func dailyMacros(userID: UUID, since: Date) async throws -> [DailyMacros] {
        if let failure { throw failure }
        return days.filter { $0.day >= Calendar.current.startOfDay(for: since) }
    }
}
