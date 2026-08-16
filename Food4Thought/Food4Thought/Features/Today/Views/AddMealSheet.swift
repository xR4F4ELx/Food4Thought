import SwiftUI
import Food4ThoughtCore

/// Add a meal to the schedule.
///
/// Onboarding picks a rhythm once, and it is wrong the first time someone eats
/// supper or brings cake into the office. Without this the only way to log an
/// off-pattern meal is to file it under a meal it wasn't — which quietly makes
/// the meal list a worse record than the user's own memory.
///
/// One required field. The time defaults to now, because the overwhelmingly
/// common case is adding the meal you are about to eat.
struct AddMealSheet: View {
    let isSaving: Bool
    let onAdd: (String, TimeOfDay, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var time = Date.now
    @State private var lastsBeyondToday = true
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $label)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                } footer: {
                    Text("Supper, second breakfast, pre-workout — whatever you actually eat.")
                }

                Section {
                    DatePicker(
                        "Usually around",
                        selection: $time,
                        displayedComponents: .hourAndMinute
                    )
                } footer: {
                    Text("Used to guess which meal you're logging when you tap +. Nothing is enforced — a late dinner is still dinner.")
                }

                Section {
                    Picker("Keep it", selection: $lastsBeyondToday) {
                        Text("Every day").tag(true)
                        Text("Just today").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(lastsBeyondToday
                         ? "Stays on your schedule until you remove it."
                         : "Here for today only, then it goes. Anything you log to it is kept.")
                }
            }
            .navigationTitle("Add a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") { onAdd(label, timeOfDay, lastsBeyondToday) }
                            .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { isNameFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private var timeOfDay: TimeOfDay {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return TimeOfDay(hour: parts.hour ?? 12, minute: parts.minute ?? 0)
    }
}
