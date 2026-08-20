import Testing
@testable import Food4ThoughtCore

@Suite("Goal type decomposition")
struct GoalTypeDecompositionTests {

    @Test("every goal round-trips through the two questions that chose it")
    func roundTripsThroughDirectionAndPace() {
        // Settings reopens a stored goal in these terms. If the round trip
        // moved the goal, opening the editor and pressing Save without touching
        // anything would silently rewrite the user's targets.
        for goal in GoalType.allCases {
            #expect(GoalType(direction: goal.direction, pace: goal.pace) == goal)
        }
    }

    @Test("direction and pace read the way the user picked them")
    func decomposesAsChosen() {
        #expect(GoalType.cut.direction == .lose)
        #expect(GoalType.cut.pace == .aggressive)
        #expect(GoalType.leanBulk.direction == .gain)
        #expect(GoalType.leanBulk.pace == .steady)
        #expect(GoalType.maintain.direction == .maintain)
    }
}
