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
                if viewModel.weighIns.isEmpty {
                    Text("No weigh-ins yet. \(Self.timingAdvice)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                } else {
                    latest(viewModel)

                    if viewModel.hasChart {
                        chart(viewModel)
                        legend
                    }

                    if let standing = viewModel.standingText ?? viewModel.planSummary {
                        Text(standing)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    history(viewModel)
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
        // Padded rather than zeroed: a weight axis starting at zero flattens
        // every real change into a straight line near the top.
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 180)
        .accessibilityLabel("Weight over time, with your plan drawn against it")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendKey(WeightPoint.Series.actual, colour: Theme.Palette.accent, isDashed: false)
            legendKey(WeightPoint.Series.plan, colour: Theme.Palette.inkTertiary, isDashed: true)
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
