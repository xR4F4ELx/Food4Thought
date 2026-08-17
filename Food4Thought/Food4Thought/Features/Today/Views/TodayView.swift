import SwiftUI
import Food4ThoughtCore

/// Home / Today — handoff 1d (on track), 1e (over target), 10a (in credit),
/// and 7a (first run).
///
/// One screen rather than three: the states differ only in what the figures
/// say, and branching the layout would let them drift apart. The rule the
/// design turns on is that **exercise never inflates today's food target** — so
/// the calorie ring here reads `goal_sets.daily_calorie_target` and nothing
/// else, and the balance sits beside it as a separate, signed figure.
struct TodayView: View {
    let userID: UUID

    @State private var viewModel: TodayViewModel?
    @State private var route: Route?

    /// A sheet queued to open as soon as the current one has finished closing.
    ///
    /// Assigning `route` while a sheet is dismissing drops the new one on the
    /// floor — there is a single presentation slot and the outgoing sheet still
    /// owns it. `onDismiss` is the point where it is free again.
    @State private var queuedRoute: Route?

    /// A single route rather than several `.sheet` modifiers stacked on one
    /// view — SwiftUI only reliably honours one, and the failure mode is a
    /// button that silently does nothing.
    private enum Route: Identifiable {
        case log(slotKey: String?)
        case detail(MealSlotGroup)
        case addMeal

