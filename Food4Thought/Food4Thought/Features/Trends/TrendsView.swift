import SwiftUI
import Charts
import Food4ThoughtCore

/// Trends — handoff 4a. Merges weight history, balance & activity, and
/// adherence; recalibration (6a) surfaces here.
///
/// Only the weight strand exists so far, and it is here rather than waiting for
/// the rest because the chart cannot be built out of data nobody has recorded.
/// Weighing in from the screen that will plot it also means the days Home's
/// prompt was missed are still reachable.
struct TrendsView: View {

    /// Said in the same words wherever weighing comes up.
    ///
    /// It is the one instruction that makes the chart mean anything: a reading
    /// taken after dinner can sit a kilogram above the same body at breakfast,
    /// which is larger than a fortnight of real progress. Consistency matters
    /// more than the hour, and first thing is the easiest hour to be consistent
    /// about.
    static let timingAdvice = "Weigh in first thing in the morning — after the loo, before eating or drinking. Same time each day is what makes the line readable."

    let userID: UUID

    @State private var viewModel: TrendsViewModel?
    @State private var isWeighingIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weightCard
                    macroCard
                    comingSoon
                }
                .padding(.horizontal, Theme.Metrics.horizontalPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard viewModel == nil else { return }
            let model = TrendsViewModel(userID: userID)
            await model.load()
            viewModel = model
        }
        .sheet(isPresented: $isWeighingIn) {
            WeighInSheet(viewModel: WeighInViewModel(userID: userID)) {
                Task { await viewModel?.load() }
            }
        }
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button("Log") { isWeighingIn = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
            }

            if let viewModel {
                latest(viewModel)

                // Always drawn, filling in as weigh-ins arrive. An empty axis
                // is an invitation; a missing chart is just a missing feature.
                chart(viewModel)
                legend(viewModel)

                if let standing = viewModel.standingText ?? viewModel.planSummary {
                    Text(standing)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.hasWeighIns {
                    history(viewModel)
                } else {
                    Text(Self.timingAdvice)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder
    private func latest(_ viewModel: TrendsViewModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(viewModel.latestWeightText)
                .font(Theme.Typography.hero(34))
                .foregroundStyle(Theme.Palette.ink)
            Text("kg")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkTertiary)

            if let change = viewModel.changeText {
                Spacer()
                Text(change)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    /// Weight against days, with the plan drawn through it.
    ///
    /// The plan line is the point of the chart. A weight line on its own says
    /// what happened; the question people have is whether it is working, and
    /// that only has an answer next to what was expected.
    private func chart(_ viewModel: TrendsViewModel) -> some View {
        Chart {
            ForEach(viewModel.planPoints) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Weight", point.kilograms),
                    series: .value("Series", point.series)
                )
                .foregroundStyle(Theme.Palette.inkTertiary)
                // Dashed so it reads as an expectation rather than a
                // measurement — it is the only line here nobody stood on.
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.linear)
            }

            ForEach(viewModel.actualPoints) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Weight", point.kilograms),
                    series: .value("Series", point.series)
                )
                .foregroundStyle(Theme.Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Weight", point.kilograms)
                )
                .foregroundStyle(Theme.Palette.accent)
                .symbolSize(36)
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.line)
                AxisValueLabel {
                    if let kilograms = value.as(Double.self) {
                        // One decimal, not a rounded integer: a fortnight of
                        // real change can span less than a kilogram, and
                        // rounding labelled three different ticks "57".
                        Text(WeighInDraft.format(kilograms))
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.line)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
            }
        }
        // Held rather than automatic: the axes have to stand still while the
        // data fills in, or the first few weigh-ins each rescale the whole
        // chart and nothing looks like progress.
        .chartXScale(domain: viewModel.chartXDomain)
        .chartYScale(domain: viewModel.chartYDomain)
        .frame(height: 180)
        .overlay {
            if !viewModel.hasWeighIns {
                Text("Your weight will appear here")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.Palette.fillSubtle, in: .capsule)
            }
        }
        .accessibilityLabel("Weight over time, with your plan drawn against it")
    }

    /// The plan key only appears when there is a plan line to explain.
    private func legend(_ viewModel: TrendsViewModel) -> some View {
        HStack(spacing: 16) {
            legendKey(WeightPoint.Series.actual, colour: Theme.Palette.accent, isDashed: false)
            if !viewModel.planPoints.isEmpty {
                legendKey(WeightPoint.Series.plan, colour: Theme.Palette.inkTertiary, isDashed: true)
            }
            Spacer()
        }
    }

    /// The key is drawn from the same parts as the line it stands for: one
    /// stroke for the measured series, two dashes for the projected one.
    private func legendKey(_ label: String, colour: Color, isDashed: Bool) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: isDashed ? 3 : 0) {
                Capsule().fill(colour).frame(width: isDashed ? 7 : 18, height: 2.5)
                if isDashed {
                    Capsule().fill(colour).frame(width: 7, height: 2.5)
                }
            }
            .frame(width: 18, alignment: .leading)

            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    /// The full history under the chart. A chart shows the shape; the list is
    /// where you check a specific morning's number.
    private func history(_ viewModel: TrendsViewModel) -> some View {
        VStack(spacing: 0) {
            ForEach(viewModel.weighIns) { weighIn in
                HStack {
                    Text(weighIn.recordedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Spacer()
                    Text("\(WeighInDraft.format(weighIn.weightKg)) kg")
                        .font(Theme.Typography.stat(15))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .padding(.vertical, 9)

                if weighIn.id != viewModel.weighIns.last?.id {
                    Divider().overlay(Theme.Palette.line)
                }
            }
        }
    }

    /// Protein, carbs and fat by day — stacked, because the question is how a
    /// day divides, and three separate lines make the reader do that division
    /// in their head.
    @ViewBuilder
    private var macroCard: some View {
        if let viewModel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Macros")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                }

                Picker("Reading", selection: readingBinding(viewModel)) {
                    ForEach(MacroReading.allCases) { reading in
                        Text(reading.rawValue).tag(reading)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.hasMacroHistory {
                    switch viewModel.macroReading {
                    case .split:
                        Text(viewModel.selectedScopeLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Palette.inkSecondary)

                        macroPie(viewModel)
                        weekStrip(viewModel)
                        sliceRows(viewModel)
                        Text("Shares are of calories, not of weight — a gram of fat carries more than twice the energy of a gram of carbs.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                    case .trend:
                        macroChart(viewModel)
                        macroLegend

                        if let average = viewModel.averageSplitText {
                            Text(average)
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Nothing logged in the last two weeks. Log a few days and the split shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }

    /// Seven days as seven rings, and the day picker at the same time.
    ///
    /// The average above it is the figure worth acting on; this is what the
    /// average hides. A steady 35% fat reads the same whether every day was 35%
    /// or they alternated 20 and 50, and those are different problems. The
    /// blanks matter too: an average over two logged days out of seven looks
    /// exactly as confident as one over seven.
    private func weekStrip(_ viewModel: TrendsViewModel) -> some View {
        HStack(spacing: 0) {
            ForEach(viewModel.weekDays.compactMap { $0 }) { day in
                let isSelected = viewModel.isSelected(day.day)

                Button {
                    viewModel.toggleSelection(day.day)
                } label: {
                    VStack(spacing: 5) {
                        MacroSplitRing(split: day.split)

                        Text(viewModel.weekdayInitial(for: day.day))
                            .font(.caption2.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? Theme.Palette.ink : Theme.Palette.inkTertiary)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        isSelected ? Theme.Palette.fill : .clear,
                        in: .rect(cornerRadius: Theme.Radius.control)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // Days with nothing in them have nothing to show, so they are
                // shown — as a gap — but not offered as a choice.
                .disabled(day.split == nil)
                .accessibilityLabel(accessibilityLabel(for: day, viewModel))
            }
        }
    }

    private func accessibilityLabel(for day: DailyMacros, _ viewModel: TrendsViewModel) -> String {
        let date = day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))

        guard let split = day.split else { return "\(date), nothing logged" }

        let percentages = split.roundedPercentages
        return "\(date), \(percentages.protein) percent protein, \(percentages.carbs) percent carbs, \(percentages.fat) percent fat"
    }

    /// A donut rather than a full pie: the hole carries the total the slices
    /// were cut from, which is the number that makes a percentage checkable.
    private func macroPie(_ viewModel: TrendsViewModel) -> some View {
        Chart(viewModel.macroSlices) { slice in
            SectorMark(
                angle: .value("Share", slice.percentage),
                innerRadius: .ratio(0.58),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value("Macro", slice.macro.rawValue))
            .cornerRadius(4)
            .annotation(position: .overlay) {
                // Only where the slice can hold it: a label floating off a 3%
                // sliver lands on its neighbour and misreads as theirs.
                if slice.percentage >= 10 {
                    Text("\(slice.percentage)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .chartForegroundStyleScale([
            MacroBar.Macro.protein.rawValue: Theme.Palette.protein,
            MacroBar.Macro.carbs.rawValue: Theme.Palette.carbs,
            MacroBar.Macro.fat.rawValue: Theme.Palette.fat
        ])
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 1) {
                Text("\(viewModel.selectedMacroKcal)")
                    .font(Theme.Typography.stat(20))
                    .foregroundStyle(Theme.Palette.ink)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
        }
        .frame(height: 200)
        .accessibilityLabel("\(viewModel.selectedScopeLabel): " + viewModel.macroSlices
            .map { "\($0.macro.rawValue) \($0.percentage) percent" }
            .joined(separator: ", "))
    }

    /// The legend doubles as the readout: colour, name, percentage, and the
    /// grams the percentage was computed from.
    private func sliceRows(_ viewModel: TrendsViewModel) -> some View {
        VStack(spacing: 0) {
            ForEach(viewModel.macroSlices) { slice in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colour(for: slice.macro))
                        .frame(width: 10, height: 10)

                    Text(slice.macro.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)

                    Spacer()

                    Text("\(Int(slice.grams.rounded())) g")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)

                    Text("\(slice.percentage)%")
                        .font(Theme.Typography.stat(15))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 7)

                if slice.id != viewModel.macroSlices.last?.id {
                    Divider().overlay(Theme.Palette.line)
                }
            }
        }
    }

    private func colour(for macro: MacroBar.Macro) -> Color {
        switch macro {
        case .protein: Theme.Palette.protein
        case .carbs: Theme.Palette.carbs
        case .fat: Theme.Palette.fat
        }
    }

    private func readingBinding(_ viewModel: TrendsViewModel) -> Binding<MacroReading> {
        Binding(
            get: { viewModel.macroReading },
            set: { viewModel.macroReading = $0 }
        )
    }

    private func macroChart(_ viewModel: TrendsViewModel) -> some View {
        Chart(viewModel.macroBars) { bar in
            BarMark(
                x: .value("Day", bar.day, unit: .day),
                y: .value(viewModel.macroReading.rawValue, bar.value)
            )
            .foregroundStyle(by: .value("Macro", bar.macro.rawValue))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            MacroBar.Macro.protein.rawValue: Theme.Palette.protein,
            MacroBar.Macro.carbs.rawValue: Theme.Palette.carbs,
            MacroBar.Macro.fat.rawValue: Theme.Palette.fat
        ])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
            }
        }
        .chartXScale(domain: viewModel.macroXDomain)
        .chartYScale(domain: viewModel.macroYDomain)
        .frame(height: 180)
        .accessibilityLabel("Each day's macros in grams")
    }

    private var macroLegend: some View {
        HStack(spacing: 16) {
            macroKey(MacroBar.Macro.protein.rawValue, colour: Theme.Palette.protein)
            macroKey(MacroBar.Macro.carbs.rawValue, colour: Theme.Palette.carbs)
            macroKey(MacroBar.Macro.fat.rawValue, colour: Theme.Palette.fat)
            Spacer()
        }
    }

    private func macroKey(_ label: String, colour: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(colour)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Balance and adherence")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("How the balance and your logging streak move over time. Needs about two weeks of data before it says anything useful.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.fillSubtle, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
