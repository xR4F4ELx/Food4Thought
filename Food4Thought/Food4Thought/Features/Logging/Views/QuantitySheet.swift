import SwiftUI
import Food4ThoughtCore

/// Handoff 2d — the one step every add path funnels through.
///
/// It opens on the serving the user usually logs, so the whole sheet is
/// normally a single tap on "Log to <slot>". The stepper is the opt-in
/// precision, not the price of entry.
struct QuantitySheet: View {
    let portion: PortionStepper
    let slotLabel: String
    let isFavorite: Bool
    /// Driven by the view model rather than held locally, so a failed write
    /// releases the button instead of spinning forever.
    let isLogging: Bool
    let onStep: (Bool) -> Void
    let onToggleFavorite: () -> Void
    let onLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            stepper
            macros
            actions
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
        .background(Theme.Palette.paper)
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text(portion.food.name)
                .font(Theme.Typography.hero(22))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("Adding to \(slotLabel)")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(.top, 16)
    }

    private var stepper: some View {
        HStack(spacing: 20) {
            stepButton(isIncrement: false)

            VStack(spacing: 2) {
                Text(portion.displayValue)
                    .font(Theme.Typography.hero(44))
                    .foregroundStyle(Theme.Palette.ink)
                    .contentTransition(.numericText())
                Text(quantityCaption)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .frame(minWidth: 130)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Quantity")
            .accessibilityValue("\(portion.displayValue) \(portion.displayUnit)")

            stepButton(isIncrement: true)
        }
        .padding(.vertical, 20)
    }

    private func stepButton(isIncrement: Bool) -> some View {
        Button {
            onStep(isIncrement)
        } label: {
            Image(systemName: isIncrement ? "plus" : "minus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isIncrement ? .white : Theme.Palette.inkSecondary)
                .frame(width: 44, height: 44)
                .background(isIncrement ? Theme.Palette.accent : Theme.Palette.fill, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isIncrement ? "Increase quantity" : "Decrease quantity")
    }

    /// "your usual" only when it is: claiming a remembered serving the app
    /// never saw would be a small lie the user can check.
    private var quantityCaption: String {
        portion.displayUnit
    }

    private var macros: some View {
        HStack {
            macro(String(Int(portion.facts.calories.rounded())), "kcal", tint: Theme.Palette.accent)
            macro(String(Int(portion.facts.protein.rounded())), "Protein")
            macro(String(Int(portion.facts.carbs.rounded())), "Carbs")
            macro(String(Int(portion.facts.fat.rounded())), "Fat")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
    }

    private func macro(_ value: String, _ label: String, tint: Color = Theme.Palette.ink) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.stat(24, relativeTo: .title3))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 19))
                    .foregroundStyle(isFavorite ? Theme.Palette.carbs : Theme.Palette.inkSecondary)
                    .frame(width: 54, height: Theme.Metrics.primaryButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .stroke(Theme.Palette.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favourites" : "Add to favourites")

            Button(action: onLog) {
                Group {
                    if isLogging {
                        ProgressView().tint(.white)
                    } else {
                        Text("Log to \(slotLabel)")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.primaryButtonHeight)
                .background(Theme.Palette.accent, in: .rect(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(.plain)
            .disabled(isLogging)
        }
        .padding(.top, 16)
    }
}
