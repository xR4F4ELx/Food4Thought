import SwiftUI
import Food4ThoughtCore

/// What's in one meal, the way back out of a mistake, and the way to remove the
/// meal itself.
///
/// Logging is designed to be fast enough to be careless, which only works if
/// undoing is equally cheap — a tracker you cannot correct is one people stop
/// trusting and then stop opening. Deleting an entry here rebuilds the balance
/// rollup, exactly as logging does; anything less would leave the debt still
/// counting a meal the user has just taken back.
struct MealDetailSheet: View {
    let group: MealSlotGroup
    let deletingEntryID: UUID?
    /// False when this is the last meal standing — an empty schedule has
    /// nothing to log against and would lock the user out.
    let canRemoveMeal: Bool
    let onDelete: (LoggedEntry) -> Void
    let onRemoveMeal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemoval = false

    var body: some View {
        NavigationStack {
            List {
                entries
                removal
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.paper)
            .navigationTitle(group.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove \(group.label)?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove meal", role: .destructive) {
                    dismiss()
                    onRemoveMeal()
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text(removalWarning)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    // MARK: - Entries

    @ViewBuilder
    private var entries: some View {
        if group.isLogged {
            Section {
                ForEach(group.entries) { entry in
                    row(entry)
                }
                .onDelete { offsets in
                    for index in offsets {
                        onDelete(group.entries[index])
                    }
                }
            } footer: {
                // Adding is deliberately not offered here — the meal row behind
                // this sheet already does it in one tap, and a second entry
                // point would mean swapping one sheet for another mid-dismissal.
                Text("Swipe a row to remove it. Your balance updates with it.")
                    .font(.footnote)
            }
        } else {
            Section {
                Text("Nothing logged yet. Tap the row behind this sheet to add something.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .listRowBackground(Theme.Palette.surface)
            }
        }
    }

    private func row(_ entry: LoggedEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ink)
                Text(subtitle(entry))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }

            Spacer(minLength: 8)

            if deletingEntryID == entry.id {
                ProgressView().controlSize(.small)
            } else {
                Text("\(Int(entry.facts.calories.rounded()))")
                    .font(Theme.Typography.stat(16))
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .listRowBackground(Theme.Palette.surface)
    }

    /// Time first, because on a screen whose job is "which one was the
    /// mistake?" two entries of the same food are told apart by when they
    /// happened, not by what they weighed.
    private func subtitle(_ entry: LoggedEntry) -> String {
        let time = entry.loggedAt.formatted(date: .omitted, time: .shortened)
        let macros = "P \(rounded(entry.facts.protein)) · C \(rounded(entry.facts.carbs)) · F \(rounded(entry.facts.fat))"
        return "\(time) · \(macros)"
    }

    private func rounded(_ value: Double) -> Int { Int(value.rounded()) }

    // MARK: - Removing the meal

    @ViewBuilder
    private var removal: some View {
        if group.isOrphaned {
            Section {
                Text("These were logged to a meal that's no longer on your schedule. They still count toward today.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .listRowBackground(Theme.Palette.surface)
            }
        } else {
            Section {
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    // The destructive role reds the text but leaves the glyph
                    // on the system tint, which reads as two different buttons
                    // sharing a row.
                    Label("Remove this meal", systemImage: "minus.circle")
                        .foregroundStyle(canRemoveMeal ? Theme.Palette.over : Theme.Palette.inkTertiary)
                }
                .disabled(canRemoveMeal == false)
                .listRowBackground(Theme.Palette.surface)
            } footer: {
                if canRemoveMeal {
                    Text(group.isImpromptu
                         ? "A one-day meal. It goes on its own at midnight anyway."
                         : "Takes it off your schedule from now on.")
                        .font(.footnote)
                } else {
                    Text("This is your only meal, so it can't be removed. Add another first.")
                        .font(.footnote)
                }
            }
        }
    }

    /// Said plainly. Removing a meal you have already logged to does not delete
    /// the food, and someone about to tap a destructive button deserves to know
    /// that before they tap it rather than after.
    private var removalWarning: String {
        guard group.isLogged else {
            return "It comes off your schedule. You can add it again any time."
        }
        return "\(countLabel) stay logged and still count toward today — they'll show under “Other”."
    }

    private var countLabel: String {
        group.entries.count == 1 ? "The item you logged here" : "The \(group.entries.count) items you logged here"
    }
}
