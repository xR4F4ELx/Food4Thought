import SwiftUI
import Food4ThoughtCore

/// One meal in the Home list — handoff 1d.
///
/// Two targets on purpose. The row itself adds to the meal, because that is the
/// common thing to want from Home and the whole product bet is that the common
/// thing costs one tap. Correcting a mistake is rarer, so it gets its own
/// smaller chevron rather than making everyone pass through a detail screen.
struct MealSlotRow: View {
    let group: MealSlotGroup
    let onAdd: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onAdd) {
                HStack(spacing: 12) {
                    icon
                    labels
                    Spacer(minLength: 8)
                    trailing
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Adds food to \(group.label)")

            if group.isLogged {
                Button(action: onOpenDetail) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        // A full 44pt square. At 30 it sat inside the row
                        // button's slop and the row swallowed the tap.
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(group.label) items")
                .accessibilityHint("Shows what's logged, and lets you remove it")
            }
        }
        .padding(.vertical, 8)
    }

    private var icon: some View {
        Image(systemName: group.isLogged ? "circle.fill" : "circle.righthalf.filled")
            .font(.system(size: group.isLogged ? 9 : 15))
            .foregroundStyle(group.isLogged ? Theme.Palette.accent : Theme.Palette.inkTertiary)
            .frame(width: 34, height: 34)
            .background(Theme.Palette.fillSubtle, in: .circle)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)

            if group.isLogged {
                Text(group.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if group.isLogged {
            Text("\(group.totalKcal)")
                .font(Theme.Typography.stat(16))
                .foregroundStyle(Theme.Palette.ink)
        } else {
            Text("+ Add")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.accent)
        }
    }

    private var accessibilityLabel: String {
        guard group.isLogged else { return "\(group.label), nothing logged" }
        return "\(group.label), \(group.summary), \(group.totalKcal) kilocalories"
    }
}
