import Foundation
import Observation
import Food4ThoughtCore

/// One point on the weight chart.
///
/// `series` is a plain string because that is what Charts wants for a legend
/// and a colour scale, and it is the label the reader sees either way.
struct WeightPoint: Identifiable, Equatable {
    enum Series {
        static let actual = "Your weight"
        static let plan = "On track"
    }

    let id = UUID()
    let date: Date
    let kilograms: Double
    let series: String
}

/// State for the Trends screen. Weight only, so far.
@Observable
@MainActor
final class TrendsViewModel {

    /// Two weeks of weigh-ins. Long enough for a line to mean something, short
    /// enough that a fortnight of daily weighing does not crush the x axis.
    private static let historyLimit = 14

    private(set) var weighIns: [WeighIn] = []
    private(set) var goalSet: GoalSetSummary?
    private(set) var errorMessage: String?

    private let userID: UUID
    private let weights: WeightRepository
    private let profiles: ProfileRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        userID: UUID,
        weights: WeightRepository = SupabaseWeightRepository(),
        profiles: ProfileRepository = SupabaseProfileRepository(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
        self.weights = weights
        self.profiles = profiles
        self.calendar = calendar
        self.now = now
    }

    func load() async {
        do {
            weighIns = try await weights.recentWeighIns(userID: userID, limit: Self.historyLimit)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        // A missing plan costs the comparison line, not the chart, so it is not
        // worth an error banner over the weigh-ins that did load.
        goalSet = try? await profiles.activeGoalSet(userID: userID)
    }

    // MARK: - The chart

    /// Oldest first, which is the order a chart is read in.
    private var chronological: [WeighIn] {
        weighIns.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// One point per day, taking the last reading of each.
    ///
    /// Plotting every row drew a vertical bar for someone who weighed twice in
    /// a morning — two real readings, no elapsed time between them. The trend
    /// wants one value a day, and the later one wins because there is no way to
    /// delete a weigh-in: re-weighing is how a mistyped number gets corrected.
    /// Every row still appears in the list underneath.
    var actualPoints: [WeightPoint] {
        let byDay = Dictionary(grouping: chronological) { calendar.startOfDay(for: $0.recordedAt) }

        return byDay
            .compactMap { day, readings in
                readings.max { $0.recordedAt < $1.recordedAt }
                    .map { WeightPoint(date: day, kilograms: $0.weightKg, series: WeightPoint.Series.actual) }
            }
            .sorted { $0.date < $1.date }
    }

    /// Two points, because a straight line needs no more: where the plan
    /// started, and where it expects to be today.
    var planPoints: [WeightPoint] {
        guard let projection, let last = chronological.last else { return [] }

        // Drawn to today even when the last weigh-in was days ago — that gap is
        // exactly what someone checking the screen wants to see.
        let end = max(last.recordedAt, now())

        return [
            WeightPoint(date: projection.anchorDate, kilograms: projection.anchorKg, series: WeightPoint.Series.plan),
            WeightPoint(
                date: end,
                kilograms: projection.expectedKg(on: end, calendar: calendar),
                series: WeightPoint.Series.plan
            )
        ]
    }

    /// Anchored on the first weigh-in taken under the current plan, falling
    /// back to the oldest one on file.
    ///
    /// Anchoring earlier would draw the plan across days the user was following
    /// different targets, and score them against a line that did not exist yet.
    private var projection: WeightProjection? {
        guard let goalSet, let anchor = anchorWeighIn else { return nil }

        return WeightProjection(
            anchorDate: anchor.recordedAt,
            anchorKg: anchor.weightKg,
            dailyKcalDelta: goalSet.dailyKcalDelta
        )
    }

    private var anchorWeighIn: WeighIn? {
        guard let goalSet else { return chronological.first }

        let underThisPlan = chronological.first { $0.recordedAt >= goalSet.effectiveFrom }
        return underThisPlan ?? chronological.first
    }

    /// The chart is always drawn, even empty.
    ///
    /// Hiding it until the data earned it meant the feature was invisible on
    /// exactly the days someone was deciding whether to bother — and an axis
    /// with one dot on it is a clearer invitation to weigh in tomorrow than an
    /// absence is.
    var hasWeighIns: Bool { !weighIns.isEmpty }

    /// A week ending today, widened to hold whatever is plotted.
    ///
    /// Fixed rather than derived from the data alone: a lone weigh-in would
    /// otherwise sit on an axis with no width, and the scale would lurch on the
    /// second reading.
    var chartXDomain: ClosedRange<Date> {
        let today = calendar.startOfDay(for: now())
        let weekAgo = calendar.date(byAdding: .day, value: -Self.minimumChartDays, to: today) ?? today

        let plotted = (actualPoints + planPoints).map(\.date)
        let start = min(plotted.min() ?? weekAgo, weekAgo)
        let end = max(plotted.max() ?? today, today)

        return start...end
    }

    /// Padded so a flat week is a flat line across the middle rather than a
    /// jagged one filling the frame — Charts will happily zoom into 200 g of
    /// water weight and make it look like a cliff.
    var chartYDomain: ClosedRange<Double> {
        let values = (actualPoints + planPoints).map(\.kilograms)

        guard let lowest = values.min(), let highest = values.max() else {
            return 0...1
        }

        let padding = max((highest - lowest) * 0.25, Self.minimumChartSpreadKg)
        return (lowest - padding)...(highest + padding)
    }

    private static let minimumChartDays = 7
    private static let minimumChartSpreadKg = 0.5

    var latestWeightText: String {
        guard let latest = weighIns.first else { return "—" }
        return WeighInDraft.format(latest.weightKg)
    }

    /// Movement across the window, not since yesterday.
    ///
    /// Day to day is mostly water, and a "+0.4 kg since yesterday" on a screen
    /// called Trends invites exactly the wrong reading of a number that means
    /// nothing on its own.
    /// Measured off the same one-a-day points the chart plots, not the raw
    /// rows. Reading them separately had the header claim 1.0 kg while the line
    /// beside it fell 0.5 — both true of different numbers, and the sort of
    /// disagreement that makes someone stop trusting the screen.
    var changeText: String? {
        let points = actualPoints
        guard let latest = points.last, let earliest = points.first, points.count > 1 else {
            return nil
        }

        let delta = latest.kilograms - earliest.kilograms
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: earliest.date),
            to: calendar.startOfDay(for: latest.date)
        ).day ?? 0

        guard days > 0 else { return nil }

        let sign = delta > 0 ? "+" : delta < 0 ? "−" : "±"
        return "\(sign)\(WeighInDraft.format(abs(delta))) kg over \(days) day\(days == 1 ? "" : "s")"
    }

