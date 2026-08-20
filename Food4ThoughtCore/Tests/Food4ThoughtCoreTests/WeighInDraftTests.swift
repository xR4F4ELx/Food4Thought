import Testing
@testable import Food4ThoughtCore

@Suite("Weigh-in draft")
struct WeighInDraftTests {

    @Test("a metric entry is stored as typed")
    func metricPassesThrough() {
        let draft = WeighInDraft(amount: "74.3", units: .metric)

        #expect(draft.problem == nil)
        #expect(abs((draft.validatedKg ?? 0) - 74.3) < 0.0001)
    }

    @Test("a pounds entry is converted, because the column is kilograms")
    func imperialConvertsToKilograms() {
        // The failure this guards against is silent: 163 written straight into
        // weight_kg looks like a plausible number and only shows up as an
        // impossible trend weeks later.
        let draft = WeighInDraft(amount: "163", units: .imperial)

        #expect(abs((draft.validatedKg ?? 0) - 73.94) < 0.01)
    }

    @Test("a comma decimal is accepted — half the world's keyboards offer one")
    func commaDecimalIsAccepted() {
        let draft = WeighInDraft(amount: "74,3", units: .metric)

        #expect(abs((draft.validatedKg ?? 0) - 74.3) < 0.0001)
    }

    @Test("an empty field is unfinished, not wrong")
    func emptyIsNotAnError() {
        let draft = WeighInDraft(amount: "  ", units: .metric)

        #expect(draft.validatedKg == nil)
        // Reported as a problem so Save stays disabled, but with nothing to say.
        #expect(draft.problem == "")
    }

    @Test("nonsense is refused")
    func nonNumericIsRefused() {
        let draft = WeighInDraft(amount: "seventy", units: .metric)

        #expect(draft.validatedKg == nil)
        #expect(draft.problem?.isEmpty == false)
    }

    @Test("the two typos that matter are caught in both unit systems")
    func implausibleWeightsAreRefused() {
        // A missed decimal point and a doubled digit. Both are numbers, both
        // parse, and both would poison the weight trend.
        #expect(WeighInDraft(amount: "7.4", units: .metric).validatedKg == nil)
        #expect(WeighInDraft(amount: "744", units: .metric).validatedKg == nil)
        #expect(WeighInDraft(amount: "16", units: .imperial).validatedKg == nil)
        #expect(WeighInDraft(amount: "1630", units: .imperial).validatedKg == nil)
    }

    @Test("switching units converts the figure rather than reinterpreting it")
    func switchingUnitsConverts() {
        // 74 kg is 163 lb. Left as "74", the user would save a third of their
        // weight without noticing the field never changed.
        let metric = WeighInDraft(amount: "74", units: .metric)

        let imperial = metric.converted(to: .imperial)

        #expect(imperial.units == .imperial)
        #expect(imperial.amount == "163.1")
        // Within a rounded pound of where it started: the field shows one
        // decimal, so a round trip costs 0.02 kg. That is the display
        // precision doing its job, not drift worth chasing.
        #expect(abs((imperial.validatedKg ?? 0) - 74) < 0.05)
    }

    @Test("switching units on an empty field just switches units")
    func switchingUnitsOnEmptyDraft() {
        let converted = WeighInDraft(amount: "", units: .metric).converted(to: .imperial)

        #expect(converted.amount == "")
        #expect(converted.units == .imperial)
    }
}
