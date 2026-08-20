import Foundation
@testable import Food4Thought

/// Weight history in memory. Shared by the Today and Trends suites.
actor FakeWeightRepository: WeightRepository {
    var stored: [WeighIn]
    private(set) var logged: [(weightKg: Double, recordedAt: Date)] = []
    private var failure: (any Error)?

    /// What counts as "today" for `todaysWeighIn`, held explicitly so a test
    /// does not depend on the clock it happens to run at.
    private let today: Date
    private let calendar: Calendar

    init(
        stored: [WeighIn] = [],
        failure: (any Error)? = nil,
        today: Date = .now,
        calendar: Calendar = .current
    ) {
        self.stored = stored
        self.failure = failure
        self.today = today
        self.calendar = calendar
    }

    func recentWeighIns(userID: UUID, limit: Int) async throws -> [WeighIn] {
        if let failure { throw failure }
        return Array(stored.sorted { $0.recordedAt > $1.recordedAt }.prefix(limit))
    }

    func todaysWeighIn(userID: UUID) async throws -> WeighIn? {
        if let failure { throw failure }
        return stored.first { calendar.isDate($0.recordedAt, inSameDayAs: today) }
    }

    func logWeight(_ weightKg: Double, recordedAt: Date, userID: UUID) async throws {
        if let failure { throw failure }
        logged.append((weightKg, recordedAt))
        stored.append(WeighIn(id: UUID(), recordedAt: recordedAt, weightKg: weightKg))
    }
}
