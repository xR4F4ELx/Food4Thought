import SwiftUI

/// Height and weight, with the unit system defaulted from the device locale so
/// most people never touch the toggle. The only keyboard in the whole flow.
struct BodyStepView: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case height, weight }

    @State private var usesMetric = Locale.current.measurementSystem == .metric
    @State private var heightText = ""
    @State private var weightText = ""

    private var heightUnit: String { usesMetric ? "cm" : "in" }
    private var weightUnit: String { usesMetric ? "kg" : "lb" }

    var body: some View {
        OnboardingStepScaffold(
            title: OnboardingStep.body.title,
            subtitle: "Rough numbers are fine — you can correct them any time."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Units", selection: $usesMetric) {
                    Text("Metric").tag(true)
                    Text("Imperial").tag(false)
                }
                .pickerStyle(.segmented)

                measurementField("Height", text: $heightText, unit: heightUnit, field: .height)
                measurementField("Weight", text: $weightText, unit: weightUnit, field: .weight)
            }
            .onChange(of: usesMetric) { _, _ in reformatForUnitChange() }
            .onChange(of: heightText) { _, _ in syncDraft() }
            .onChange(of: weightText) { _, _ in syncDraft() }
        }
    }

    private func measurementField(
        _ label: String,
        text: Binding<String>,
        unit: String,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium))
            HStack {
                TextField(label, text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: field)
                Text(unit).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Conversion

    private func syncDraft() {
        viewModel.draft.heightCm = Double(heightText).map { usesMetric ? $0 : $0 * 2.54 }
        viewModel.draft.weightKg = Double(weightText).map { usesMetric ? $0 : $0 * 0.45359237 }
    }

    /// Rewrites what is on screen into the newly chosen units rather than
    /// reinterpreting the digits, which would silently change the answer.
    private func reformatForUnitChange() {
        if let heightCm = viewModel.draft.heightCm {
            heightText = format(usesMetric ? heightCm : heightCm / 2.54)
        }
        if let weightKg = viewModel.draft.weightKg {
            weightText = format(usesMetric ? weightKg : weightKg / 0.45359237)
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
