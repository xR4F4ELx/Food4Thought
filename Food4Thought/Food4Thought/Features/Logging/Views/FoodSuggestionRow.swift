import SwiftUI
import Food4ThoughtCore

/// One food in the log list: name, why it's here, calories, and an add button.
struct FoodSuggestionRow: View {
    let suggestion: FoodSuggestion
    let isFavorite: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.item.name)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(calories)
                        .font(Theme.Typography.stat(16))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.Palette.fill, in: .circle)
            }
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.item.name), \(calories) kilocalories per \(portionLabel)")
        .accessibilityHint("Opens the quantity step")
    }

    /// The estimate shown is for the portion the sheet will open on, so the
    /// number on the row is the number the user is about to log.
    private var previewFacts: NutritionFacts {
        PortionStepper(food: suggestion.item, usualServings: suggestion.usualServings).facts
    }

    private var calories: String {
        String(Int(previewFacts.calories.rounded()))
    }

    private var portionLabel: String {
        let stepper = PortionStepper(food: suggestion.item, usualServings: suggestion.usualServings)
        return "\(stepper.displayValue) \(stepper.displayUnit)"
    }

    /// Says why this food is in front of you. A recents-first list that doesn't
    /// explain itself just looks arbitrary.
    private var subtitle: String {
        var parts: [String] = []

        if isFavorite { parts.append("★") }

        switch suggestion.origin {
        case .favorite:
            break
        case .recent(_, let timesLogged) where timesLogged > 1:
            parts.append("Logged \(timesLogged)×")
        case .recent:
            parts.append("Recent")
        case .catalogue:
            break
        case .usda:
            parts.append("USDA")
        }

        if let brand = suggestion.item.brand {
            parts.append(brand)
        }
        parts.append(portionLabel)

        return parts.joined(separator: " · ")
    }
}
