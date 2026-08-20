import SwiftUI

/// The signed-in shell: four tabs either side of the centre log button.
///
/// The tab bar is drawn once here rather than per screen, so a screen only ever
/// has to fill the space above it.
struct MainTabView: View {
    let user: AuthenticatedUser

    @State private var selection: AppTab = .today
    @State private var isLoggingFood = false

    /// Bumped when the centre + button logs something, to rebuild Today against
    /// the entry that was just written. Home holds its own snapshot, and the
    /// FAB writes to it from outside — without this the rings sit on the figures
    /// they had before the meal was logged.
    @State private var todayReloadToken = UUID()

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()

            Group {
                switch selection {
                case .today:
                    // The balance affordance selects the Activity tab rather
                    // than pushing a copy of it: with Activity promoted to a
                    // tab, a push from Home would put the same screen in two
                    // places at once.
                    TodayView(userID: user.id) { selection = .activity }
                        .id(todayReloadToken)
                case .trends:
                    TrendsView(userID: user.id)
                case .activity:
                    // Logging exercise moves the balance Home shows, so Home is
                    // rebuilt the next time it is selected.
                    ActivityView(userID: user.id) { todayReloadToken = UUID() }
                case .settings:
                    SettingsView(user: user)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBar(selection: $selection) {
                isLoggingFood = true
            }
        }
        .sheet(isPresented: $isLoggingFood) {
            LogFoodSheet(userID: user.id)
                // Deliberately not switching to Today as well: the FAB is
                // reachable from every tab, and yanking someone off Activity
                // because they cancelled a sheet is a worse bug than a
                // redundant fetch.
                .onDisappear { todayReloadToken = UUID() }
        }
    }
}

/// Standing in for a screen that has a design but no implementation yet.
///
/// Deliberately says so, rather than showing plausible empty rings — a mocked
/// dashboard is indistinguishable from a broken one.
struct ComingSoonScreen: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.Palette.ink)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
    }
}