    // MARK: - Reading the comparison

    var standing: ProgressStanding? {
        guard
            let projection,
            let goalSet,
            let latest = chronological.last,
            latest.recordedAt > projection.anchorDate
        else { return nil }

        return ProgressStanding(
            actualKg: latest.weightKg,
            expectedKg: projection.expectedKg(on: latest.recordedAt, calendar: calendar),
            goalIsLoss: goalSet.goal.direction == .lose
        )
    }

    /// Said in plain words under the chart, because a dashed line explains
    /// nothing on its own.
    var standingText: String? {
        guard let standing, let projection else { return nil }

        let pace = Self.pace(weeklyKgChange: projection.weeklyKgChange)

        return switch standing {
        case .onTrack:
            "On track. Your plan expects \(pace)."
        case .ahead(let kg):
            "\(WeighInDraft.format(kg)) kg ahead of your plan, which expects \(pace)."
        case .behind(let kg):
            "\(WeighInDraft.format(kg)) kg behind your plan, which expects \(pace). Weight is noisy — a fortnight of readings says more than any one of them."
        }
    }

    /// "about 0.5 kg a week", or the honest version when the plan is flat or
    /// so gentle that one decimal rounds it away.
    private static func pace(weeklyKgChange: Double) -> String {
        let magnitude = abs(weeklyKgChange)

        if magnitude == 0 { return "your weight to hold steady" }
        if magnitude < 0.05 { return "under 0.1 kg a week" }
        return "about \(WeighInDraft.format(magnitude)) kg a week"
    }

    /// The plan line needs saying out loud too, for the days there is not
    /// enough history to draw one.
    var planSummary: String? {
        guard let goalSet else { return nil }

        guard goalSet.dailyKcalDelta != 0 else {
            return "Your plan holds your weight steady at \(goalSet.dailyCalorieTarget) kcal a day."
        }

        // Anchor weight is irrelevant to the rate, so zero stands in for it.
        let projection = WeightProjection(
            anchorDate: goalSet.effectiveFrom,
            anchorKg: 0,
            dailyKcalDelta: goalSet.dailyKcalDelta
        )
        let direction = goalSet.dailyKcalDelta < 0 ? "lose" : "gain"
        let pace = Self.pace(weeklyKgChange: projection.weeklyKgChange)

        return "Your plan expects you to \(direction) \(pace) — an estimate, from your calorie target."
    }
}
