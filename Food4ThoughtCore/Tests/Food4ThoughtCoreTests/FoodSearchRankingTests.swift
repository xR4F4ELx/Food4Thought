import Foundation
import Testing
@testable import Food4ThoughtCore

@Suite("FoodSearchRanking")
struct FoodSearchRankingTests {

    private func item(
        _ id: FoodItem.Identity,
        name: String,
        externalID: String? = nil,
        source: FoodSource = .usdaFDC
    ) -> FoodItem {
        FoodItem(
            id: id,
            source: source,
            externalID: externalID,
            name: name,
            brand: nil,
            serving: Serving(amount: 100, unit: "g"),
            facts: NutritionFacts(calories: 100, protein: 5, carbs: 10, fat: 2)
        )
    }

    @Test("favourites lead, then recents, then the catalogue, then fresh USDA hits")
    func originOrdering() {
        let suggestions = [
            FoodSuggestion(item: item(.external("4"), name: "USDA hit"), origin: .usda),
            FoodSuggestion(item: item(.stored(UUID()), name: "Catalogue"), origin: .catalogue),
            FoodSuggestion(
                item: item(.stored(UUID()), name: "Recent"),
                origin: .recent(lastLoggedAt: Date(timeIntervalSince1970: 100), timesLogged: 1)
            ),
            FoodSuggestion(item: item(.stored(UUID()), name: "Favourite"), origin: .favorite)
        ]

        let ranked = FoodSearchRanking.ranked(suggestions)

        #expect(ranked.map(\.item.name) == ["Favourite", "Recent", "Catalogue", "USDA hit"])
    }

    @Test("more recent logs sort above older ones")
    func recentsSortByRecency() {
        let older = FoodSuggestion(
            item: item(.stored(UUID()), name: "Older"),
            origin: .recent(lastLoggedAt: Date(timeIntervalSince1970: 100), timesLogged: 9)
        )
        let newer = FoodSuggestion(
            item: item(.stored(UUID()), name: "Newer"),
            origin: .recent(lastLoggedAt: Date(timeIntervalSince1970: 500), timesLogged: 1)
        )

        let ranked = FoodSearchRanking.ranked([older, newer])

        #expect(ranked.map(\.item.name) == ["Newer", "Older"])
    }

    @Test("a USDA hit already cached locally appears once, as the cached row")
    func remoteDuplicatesCollapseIntoTheCachedRow() {
        // Logging the remote copy would insert a second food_items row for the
        // same fdcId, which the unique index rejects — and would split the
        // user's own serving history across two ids.
        let cachedID = UUID()
        let cached = FoodSuggestion(
            item: item(.stored(cachedID), name: "Chicken breast", externalID: "171077"),
            origin: .recent(lastLoggedAt: Date(), timesLogged: 4)
        )
        let remote = FoodSuggestion(
            item: item(.external("171077"), name: "Chicken breast", externalID: "171077"),
            origin: .usda
        )

        let ranked = FoodSearchRanking.ranked([cached, remote])

        #expect(ranked.count == 1)
        #expect(ranked.first?.item.id == .stored(cachedID))
    }

    @Test("the same stored food listed twice keeps its strongest reason for being there")
    func duplicateStoredRowsKeepTheBetterOrigin() {
        let id = UUID()
        let asCatalogue = FoodSuggestion(item: item(.stored(id), name: "Yogurt"), origin: .catalogue)
        let asFavourite = FoodSuggestion(item: item(.stored(id), name: "Yogurt"), origin: .favorite)

        let ranked = FoodSearchRanking.ranked([asCatalogue, asFavourite])

        #expect(ranked.count == 1)
        #expect(ranked.first?.origin == .favorite)
    }

    @Test("the usual serving survives deduplication")
    func usualServingSurvivesDeduplication() {
        let id = UUID()
        let withHistory = FoodSuggestion(
            item: item(.stored(id), name: "Rice"),
            origin: .recent(lastLoggedAt: Date(), timesLogged: 3),
            usualServings: 1.5
        )
        let withoutHistory = FoodSuggestion(item: item(.stored(id), name: "Rice"), origin: .catalogue)

        let ranked = FoodSearchRanking.ranked([withoutHistory, withHistory])

        #expect(ranked.first?.usualServings == 1.5)
    }
}