        var id: String {
            switch self {
            case .log(let slotKey): "log-\(slotKey ?? "auto")"
            case .detail(let group): "detail-\(group.key)"
            case .addMeal: "add-meal"
            }
        }
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.paper)
        .task {
            guard viewModel == nil else { return }
            let model = TodayViewModel(userID: userID)
            await model.load()
            viewModel = model
        }
        .sheet(item: $route, onDismiss: {
            guard let next = queuedRoute else { return }
            queuedRoute = nil
            // One runloop turn later, not inside `onDismiss` itself. The
            // callback fires while the outgoing sheet is still tearing down and
            // still holds the single presentation slot, so assigning here is
            // swallowed and the next sheet silently never appears.
            DispatchQueue.main.async { route = next }
        }) { presented in
            switch presented {
            case .log(let slotKey):
                LogFoodSheet(userID: userID, initialSlotKey: slotKey)
                    .onDisappear { Task { await viewModel?.load() } }
            case .detail(let group):
                detailSheet(for: group)
            case .addMeal:
                AddMealSheet(isSaving: viewModel?.isSavingSchedule ?? false) { label, time, lasts in
                    Task {
                        await viewModel?.addMeal(
                            label: label,
                            typicalTime: time,
                            lastsBeyondToday: lasts
                        )
                        route = nil
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ viewModel: TodayViewModel) -> some View {
        if viewModel.snapshot == nil {
            unavailable(viewModel)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                rings(viewModel)
                paceRow(viewModel)
                balanceCallout(viewModel)
                if let error = viewModel.errorMessage { errorNote(error) }
                mealList(viewModel)
            }
            .padding(.horizontal, Theme.Metrics.horizontalPadding)
        }
    }

    private func unavailable(_ viewModel: TodayViewModel) -> some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Text(viewModel.errorMessage ?? "Today couldn't be loaded.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await viewModel.load() } }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.Palette.fill, in: .capsule)
        }
        .padding(.top, 8)
    }

    // MARK: - Rings

    @ViewBuilder
    private func rings(_ viewModel: TodayViewModel) -> some View {
        if let progress = viewModel.progress, let balance = viewModel.balance {
            HStack(spacing: 14) {
                calorieRing(progress, isFirstRun: viewModel.isFirstRunOfDay)

                // The grid's columns size to their content, so this spacing is
                // the *only* gap between rings. At 4 the strokes — which paint
                // half a line width outside the 64pt frame — ran into each
                // other and the four read as one blob.
                Grid(horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        macroRing(progress, .protein, tint: Theme.Palette.protein)
                        macroRing(progress, .carbs, tint: Theme.Palette.carbs)
                    }
                    GridRow {
                        macroRing(progress, .fat, tint: Theme.Palette.fat)
                        balanceRing(balance)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
        }
    }

    private func calorieRing(_ progress: DayProgress, isFirstRun: Bool) -> some View {
        ProgressRing(
            fraction: progress.calorieFraction,
            tint: progress.isOverTarget ? Theme.Palette.over : Theme.Palette.accent,
            track: progress.isOverTarget
                ? Theme.Palette.over.opacity(0.16)
                : Theme.Palette.fill,
            lineWidth: Theme.Metrics.calorieRingStroke
        ) {
            VStack(spacing: 1) {
                Text(progress.isOverTarget
                     ? "−\(formatted(abs(progress.remainingKcal)))"
                     : formatted(progress.remainingKcal))
                    .font(Theme.Typography.hero(progress.isOverTarget ? 36 : 38))
                    .foregroundStyle(progress.isOverTarget ? Theme.Palette.over : Theme.Palette.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(progress.isOverTarget ? "over today" : "kcal left")
                    .font(.caption)
                    .foregroundStyle(progress.isOverTarget ? Theme.Palette.over : Theme.Palette.inkSecondary)

                // 7a's rings are at rest, so the subcaption says what to do
                // rather than restating a total of zero.
                Text(isFirstRun
                     ? "to log"
                     : "\(formatted(progress.consumedKcal)) of \(formatted(progress.target))")
                    .font(Theme.Typography.stat(11, relativeTo: .caption2))
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: 152, height: 152)
        .accessibilityHidden(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue(progress.isOverTarget
            ? "\(abs(progress.remainingKcal)) over your \(progress.target) target"
            : "\(progress.remainingKcal) left of \(progress.target)")
    }

    private func macroRing(_ progress: DayProgress, _ macro: Macro, tint: Color) -> some View {
        MacroRing(
            value: progress.grams(of: macro),
            target: progress.targetGrams(of: macro),
            label: macro.label,
            fraction: progress.fraction(of: macro),
            tint: tint,
            isOver: progress.isOver(macro)
        )
    }

    /// The signed balance. One ring, three states, switching at zero — debt in
    /// slate, credit in green, and the label carrying the day's own addition.
    private func balanceRing(_ balance: BalanceSummary) -> some View {
        VStack(spacing: 2) {
            ProgressRing(
                fraction: balance.ringFraction,
                tint: balanceTint(balance),
                track: balance.state == .credit
                    ? Theme.Palette.credit.opacity(0.16)
                    : Theme.Palette.fill,
                lineWidth: Theme.Metrics.macroRingStroke
            ) {
                Text(balance.ringValue)
                    .font(Theme.Typography.stat(13, relativeTo: .caption))
                    .foregroundStyle(balanceTint(balance))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
            }
            .frame(width: 64, height: 64)

            Text(balance.ringLabel)
                .font(.caption2.weight(balance.state == .square ? .regular : .semibold))
                .foregroundStyle(balance.state == .square
                    ? Theme.Palette.inkSecondary
                    : balanceTint(balance))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calorie balance")
        .accessibilityValue(balance.accessibilityDescription)
    }

    private func debtExplanation(_ balance: BalanceSummary) -> String {
        let today = balance.todayOverageKcal > 0
            ? "\(formatted(balance.todayOverageKcal)) of that came from today. "
            : ""

        let clearing = balance.isFocusPartial
            ? "Clear the focus figure and the rest waits — movement clears it, and it never adds to today's food."
            : "Movement clears it. It never adds to today's food target."

        return today + clearing
    }

    private func balanceTint(_ balance: BalanceSummary) -> Color {
        switch balance.state {
        case .debt: Theme.Palette.debt
        case .credit: Theme.Palette.credit
        case .square: Theme.Palette.inkSecondary
        }
    }

    // MARK: - Pace

    @ViewBuilder
    private func paceRow(_ viewModel: TodayViewModel) -> some View {
        if let pace = viewModel.pace {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(paceTint(pace))
                        .frame(width: 7, height: 7)
                    Text("\(pace.label) · \(formatted(pace.consumedKcal)) eaten")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.ink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.Palette.fill, in: .capsule)

                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func paceTint(_ pace: PaceStatus) -> Color {
        switch pace.state {
        case .onPace: Theme.Palette.fat
        case .ahead: Theme.Palette.carbs
        case .behind: Theme.Palette.inkTertiary
        }
    }

    // MARK: - Balance callout

    /// 1e's debt banner and 10a's credit note.
    ///
    /// Neither pushes anywhere yet: Activity (3a/3b) is not built, and a "▸"
    /// that goes nowhere is worse than no affordance at all. The figures are
    /// the point and they are all here.
    @ViewBuilder
    private func balanceCallout(_ viewModel: TodayViewModel) -> some View {
        if let balance = viewModel.balance {
            switch balance.state {
            case .debt:
                debtBanner(balance)
            case .credit:
                creditNote(balance)
            case .square:
                EmptyView()
            }
        }
    }

    private func debtBanner(_ balance: BalanceSummary) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 2) {
                Text(balance.isFocusPartial
                     ? "\(formatted(balance.owedKcal)) kcal owed · focus \(formatted(balance.focusToClearKcal))"
                     : "\(formatted(balance.owedKcal)) kcal owed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                // Today's own contribution lives here rather than on the ring
                // caption, which has 64pt and a more important job: saying what
                // the figure is at all.
                Text(debtExplanation(balance))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.Palette.debt, in: .rect(cornerRadius: Theme.Radius.card))
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    private func creditNote(_ balance: BalanceSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.credit)

            Text("**+\(formatted(balance.creditKcal)) credit.** It cushions your next over-day — it doesn't add to today's food.\(balance.isAtCreditCap ? " You're at the \(BalanceSummary.creditCapKcal) cap; extra burn stops counting." : "")")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.Palette.credit.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.credit.opacity(0.25), lineWidth: 1)
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    private func errorNote(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.Palette.over)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    // MARK: - Meals

    private func mealList(_ viewModel: TodayViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.isFirstRunOfDay {
                    firstRunPrompt
                }

                ForEach(viewModel.slotGroups) { group in
                    MealSlotRow(
                        group: group,
                        onAdd: { route = .log(slotKey: group.isOrphaned ? nil : group.key) },
                        onOpenDetail: { route = .detail(group) }
                    )

                    Divider().overlay(Theme.Palette.line)
                }

                addMealRow
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // On the scroll view rather than the enclosing stack: pull-to-refresh
        // needs a scrollable to hang off, and on a VStack it silently does
        // nothing.
        .refreshable { await viewModel.load() }
        .padding(.top, 4)
    }

    /// The escape hatch from the rhythm onboarding picked once.
    ///
    /// Sits at the end of the list rather than in Settings: the moment someone
    /// wants a meal that isn't there is the moment they are looking at the list
    /// and failing to find it.
    private var addMealRow: some View {
        Button {
            route = .addMeal
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.Palette.fillSubtle, in: .circle)

                Text("Add a meal")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.inkSecondary)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds a meal to your schedule, permanently or just for today")
    }

    /// 7a. One quiet line — no confetti, no lecture, and nothing that implies a
    /// streak the user could later break.
    private var firstRunPrompt: some View {
        Text("Log your first meal — the first few days set your baseline.")
            .font(.footnote)
            .foregroundStyle(Theme.Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Palette.fillSubtle, in: .rect(cornerRadius: Theme.Radius.card))
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func detailSheet(for group: MealSlotGroup) -> some View {
        if let viewModel {
            // Re-read from the view model so the list reflects a delete that has
            // already landed, rather than the snapshot the route captured.
            let current = viewModel.slotGroups.first { $0.key == group.key } ?? group

            MealDetailSheet(
                group: current,
                deletingEntryID: viewModel.deletingEntryID,
                canRemoveMeal: viewModel.canRemoveMeal,
                onDelete: { entry in Task { await viewModel.delete(entry) } },
                onAddFood: { queuedRoute = .log(slotKey: current.key) },
                onRemoveMeal: { Task { await viewModel.removeMeal(key: current.key) } }
            )
        }
    }

    // MARK: - Formatting

    /// Grouped thousands, matching the design's "1,965".
    private func formatted(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
