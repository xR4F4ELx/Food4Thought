import SwiftUI
import Food4ThoughtCore

/// Create a food by hand.
///
/// The screen that makes the app work without a food database at all — home
/// cooking is never in one. Name and calories are the only required fields:
/// for the food this screen exists for, the honest answer to "how much
/// protein" is often a shrug, and demanding one just stops the entry being
/// made at all.
struct CustomFoodSheet: View {
    let isSaving: Bool
    let onSave: (CustomFoodDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = CustomFoodDraft()
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .focused($isNameFocused)
                    TextField("Brand (optional)", text: $draft.brand)
                } footer: {
                    Text("Anything you cook or buy that isn't in the food database.")
                }

                Section("One serving is") {
                    HStack {
                        TextField("Amount", text: $draft.servingAmount)
                            .keyboardType(.decimalPad)
                        TextField("Unit", text: $draft.servingUnit)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }

                Section {
                    field("Calories", text: $draft.calories, unit: "kcal")
                    field("Protein", text: $draft.protein, unit: "g")
                    field("Carbs", text: $draft.carbs, unit: "g")
                    field("Fat", text: $draft.fat, unit: "g")
                } header: {
                    Text("Per serving")
                } footer: {
                    Text("Only calories are required. Leave a macro blank and it counts as zero — a rough entry beats a skipped one.")
                }
            }
            .navigationTitle("New food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { onSave(draft) }
                            .disabled(draft.problem != nil)
                    }
                }
            }
            .onAppear { isNameFocused = true }
        }
        .presentationDragIndicator(.visible)
    }

    private func field(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Theme.Typography.stat(17, relativeTo: .body))
                .frame(width: 80)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkTertiary)
                .frame(width: 32, alignment: .leading)
        }
    }
}
