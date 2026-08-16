import SwiftUI

/// The signed-in shell: four tabs either side of the centre log button.
///
/// The tab bar is drawn once here rather than per screen, so a screen only ever
/// has to fill the space above it.
struct MainTabView: View {
    let user: AuthenticatedUser

    @State private var selection: AppTab = .today
    @State private var isLoggingFood = false

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()

            Group {
                switch selection {
                case .today: TodayView()
                case .trends: TrendsView()
                case .foods: FoodsView()
                case .settings: SettingsView(user: user)
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
