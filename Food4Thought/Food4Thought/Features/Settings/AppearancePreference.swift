import SwiftUI

/// Light, dark, or whatever the phone is doing.
///
/// Stored on the device rather than the profile: it is a property of the screen
/// you are looking at, not of the person. Someone with an iPad on a bright desk
/// and a phone in bed wants different answers on each, and syncing it would
/// make one of them wrong.
///
/// `system` is the default because iOS already schedules dark mode for sunset,
/// and an app that ignores that is the one thing on the phone still glowing
/// white at midnight. The explicit choices exist because the system setting is
/// a blunt instrument — plenty of people run their phone light and want one
/// app dark.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearancePreference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` hands the decision back to iOS, which is what `system` means.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
