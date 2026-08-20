import SwiftUI
import Food4ThoughtCore

/// Log today's weight. One field, one button.
///
/// Deliberately the smallest sheet in the app: the whole reason daily weighing
/// works as a habit is that it costs nothing, and a form would undo that.
struct WeighInSheet: View {
    @Bindable var viewModel: WeighInViewModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                unitPicker
                amountField

                if let problem = viewModel.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.over)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.over)
                }

                Text(context)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                saveButton
            }
            .padding(.horizontal, Theme.Metrics.horizontalPadding)
            .padding(.top, 8)
            .background(Theme.Palette.paper)
            .navigationTitle("Weigh in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.load()
            isAmountFocused = true
        }
    }

    private var unitPicker: some View {
        Picker("Units", selection: unitBinding) {
            ForEach(WeighInDraft.Units.allCases) { units in
                Text(units.label).tag(units)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Goes through the model rather than binding the raw property: switching
    /// units has to convert what is in the field, and a plain binding would
    /// silently reinterpret 74 kg as 74 lb.
    private var unitBinding: Binding<WeighInDraft.Units> {
        Binding(
            get: { viewModel.draft.units },
            set: { viewModel.select(units: $0) }
        )
    }

    private var amountField: some View {
        HStack {
            TextField("Weight", text: $viewModel.draft.amount)
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .font(Theme.Typography.hero(34))
                .foregroundStyle(Theme.Palette.ink)
            Text(viewModel.draft.units.label)
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
    }

    /// Says what the number is for, and when to take it. Without the timing,
    /// the chart collects readings that are not comparable: the same body can
    /// read a kilogram heavier after dinner than it did at breakfast, which is
    /// more than a fortnight of real progress.
    private var context: String {
        guard let last = viewModel.lastWeighIn else {
            return "\(TrendsView.timingAdvice)\n\nYour first weigh-in. Trends needs a couple of weeks of them before it can tell a real change from a heavy dinner."
        }

        let display = viewModel.draft.units == .metric
            ? last.weightKg
            : last.weightKg / WeighInDraft.kgPerPound

        return "Last recorded: \(WeighInDraft.format(display)) \(viewModel.draft.units.label), \(relative(last.recordedAt)).\n\n\(TrendsView.timingAdvice)"
    }

    /// Counted in calendar days rather than elapsed hours, so this agrees with
    /// the prompt on Home that opened it. `RelativeDateTimeFormatter` rounds by
    /// elapsed time, which made the same weigh-in "6 days ago" on one screen
    /// and "5 days ago" on the other.
    private func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0

        return switch days {
        case ..<1: "earlier today"
        case 1: "yesterday"
        default: "\(days) days ago"
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                if await viewModel.save() {
                    onSaved()
                    dismiss()
                }
            }
        } label: {
            Group {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save weigh-in").font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.primaryButtonHeight)
            .background(
                viewModel.canSave ? Theme.Palette.accent : Theme.Palette.inkTertiary,
                in: .rect(cornerRadius: Theme.Radius.control)
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
        .padding(.bottom, 16)
    }
}
