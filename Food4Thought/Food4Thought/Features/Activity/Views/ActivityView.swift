import SwiftUI
import Food4ThoughtCore

/// Activity & balance — handoff 3a, and 10b when the balance is in credit.
///
/// Not a tab, by design: it is a push from the Home balance affordance, because
/// it is only worth opening when the balance has something to say. Its job is
/// to make the figure actionable — what is owed, what has been burned against
/// it today, and a way to record more.
///
/// 3b's "Connect Apple Health" screen is deliberately absent. HealthKit needs
/// an entitlement this project cannot provision yet, and a button that opens a
/// permission dialog which can never be granted is worse than no button. Manual
/// logging is the whole path for now, and the repository already reads
/// `source` so a sync can slot in beside it.
struct ActivityView: View {
    let userID: UUID

    /// Called after anything that moves the balance, so Home can catch up.
    let onBalanceChanged: () -> Void

    @State private var viewModel: ActivityViewModel?
    @State private var isLogging = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.paper)
        .navigationTitle("Balance")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = ActivityViewModel(userID: userID)
            await model.load()
            viewModel = model
        }
        .sheet(isPresented: $isLogging) {
            if let viewModel {
                LogExerciseSheet(
                    weightKg: viewModel.weightKg,
                    isUsingFallbackWeight: viewModel.isUsingFallbackWeight,
                    isSaving: viewModel.isSaving
                ) { draft in
                    Task {
                        if await viewModel.log(draft) {
                            isLogging = false
                            onBalanceChanged()
                        }
                    }
                }
            }
        }
    }

    private func content(_ viewModel: ActivityViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let balance = viewModel.balance {
                    hero(balance, viewModel)
                }

                ruleLine

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.over)
                }

                logButton
                todayList(viewModel)
            }
            .padding(.horizontal, Theme.Metrics.horizontalPadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Hero

    private func hero(_ balance: BalanceSummary, _ viewModel: ActivityViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(balance.ringLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))

            Text(balance.ringValue)
                .font(Theme.Typography.hero(44))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text(heroCaption(balance, viewModel))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if balance.state == .credit {
                capMeter(balance)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(heroTint(balance), in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    private func heroTint(_ balance: BalanceSummary) -> Color {
        switch balance.state {
        case .debt: Theme.Palette.debt
        case .credit: Theme.Palette.fat
        case .square: Theme.Palette.inkSecondary
        }
    }

    private func heroCaption(_ balance: BalanceSummary, _ viewModel: ActivityViewModel) -> String {
        switch balance.state {
        case .debt:
            let focus = balance.isFocusPartial
                ? "Focus on \(balance.focusToClearKcal) of it for now — the rest waits."
                : "Movement clears it."

            guard let minutes = viewModel.walkMinutesToClearFocus else { return focus }
            return "\(focus) About \(minutes) min of brisk walking would do it — an estimate."

        case .credit:
            return "Banked against your next over-day."

        case .square:
            return "Nothing owed, nothing banked."
        }
    }

    /// 10b's cap meter. The cap is the reason a big workout can read as a
    /// smaller balance, so the screen that shows workouts is where it belongs.
    private func capMeter(_ balance: BalanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * balance.ringFraction)
                }
            }
            .frame(height: 6)

            Text(balance.isAtCreditCap
                 ? "\(balance.creditKcal) / \(BalanceSummary.creditCapKcal) — at the cap. Extra burn stops counting; it's already in your weight trend."
                 : "\(balance.creditKcal) / \(BalanceSummary.creditCapKcal) banked")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: - Rule

    /// The product's central claim, stated on the screen where someone is most
    /// likely to expect the opposite.
    private var ruleLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.inkTertiary)

            Text("Exercise clears debt and builds credit. It never adds to today's food target.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Logging

    private var logButton: some View {
        Button {
            isLogging = true
        } label: {
            Label("Log exercise", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.primaryButtonHeight)
                .background(Theme.Palette.accent, in: .rect(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today

    @ViewBuilder
    private func todayList(_ viewModel: ActivityViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)

                Spacer()

                if viewModel.hasLoggedToday {
                    Text("\(viewModel.burnedTodayKcal) kcal · estimate")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if !viewModel.hasLoggedToday {
                Text("Nothing logged today. A walk counts.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.entries) { entry in
                    row(entry, viewModel)
                    if entry.id != viewModel.entries.last?.id {
                        Divider().overlay(Theme.Palette.line)
                    }
                }
            }
        }
    }

    private func row(_ entry: ActivityEntry, _ viewModel: ActivityViewModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.fat)
                .frame(width: 34, height: 34)
                .background(Theme.Palette.fillSubtle, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)

                Text(subtitle(entry))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }

            Spacer(minLength: 8)

            if viewModel.deletingEntryID == entry.id {
                ProgressView().controlSize(.small)
            } else {
                // Signed positive: burn moves the balance up, toward credit.
                Text("+\(Int(entry.activeKcal.rounded()))")
                    .font(Theme.Typography.stat(16))
                    .foregroundStyle(Theme.Palette.fat)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        // Long press rather than a swipe: swipeActions only works inside a
        // List, and these rows sit in a stack under the hero card.
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    await viewModel.delete(entry)
                    onBalanceChanged()
                }
            } label: {
                Label("Remove workout", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ entry: ActivityEntry) -> String {
        var parts = [entry.startedAt.formatted(date: .omitted, time: .shortened)]
        if let minutes = entry.minutes, minutes > 0 { parts.append("\(minutes) min") }
        parts.append("estimate")
        return parts.joined(separator: " · ")
    }
}
