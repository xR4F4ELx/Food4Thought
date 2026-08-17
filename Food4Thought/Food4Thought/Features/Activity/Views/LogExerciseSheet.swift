import SwiftUI
import Food4ThoughtCore

/// Record a workout by hand.
///
/// The burn figure is the one number a user without a watch cannot look up, so
/// the app has to offer one — but it is an estimate from a published MET table
/// and the user's own weight, it says so, and it stays editable. Somebody whose
/// watch told them 312 should be able to enter 312.
struct LogExerciseSheet: View {
    let weightKg: Double?
    let isUsingFallbackWeight: Bool
    let isSaving: Bool
    let onLog: (ActivityDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var type: ExerciseType = .walking
    @State private var minutes: Double = 30
    @State private var startedAt = Date.now

    /// Set only once the user overrides the estimate. Nil means "follow the
    /// type and duration", so changing either keeps updating the figure until
    /// they take control of it.
    @State private var overrideKcal: String?

    private static let durations: [Double] = [10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                durationSection
                energySection
            }
            .navigationTitle("Log exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Log") { onLog(draft) }
                            .disabled(resolvedKcal <= 0)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ExerciseType.allCases) { option in
                        let isOn = option == type

                        Button {
                            type = option
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: option.symbolName)
                                    .font(.system(size: 12))
                                Text(option.label)
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(isOn ? .white : Theme.Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isOn ? Theme.Palette.ink : Theme.Palette.fill, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
        } header: {
            Text("What")
        }
    }

    private var durationSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.durations, id: \.self) { option in
                        let isOn = option == minutes

                        Button {
                            minutes = option
                        } label: {
                            Text("\(Int(option)) min")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isOn ? .white : Theme.Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isOn ? Theme.Palette.ink : Theme.Palette.fill, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))

            DatePicker("Started", selection: $startedAt, displayedComponents: .hourAndMinute)
        } header: {
            Text("How long")
        }
    }

    private var energySection: some View {
        Section {
            HStack {
                Text("Active energy")
                Spacer()
                TextField(
                    "\(estimatedKcal)",
                    text: Binding(
                        get: { overrideKcal ?? "\(estimatedKcal)" },
                        set: { overrideKcal = $0 }
                    )
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(Theme.Typography.stat(17, relativeTo: .body))
                .frame(width: 80)

                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .frame(width: 32, alignment: .leading)
            }

            if overrideKcal != nil {
                Button("Use the estimate (\(estimatedKcal) kcal)") {
                    overrideKcal = nil
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.accent)
            }
        } header: {
            Text("Estimate")
        } footer: {
            Text(footnote)
        }
    }

    // MARK: - The figure

    private var estimatedKcal: Int {
        Int(ExerciseEstimator.activeKcal(for: type, minutes: minutes, weightKg: weightKg).rounded())
    }

    private var resolvedKcal: Int {
        guard let overrideKcal else { return estimatedKcal }
        return Int(overrideKcal.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Says plainly what the number is and where it came from. A burn figure
    /// presented as fact would be the same lie as an invented calorie count.
    private var footnote: String {
        let basis = isUsingFallbackWeight
            ? "an average body weight, since yours isn't recorded yet"
            : "your recorded weight"

        return """
        An estimate, from typical effort for this activity and \(basis). \
        Overwrite it if your watch gave you a figure. \
        Exercise clears debt and builds credit — it never adds to today's food target.
        """
    }

    private var draft: ActivityDraft {
        ActivityDraft(
            type: type,
            startedAt: startedAt,
            minutes: minutes,
            activeKcal: Double(resolvedKcal)
        )
    }
}
