import SwiftUI
import Food4ThoughtCore

/// Settings → Your details. The questionnaire's answers, editable.
struct EditDetailsView: View {
    @Bindable var viewModel: EditDetailsViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if viewModel.isLoading {
                Section { ProgressView() }
            } else {
                bodySection
                aboutYouSection
                activitySection
                goalSection
                planSection
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.over)
                }
            }
        }
        .navigationTitle("Your details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { if await viewModel.save() { dismiss() } }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var bodySection: some View {
        Section {
            Picker("Units", selection: metricBinding) {
                Text("Metric").tag(true)
                Text("Imperial").tag(false)
            }
            .pickerStyle(.segmented)

            measurement("Height", text: $viewModel.heightText, unit: viewModel.heightUnit)
            measurement("Weight", text: $viewModel.weightText, unit: viewModel.weightUnit)
        } header: {
            Text("Measurements")
        } footer: {
            // Saying so up front: someone editing their weight here is
            // reporting a weigh-in, and will otherwise wonder why Trends moved.
            Text("Saving records today's weight, so it shows up in Trends too.")
        }
    }

    /// Routed through the model so switching units converts the figures.
    private var metricBinding: Binding<Bool> {
        Binding(
            get: { viewModel.usesMetric },
            set: { viewModel.setUsesMetric($0) }
        )
    }

    private var aboutYouSection: some View {
        Section("About you") {
            DatePicker(
                "Date of birth",
                selection: $viewModel.birthDate,
                in: ...Date.now,
                displayedComponents: .date
            )

            Picker("Sex", selection: $viewModel.sex) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    Text(sex.rawValue.capitalized).tag(sex)
                }
            }
        }
    }

    private var activitySection: some View {
        Section {
            Picker("Activity", selection: $viewModel.activityLevel) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Text(level.onboardingLabel).tag(level)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("How active are you?")
        } footer: {
            Text("Day-to-day movement outside deliberate exercise. Workouts you log are credited separately, on the balance.")
        }
    }

    private var goalSection: some View {
        Section("Goal") {
            Picker("Aiming to", selection: $viewModel.direction) {
                ForEach(GoalDirection.allCases, id: \.self) { direction in
                    Text(direction.onboardingLabel).tag(direction)
                }
            }

            if viewModel.offersPaceChoice {
                Picker("Pace", selection: $viewModel.pace) {
                    ForEach(GoalPace.allCases, id: \.self) { pace in
                        Text(pace.onboardingLabel).tag(pace)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    /// The new plan, before it is saved. Editing a number whose only visible
    /// consequence appears on another screen tomorrow is editing blind.
    @ViewBuilder
    private var planSection: some View {
        if let plan = viewModel.plan {
            Section {
                LabeledContent("Daily calories") {
                    Text("\(plan.dailyCalorieTarget) kcal")
                        .font(Theme.Typography.stat(17, relativeTo: .body))
                }
                LabeledContent("Protein") { Text("\(Int(plan.macros.proteinGrams.rounded())) g") }
                LabeledContent("Carbs") { Text("\(Int(plan.macros.carbsGrams.rounded())) g") }
                LabeledContent("Fat") { Text("\(Int(plan.macros.fatGrams.rounded())) g") }
            } header: {
                Text("New plan")
            } footer: {
                Text(planFooter(plan))
            }
        } else if let problem = viewModel.problem {
            Section {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.over)
            }
        }
    }

    private func planFooter(_ plan: GoalPlan) -> String {
        guard let current = viewModel.currentTarget, current != plan.dailyCalorieTarget else {
            return "Targets are estimates. Days you've already logged keep the targets they were scored against."
        }

        let delta = plan.dailyCalorieTarget - current
        let direction = delta > 0 ? "up" : "down"
        return "That's \(direction) \(abs(delta)) kcal from your current \(current). Days you've already logged keep the targets they were scored against."
    }

    private func measurement(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Theme.Typography.stat(17, relativeTo: .body))
                .frame(width: 90)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkTertiary)
                .frame(width: 28, alignment: .leading)
        }
    }
}
