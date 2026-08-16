import Foundation

/// Merges the several places a food can come from into one list.
///
/// Local history and the USDA API answer the same query independently, so the
/// same food routinely arrives twice — once as a row the user has already
/// logged, once as a fresh remote hit. Showing both is the visible problem;
/// letting the user log the remote copy is the real one, because it splits
/// their serving history across two ids and collides with the unique index on
/// `(source, external_id)`.
public enum FoodSearchRanking {

    /// Merges, deduplicates, and orders. When `query` is given, remote hits
    /// must also survive `FoodQueryMatcher` — see `gated(_:matching:)` for why
    /// only remote ones do.
    public static func ranked(
        _ suggestions: [FoodSuggestion],
        matching query: String? = nil
    ) -> [FoodSuggestion] {
        deduplicated(gated(suggestions, matching: query)).sorted(by: isOrderedBefore)
    }

    /// Applies the match-quality gate to remote results only.
    ///
    /// The user's own foods are exempt on purpose. A favourite is an explicit
    /// choice, and recents and catalogue hits come from a substring search the
    /// query already satisfied — so there is no wrong-food risk to guard
    /// against, and filtering them would hide something that is genuinely
    /// theirs. The gate exists for databases guessing at dishes they do not
    /// have, which is only ever the remote ones.
    private static func gated(
        _ suggestions: [FoodSuggestion],
        matching query: String?
    ) -> [FoodSuggestion] {
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return suggestions
        }

        return suggestions.filter { suggestion in
            switch suggestion.origin {
            case .usda:
                FoodQueryMatcher.matches(suggestion.item, query: query)
            case .favorite, .recent, .catalogue:
                true
            }
        }
    }

    // MARK: - Deduplication

    /// Two suggestions are the same food if they share an identity, or if a
    /// stored row is the cached copy of a remote hit's `external_id`.
    private static func deduplicated(_ suggestions: [FoodSuggestion]) -> [FoodSuggestion] {
        var byKey: [DeduplicationKey: FoodSuggestion] = [:]

        for suggestion in suggestions {
            let key = DeduplicationKey(suggestion.item)
            byKey[key] = byKey[key].map { merged($0, suggestion) } ?? suggestion
        }

        return Array(byKey.values)
    }

    /// Keeps the stored copy, the strongest reason, and any serving history —
    /// each of which may have arrived on a different one of the duplicates.
    private static func merged(_ lhs: FoodSuggestion, _ rhs: FoodSuggestion) -> FoodSuggestion {
        let strongest = lhs.origin.rank <= rhs.origin.rank ? lhs : rhs
        let stored = lhs.item.storedID != nil ? lhs.item : rhs.item

        return FoodSuggestion(
            item: stored,
            origin: strongest.origin,
            usualServings: lhs.usualServings ?? rhs.usualServings
        )
    }

    private struct DeduplicationKey: Hashable {
        private let value: String

        init(_ item: FoodItem) {
            // external_id is what makes a cached USDA row and a live hit the
            // same food; identity alone would never match them.
            if let externalID = item.externalID, item.source == .usdaFDC {
                value = "usda:\(externalID)"
            } else if let stored = item.storedID {
                value = "row:\(stored)"
            } else {
                value = "name:\(item.name.lowercased())"
            }
        }
    }

    // MARK: - Ordering

    private static func isOrderedBefore(_ lhs: FoodSuggestion, _ rhs: FoodSuggestion) -> Bool {
        guard lhs.origin.rank == rhs.origin.rank else {
            return lhs.origin.rank < rhs.origin.rank
        }

        // Within recents, what you ate most recently is the best guess at what
        // you are about to eat — frequency only breaks ties on the same moment.
        if case .recent(let lhsDate, let lhsCount) = lhs.origin,
           case .recent(let rhsDate, let rhsCount) = rhs.origin {
            return lhsDate == rhsDate ? lhsCount > rhsCount : lhsDate > rhsDate
        }

        return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
    }
}
