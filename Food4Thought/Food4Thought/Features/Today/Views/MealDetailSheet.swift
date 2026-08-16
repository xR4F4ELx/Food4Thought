import SwiftUI
import Food4ThoughtCore

/// What's in one meal, and the way back out of a mistake.
///
/// Logging is designed to be fast enough to be careless, which only works if
/// undoing is equally cheap — a tracker you cannot correct is one people stop
/// trusting and then stop opening. Deleting here rebuilds the balance rollup,
/// exactly as logging does; anything less would leave the debt still counting
/// a meal the user has just taken back.
struct MealDetailSheet: View {
    let group: MealSlotGroup
    let deletingEntryID: UUID?
    let onDelete: (LoggedEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                    // Adding is deliberately not offered here — the meal row
                    // behind this sheet already does it in one tap, and a
                    // second entry point would mean swapping one sheet for
                    // another mid-dismissal.
                    Text("Swipe a row to remove it. Your balance updates with it.")
                        .font(.footnote)
                }
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
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
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
}
