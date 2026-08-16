import Testing
import UIKit
@testable import Food4Thought

/// Theme.Typography falls back to a system face when a lookup fails, which is
/// the right runtime behaviour and a terrible failure mode to discover by eye:
/// a dropped UIAppFonts entry or a renamed file would just quietly un-brand
/// every number in the app. These assert the bundle actually registered.
@Suite("Space Grotesk registration")
struct ThemeTypographyTests {

    @Test("every bundled PostScript name resolves", arguments: [
        "SpaceGrotesk-Regular",
        "SpaceGrotesk-Medium",
        "SpaceGrotesk-Bold"
    ])
    func postScriptNameResolves(_ name: String) {
        #expect(UIFont(name: name, size: 17) != nil)
    }

    @Test("the licence ships alongside the fonts, as the OFL requires")
    func licenceIsBundled() {
        #expect(Bundle.main.url(forResource: "OFL", withExtension: "txt") != nil)
    }
}
