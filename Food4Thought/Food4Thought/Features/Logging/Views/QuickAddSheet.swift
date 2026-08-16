import SwiftUI

/// Calories only — the escape hatch for the meal that would otherwise go
/// unlogged entirely.
///
/// Deliberately offered as a first-class path rather than buried as a failure
/// mode: a rough number today keeps the trend honest, where a skipped entry
/// leaves a hole that reads as a good day.
struct QuickAddSheet: View {
    let slotLabel: String
    let isLogging: Bool
    let onLog: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var calories: Double? {
        let value = Double(text.trimmingCharacters(in: .whitespaces))
        guard let value, value > 0, value <= 10_000 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text("Quick add")
                    .font(Theme.Typography.hero(22))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Adding to \(slotLabel)")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(.top, 20)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $text)
                    .font(Theme.Typography.hero(44))
                    .foregroundStyle(Theme.Palette.ink)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .frame(maxWidth: 160)
                Text("kcal")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(.vertical, 26)

            Text("Macros aren't recorded for a quick add, so this counts toward calories only.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 16)

            Button {
                if let calories { onLog(calories) }
            } label: {
                Group {
                    if isLogging {
                        ProgressView().tint(.white)
                    } else {
                        Text("Log to \(slotLabel)").font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.primaryButtonHeight)
                .background(
                    calories == nil ? Theme.Palette.inkTertiary : Theme.Palette.accent,
                    in: .rect(cornerRadius: Theme.Radius.control)
                )
            }
            .buttonStyle(.plain)
            .disabled(calories == nil || isLogging)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
        .background(Theme.Palette.paper)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
        .onAppear { isFocused = true }
    }
}
