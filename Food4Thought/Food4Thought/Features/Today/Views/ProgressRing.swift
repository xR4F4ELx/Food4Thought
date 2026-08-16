import SwiftUI

/// The one ring component every figure on Home is drawn with.
///
/// Deliberately dumb: it takes a fraction and two colours and knows nothing
/// about calories, macros or the balance. The three-way colour switch at zero
/// that 1d/1e/10a describe is a decision about the *value*, so it belongs to
/// whoever owns the value, not here.
struct ProgressRing<Center: View>: View {
    let fraction: Double
    let tint: Color
    var track: Color = Theme.Palette.fill
    let lineWidth: CGFloat
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)

            // A zero-length round-capped stroke still paints a dot, which reads
            // as progress on a day nothing has been logged to. 7a's rings are
            // meant to be empty, so an empty ring draws nothing.
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: min(1, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            center()
        }
        // The ring is decoration for a figure the centre already states; a
        // second reading of the same number is noise for a screen reader.
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

/// The 2×2 grid ring: a number inside, a caption under.
struct MacroRing: View {
    let value: Int
    let target: Int
    let label: String
    let fraction: Double
    let tint: Color
    let isOver: Bool

    var body: some View {
        VStack(spacing: 2) {
            ProgressRing(
                fraction: fraction,
                tint: isOver ? Theme.Palette.over : tint,
                track: isOver ? Theme.Palette.over.opacity(0.16) : Theme.Palette.fill,
                lineWidth: Theme.Metrics.macroRingStroke
            ) {
                Text("\(value)")
                    .font(Theme.Typography.stat(15, relativeTo: .footnote))
                    .foregroundStyle(isOver ? Theme.Palette.over : Theme.Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .frame(width: 64, height: 64)

            Text("\(label) · \(target)")
                .font(.caption2)
                .foregroundStyle(isOver ? Theme.Palette.over : Theme.Palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) of \(target) grams\(isOver ? ", over target" : "")")
    }
}
