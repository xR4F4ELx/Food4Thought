import SwiftUI

/// Trends — handoff 4a. Merges weight history, balance & activity, and
/// adherence; recalibration (6a) surfaces here.
struct TrendsView: View {
    var body: some View {
        ComingSoonScreen(
            title: "Trends",
            note: "Weight, balance, and adherence over time. Needs about two weeks of data before it says anything useful."
        )
    }
}
