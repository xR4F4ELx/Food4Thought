import SwiftUI
import Food4ThoughtCore

/// One day's macro split as a ring.
///
/// Named apart from Today's `MacroRing`, which draws one macro against its
/// target. This one divides a single ring between all three.
///
/// Drawn with arcs rather than a `Chart`: at this size the ring carries a
/// proportion and nothing else — no labels, no axes — and seven chart views in
/// a row is a lot of machinery for three strokes.
struct MacroSplitRing: View {
    let split: MacroSplit?

    var diameter: CGFloat = 34
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            if let split {
                arc(from: 0, to: split.protein, colour: Theme.Palette.protein)
                arc(from: split.protein, to: split.protein + split.carbs, colour: Theme.Palette.carbs)
                arc(from: split.protein + split.carbs, to: 1, colour: Theme.Palette.fat)
            } else {
                // Dashed and hollow: a day with no record is not a day of
                // eating nothing, and a solid empty ring would say the latter.
                Circle()
                    .stroke(
                        Theme.Palette.line,
                        style: StrokeStyle(lineWidth: lineWidth, dash: [2, 3])
                    )
            }
        }
        // Twelve o'clock start, so every ring is read from the same place.
        .rotationEffect(.degrees(-90))
        .frame(width: diameter, height: diameter)
    }

    private func arc(from start: Double, to end: Double, colour: Color) -> some View {
        Circle()
            .trim(from: start, to: max(end, start))
            .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
}
