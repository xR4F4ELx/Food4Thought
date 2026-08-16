import SwiftUI

/// Design tokens from docs/design/handoff.md.
///
/// One home for every colour, radius, and type ramp so views never hardcode a
/// hex value. If a screen needs a colour that isn't here, the token is missing
/// — add it here rather than inlining it.
///
/// Light values are exactly as specified in the handoff. **Dark values are
/// provisional**: the handoff only defines a light palette, and these were
/// derived to keep the same hue relationships and contrast ordering. They need
/// a design pass before anyone treats them as final.
enum Theme {}

// MARK: - Colour

extension Theme {
    enum Palette {
        /// App background — a warm off-white, not system grey.
        static let paper = adaptive(light: 0xFBF8F3, dark: 0x14130E)
        /// Cards and sheets sitting on `paper`.
        static let surface = adaptive(light: 0xFFFFFF, dark: 0x1E1C16)

        static let ink = adaptive(light: 0x1C1A15, dark: 0xF5F1E8)
        static let inkSecondary = adaptive(light: 0x6E685C, dark: 0xA9A294)
        static let inkTertiary = adaptive(light: 0xA79F91, dark: 0x7C7568)

        static let line = adaptiveAlpha(light: 0x1C1A15, lightAlpha: 0.09,
                                        dark: 0xFFFFFF, darkAlpha: 0.12)
        static let lineStrong = adaptiveAlpha(light: 0x1C1A15, lightAlpha: 0.14,
                                              dark: 0xFFFFFF, darkAlpha: 0.18)

        /// Grouped row and control backgrounds.
        static let fill = adaptive(light: 0xEFEAE1, dark: 0x262319)
        static let fillSubtle = adaptive(light: 0xF4F0E8, dark: 0x201E17)

        /// Terracotta. Primary actions and the calorie ring.
        static let accent = adaptive(light: 0xE4572E, dark: 0xF06B42)

        static let protein = adaptive(light: 0xC4452B, dark: 0xE0664B)
        static let carbs = adaptive(light: 0xD99A2B, dark: 0xE8B155)
        static let fat = adaptive(light: 0x3E8C79, dark: 0x52A894)

        /// Deliberately the same green as `fat`: credit is a good state, and the
        /// handoff reuses the token. Named separately so balance views read
        /// clearly and either can move independently later.
        static var credit: Color { fat }

        /// Muted slate, not red. Debt is a state to clear, not a failure.
        static let debt = adaptive(light: 0x4A4E57, dark: 0x8A8F99)
        /// Reserved for genuinely over target.
        static let over = adaptive(light: 0xB4231C, dark: 0xE0524A)
    }
}

// MARK: - Typography

extension Theme {
    /// Space Grotesk for numerals, system for everything else.
    ///
    /// Every helper falls back to a rounded system face when the font isn't
    /// bundled, so the app stays legible before the asset lands and if it ever
    /// fails to load. All sizes are `relativeTo:` a text style so Dynamic Type
    /// keeps working — a custom font otherwise freezes at a fixed size.
    enum Typography {
        private static let displayFamily = "SpaceGrotesk"

        /// Big hero figures: the calorie target, the balance.
        static func hero(_ size: CGFloat = 56) -> Font {
            numeral(size: size, weight: .bold, relativeTo: .largeTitle)
        }

        /// Inline figures: macro grams, per-row kcal.
        static func stat(_ size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
            numeral(size: size, weight: .semibold, relativeTo: style)
        }

        private static func numeral(
            size: CGFloat,
            weight: Font.Weight,
            relativeTo style: Font.TextStyle
        ) -> Font {
            guard let name = postScriptName(for: weight), UIFont(name: name, size: size) != nil else {
                // Rounded keeps numerals reading as display type rather than body.
                return .system(size: size, weight: weight, design: .rounded)
            }
            return .custom(name, size: size, relativeTo: style)
        }

        private static func postScriptName(for weight: Font.Weight) -> String? {
            switch weight {
            case .bold: "\(displayFamily)-Bold"
            case .semibold: "\(displayFamily)-SemiBold"
            case .medium: "\(displayFamily)-Medium"
            default: "\(displayFamily)-Regular"
            }
        }
    }
}

// MARK: - Shape and metrics

extension Theme {
    enum Radius {
        static let card: CGFloat = 16
        static let sheet: CGFloat = 24
        static let control: CGFloat = 14
        static let pill: CGFloat = 20
    }

    enum Metrics {
        static let primaryButtonHeight: CGFloat = 52
        static let calorieRingStroke: CGFloat = 15
        static let macroRingStroke: CGFloat = 6.5
        /// Standard screen gutter.
        static let horizontalPadding: CGFloat = 20
    }
}

// MARK: - Helpers

private extension Theme {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }

    static func adaptiveAlpha(
        light: UInt32, lightAlpha: CGFloat,
        dark: UInt32, darkAlpha: CGFloat
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
