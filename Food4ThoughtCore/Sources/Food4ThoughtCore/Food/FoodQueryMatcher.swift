import Foundation

/// Decides whether a remote search hit is actually the food that was asked for.
///
/// Remote food databases answer a text query with their best effort, and their
/// best effort on a dish they have never heard of is a confident wrong answer.
/// Querying USDA with Singapore hawker dishes returns Melba toast for "kaya
/// toast", char siu sauce for "char kway teow", and a spice-mix packet for
/// "nasi lemak" — each matched on one shared word.
///
/// That is the one failure a calorie tracker cannot absorb. A miss costs the
/// user a tap on "Create a food"; a plausible wrong match costs them 390 kcal
/// they never ate and never see, in a number they are making decisions on.
///
/// The rule: **every** token in the query has to land somewhere in the food's
/// name or brand. One shared word out of two is exactly what let Melba toast
/// through, so a majority is not enough.
public enum FoodQueryMatcher {

    /// Whether `item` is a defensible answer to `query`.
    ///
    /// A blank query gates nothing, so browsing is never filtered.
    public static func matches(_ item: FoodItem, query: String) -> Bool {
        let wanted = tokens(in: query)
        guard !wanted.isEmpty else { return true }

        let available = tokens(in: "\(item.name) \(item.brand ?? "")")

        return wanted.allSatisfy { want in
            available.contains { $0.hasPrefix(want) }
        }
    }

    /// Lowercased, diacritic-folded, punctuation-free words.
    ///
    /// Punctuation goes because "mum's adobo" and "Mums Adobo" are the same
    /// food, and nobody should have to guess which one a database chose.
    static func tokens(in text: String) -> [String] {
        // Apostrophes are deleted rather than treated as boundaries. Splitting
        // on them turns "mum's" into "mum" + "s", and that orphan "s" then
        // fails to match anything and rejects the food outright.
        let withoutApostrophes = text.filter { $0 != "'" && $0 != "\u{2019}" }

        return withoutApostrophes
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
