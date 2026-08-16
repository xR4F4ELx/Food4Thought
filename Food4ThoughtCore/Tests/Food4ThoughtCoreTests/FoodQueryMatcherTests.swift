import Foundation
import Testing
@testable import Food4ThoughtCore

/// Every case here is a real USDA response, captured by querying the live API
/// with Singapore hawker dish names. The failures were not misses — USDA
/// returned confident, plausible-looking wrong food, which is the one failure
/// mode a calorie tracker cannot afford.
@Suite("FoodQueryMatcher")
struct FoodQueryMatcherTests {

    private func food(_ name: String, brand: String? = nil) -> FoodItem {
        FoodItem(
            id: .external("1"),
            source: .usdaFDC,
            externalID: "1",
            name: name,
            brand: brand,
            serving: .per100g,
            facts: NutritionFacts(calories: 100, protein: 1, carbs: 1, fat: 1)
        )
    }

    // MARK: - The bug this exists to stop

    @Test("'kaya toast' does not match 'Melba toast'")
    func kayaToastRejectsMelbaToast() {
        #expect(FoodQueryMatcher.matches(food("Melba toast"), query: "kaya toast") == false)
    }

    @Test("'char kway teow' does not match 'CHAR SIU SAUCE' on the word char alone")
    func charKwayTeowRejectsCharSiu() {
        #expect(FoodQueryMatcher.matches(food("CHAR SIU SAUCE, CHAR SIU"), query: "char kway teow") == false)
    }

    @Test("'nasi lemak' does not match a coconut rice spice mix")
    func nasiLemakRejectsSpiceMix() {
        let spiceMix = food("SPICE MIX FOR SINGAPORE COCONUT RICE", brand: "ASIAN HOME GOURMET")
        #expect(FoodQueryMatcher.matches(spiceMix, query: "nasi lemak") == false)
    }

    // MARK: - What must still get through

    @Test("a single-word query matches a result that contains it")
    func laksaMatchesLaksaSoupBase() {
        #expect(FoodQueryMatcher.matches(food("LAKSA SOUP BASE, LAKSA"), query: "laksa"))
    }

    @Test("USDA's verbose descriptions still match a normal query")
    func verboseDescriptionsStillMatch() {
        let usda = food("Chicken, broilers or fryers, breast, meat only, cooked, grilled")
        #expect(FoodQueryMatcher.matches(usda, query: "chicken breast"))
    }

    @Test("matching ignores case")
    func matchingIgnoresCase() {
        #expect(FoodQueryMatcher.matches(food("GREEK YOGURT, PLAIN"), query: "greek yogurt"))
    }

    @Test("a query token matches a longer word starting with it, so plurals survive")
    func prefixMatchHandlesPlurals() {
        #expect(FoodQueryMatcher.matches(food("Roti pratas, frozen"), query: "prata"))
    }

    @Test("punctuation is not something the user should have to get right")
    func punctuationIsIgnored() {
        #expect(FoodQueryMatcher.matches(food("Mums Adobo"), query: "mum's adobo"))
    }

    @Test("the brand counts as searchable text, not just the name")
    func brandIsSearchable() {
        #expect(FoodQueryMatcher.matches(food("GREEK YOGURT", brand: "Chobani"), query: "chobani yogurt"))
    }

    @Test("an empty query gates nothing")
    func emptyQueryGatesNothing() {
        #expect(FoodQueryMatcher.matches(food("Anything at all"), query: "   "))
    }

    @Test("every query token has to land — one match out of two is what let Melba toast through")
    func partialTokenCoverageIsNotEnough() {
        #expect(FoodQueryMatcher.matches(food("Toast, wholemeal"), query: "kaya toast") == false)
    }

    @Test("a known limitation: token coverage cannot tell a dish from its ingredients")
    func documentedLimitation() {
        // "Chicken curry with rice" genuinely contains both tokens, so it
        // survives a search for "chicken rice". That is a far smaller error
        // than Melba toast — it is at least chicken and rice — and closing it
        // would need phrase-order matching this gate deliberately does not do.
        #expect(FoodQueryMatcher.matches(food("Chicken curry with rice"), query: "chicken rice"))
    }
}

@Suite("Ranking applies the gate only where it belongs")
struct FoodSearchRankingGateTests {

    private func suggestion(_ name: String, origin: FoodSuggestion.Origin) -> FoodSuggestion {
        FoodSuggestion(
            item: FoodItem(
                id: origin == .usda ? .external(name) : .stored(UUID()),
                source: origin == .usda ? .usdaFDC : .userCustom,
                externalID: origin == .usda ? name : nil,
                name: name,
                brand: nil,
                serving: .per100g,
                facts: NutritionFacts(calories: 100, protein: 1, carbs: 1, fat: 1)
            ),
            origin: origin
        )
    }

    @Test("a remote result that fails the gate is dropped")
    func remoteMismatchIsDropped() {
        let ranked = FoodSearchRanking.ranked(
            [suggestion("Melba toast", origin: .usda)],
            matching: "kaya toast"
        )

        #expect(ranked.isEmpty)
    }

    @Test("the user's own foods are never gated — they put them there on purpose")
    func localResultsAreNotGated() {
        // Catalogue and recents come from a substring search the user's own
        // query already satisfied, and a favourite is an explicit choice.
        // Second-guessing either would hide food that is genuinely theirs.
        let ranked = FoodSearchRanking.ranked(
            [
                suggestion("Kaya toast set", origin: .favorite),
                suggestion("Melba toast", origin: .catalogue)
            ],
            matching: "kaya toast"
        )

        #expect(ranked.count == 2)
    }

    @Test("with no query nothing is gated, so recents and favourites are untouched")
    func noQueryMeansNoGate() {
        let ranked = FoodSearchRanking.ranked([suggestion("Melba toast", origin: .usda)])
        #expect(ranked.count == 1)
    }
}
