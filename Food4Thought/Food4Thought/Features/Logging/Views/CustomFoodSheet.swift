import SwiftUI
import Food4ThoughtCore

/// Create a food by hand.
///
/// The screen that makes the app work without a food database at all — home
/// cooking is never in one. Name and calories are the only required fields:
/// for the food this screen exists for, the honest answer to "how much
/// protein" is often a shrug, and demanding one just stops the entry being
/// made at all.
/// Doubles as the edit screen for the "My foods" shelf. The fields, the
/// validation and the "only calories are required" rule are identical either
/// way, so the mode only changes the title, the focus, and what the form says
/// about where the food ends up.
struct CustomFoodSheet: View {
    enum Mode {
        case create
        case edit

        var title: String {
            switch self {
            case .create: "New food"
            case .edit: "Edit food"
            }
        }

        /// Editing starts focused on nothing — the name is already filled in,
        /// and stealing focus into it would put a keyboard over a form the user
        /// came to read before changing one number.
        var focusesName: Bool { self == .create }

        /// Says where the food is about to land. Creating one from the log
        /// sheet looks like it exists only for the meal being logged, and
        /// someone who thinks that will type their recipe in again next week.
        var footer: String {
            switch self {
            case .create:
                "Anything you cook or buy that isn't in the food database. It's saved to My foods, so you can log it again without typing it out."
            case .edit:
                "Changes apply from now on. Meals you've already logged keep the figures they were logged with."
            }
        }
    }

    let isSaving: Bool
    let onSave: (CustomFoodDraft) -> Void

    var mode: Mode = .create

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomFoodDraft
    @FocusState private var isNameFocused: Bool

    init(
        isSaving: Bool,
        draft: CustomFoodDraft = CustomFoodDraft(),
        mode: Mode = .create,
        onSave: @escaping (CustomFoodDraft) -> Void
    ) {
        self.isSaving = isSaving
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .focused($isNameFocused)
                    TextField("Brand (optional)", text: $draft.brand)
                } footer: {
                    Text(mode.footer)
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
            .navigationTitle(mode.title)
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
            .onAppear { isNameFocused = mode.focusesName }
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
