import SwiftUI
import Food4ThoughtCore

struct AboutYouStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    private var birthDate: Binding<Date> {
        Binding(
            get: { viewModel.draft.birthDate ?? viewModel.defaultBirthDate },
            set: { viewModel.draft.birthDate = $0 }
        )
    }

    var body: some View {
        OnboardingStepScaffold(
            title: OnboardingStep.aboutYou.title,
            subtitle: "Both of these feed the calorie formula directly."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date of birth")
                        .font(.subheadline.weight(.medium))
                    DatePicker(
                        "Date of birth",
                        selection: birthDate,
                        in: ...viewModel.latestAllowedBirthDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    // A wheel showing a date reads as a date already chosen, so
                    // commit what it displays rather than greying out Continue
                    // beneath a visibly filled-in field.
                    .onAppear { viewModel.draft.birthDate = birthDate.wrappedValue }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sex")
                        .font(.subheadline.weight(.medium))
                    Text("Used only to pick the right constant in the formula — this isn't a question about gender identity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(BiologicalSex.allCases, id: \.self) { option in
                        OnboardingChoiceRow(
                            title: option.onboardingLabel,
                            isSelected: viewModel.draft.sex == option
                        ) {
                            viewModel.draft.sex = option
                        }
                    }
                }
            }
        }
    }
}

extension BiologicalSex {
    var onboardingLabel: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        }
    }
}
