import SwiftUI

/// Custom rather than a stock `TabView` bar, for one reason: the centre log
/// button overhangs the top edge, which no `TabView` will do.
struct MainTabBar: View {
    @Binding var selection: AppTab
    let logAction: () -> Void

    /// The FAB overhangs by this much, so the bar needs the same headroom or it
    /// clips against the content above it.
    private let fabOverhang: CGFloat = 16
    private let fabDiameter: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tab(.today)
            tab(.trends)
            logButton
            tab(.activity)
            tab(.settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            Rectangle()
                .fill(Theme.Palette.line)
                .frame(height: 1)
        }
        .background(.bar)
        // Tab labels are already at the small end; letting them scale to
        // accessibility sizes tears the row apart without helping anyone who
        // has the icons.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func tab(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: isSelected ? tab.selectedSymbolName : tab.symbolName)
                    .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.inkTertiary)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var logButton: some View {
        Button(action: logAction) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white)
                .frame(width: fabDiameter, height: fabDiameter)
                .background(Theme.Palette.accent, in: .circle)
                .shadow(color: Theme.Palette.accent.opacity(0.45), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .offset(y: -fabOverhang)
        // Without this the button keeps its pre-offset footprint and leaves a
        // 56pt hole in the middle of the bar.
        .frame(width: fabDiameter, height: fabDiameter - fabOverhang)
        .padding(.horizontal, 8)
        .accessibilityLabel("Log food")
        .accessibilityHint("Adds to the meal happening now")
    }
}

#Preview {
    @Previewable @State var selection = AppTab.today

    return VStack {
        Spacer()
        MainTabBar(selection: $selection, logAction: {})
    }
    .background(Theme.Palette.paper)
}
