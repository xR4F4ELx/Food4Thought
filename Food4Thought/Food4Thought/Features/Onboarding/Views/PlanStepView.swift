import SwiftUI
import Food4ThoughtCore

/// Calories lead; macros are the consequence of the answers, not a fourth
/// decision. No projected finish date — that is a promise the model can't keep.
struct PlanStepView: View {
    let viewModel: OnboardingViewModel
    @State private var isShowingWorking = false

    var body: some View {
        OnboardingStepScaffold(title: OnboardingStep.plan.title) {
            if let plan = viewModel.plan {
                VStack(alignment: .leading, spacing: 24) {
                    headline(for: plan)
                    macros(for: plan)
                    working(for: plan)
                    disclaimer
                }
            } else {
                Text("Something's missing. Go back and check your answers.")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            footer
        }
    }

    private func headline(for plan: GoalPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.dailyCalorieTarget.formatted())
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("calories a day")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func macros(for plan: GoalPlan) -> some View {
        HStack(spacing: 16) {
            macro("Protein", grams: plan.macros.proteinGrams)
            macro("Carbs", grams: plan.macros.carbsGrams)
            macro("Fat", grams: plan.macros.fatGrams)
        }
        .frame(maxWidth: .infinity)
    }

    private func macro(_ label: String, grams: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(grams.rounded()))g").font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Collapsed by default: there so the number doesn't feel arbitrary, not
    /// because anyone needs to read it.
    private func working(for plan: GoalPlan) -> some View {
        DisclosureGroup("How we got there", isExpanded: $isShowingWorking) {
            VStack(alignment: .leading, spacing: 6) {
                // BMI is deliberately absent. It feeds nothing here, and it
                // cannot tell muscle from fat — so on the one screen where the
                // user decides whether to trust these numbers, it can only
                // mislead. Still written to goal_sets for history.
                row("Resting burn (BMR)", value: plan.basalMetabolicRate)
                row("With your activity (TDEE)", value: plan.totalDailyEnergyExpenditure)
            }
            .font(.footnote)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    private func row(_ label: String, value: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(0)))) kcal")
                .monospacedDigit()
        }
    }

    private var disclaimer: some View {
        Text("These are estimates, not medical advice. Talk to a doctor before big changes. Not suitable during pregnancy or breastfeeding.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Start tracking").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.plan == nil || viewModel.isSaving)
        }
        .padding(20)
        .background(.bar)
    }
}
