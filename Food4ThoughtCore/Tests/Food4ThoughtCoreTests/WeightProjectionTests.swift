import Foundation
import Testing
@testable import Food4ThoughtCore

private func day(_ offset: Int) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 1 + offset
    components.hour = 8
    return Calendar.current.date(from: components)!
}

@Suite("Weight projection")
struct WeightProjectionTests {

    @Test("a 500 kcal daily deficit predicts about half a kilo a week")
    func deficitPredictsWeeklyLoss() {
        // The rule of thumb the whole line rests on: 7,700 kcal to a kilogram.
        let projection = WeightProjection(anchorDate: day(0), anchorKg: 80, dailyKcalDelta: -500)

        #expect(abs(projection.weeklyKgChange - -0.4545) < 0.001)
        #expect(abs(projection.expectedKg(on: day(7)) - 79.545) < 0.01)
    }

    @Test("a surplus predicts gain, in the same arithmetic")
    func surplusPredictsGain() {
        let projection = WeightProjection(anchorDate: day(0), anchorKg: 70, dailyKcalDelta: 300)

        #expect(projection.expectedKg(on: day(14)) > 70)
        #expect(abs(projection.expectedKg(on: day(14)) - 70.545) < 0.01)
    }

    @Test("maintenance draws a flat line rather than no line")
    func maintenanceIsFlat() {
        let projection = WeightProjection(anchorDate: day(0), anchorKg: 62.5, dailyKcalDelta: 0)

        #expect(projection.expectedKg(on: day(30)) == 62.5)
    }

    @Test("the line starts where the anchor is")
    func anchorDayIsTheAnchorWeight() {
        let projection = WeightProjection(anchorDate: day(0), anchorKg: 80, dailyKcalDelta: -500)

        #expect(projection.expectedKg(on: day(0)) == 80)
    }

    // MARK: - Standing

    @Test("a swing smaller than daily water noise reads as on track")
    func smallDifferencesAreOnTrack() {
        // Being called "behind" on Wednesday and "ahead" on Thursday, for the
        // same behaviour, teaches people to distrust the screen.
        #expect(ProgressStanding(actualKg: 79.6, expectedKg: 79.0, goalIsLoss: true) == .onTrack)
        #expect(ProgressStanding(actualKg: 78.5, expectedKg: 79.0, goalIsLoss: true) == .onTrack)
    }

    @Test("direction decides which side of the line is ahead")
    func directionDecidesAhead() {
        // 2 kg under the line is progress when cutting and a shortfall when
        // bulking — the same number, the opposite meaning.
        #expect(ProgressStanding(actualKg: 77, expectedKg: 79, goalIsLoss: true) == .ahead(kg: 2))
        #expect(ProgressStanding(actualKg: 77, expectedKg: 79, goalIsLoss: false) == .behind(kg: 2))
        #expect(ProgressStanding(actualKg: 81, expectedKg: 79, goalIsLoss: true) == .behind(kg: 2))
        #expect(ProgressStanding(actualKg: 81, expectedKg: 79, goalIsLoss: false) == .ahead(kg: 2))
    }
}
