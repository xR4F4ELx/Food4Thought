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

    public static func ranked(_ suggestions: [FoodSuggestion]) -> [FoodSuggestion] {
        deduplicated(suggestions).sorted(by: isOrderedBefore)
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
