import AppKit
import SwiftUI

/// Halo's palette. Two moods designed together:
/// **Daybreak** — warm ivory, sky blue and soft gold light.
/// **Nightfall** — deep midnight blue lit by starlight and gold.
/// Every token is a dynamic NSColor so AppKit and SwiftUI follow the
/// system appearance without any manual refresh.
enum Palette {
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        }
    }

    // Surfaces
    static let editorBackground = dynamic(light: 0xFBFAF7, dark: 0x0F131A)
    static let chromeBackground = dynamic(light: 0xF5F3EE, dark: 0x0B0E14)
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x1A2029)
    static let hairline = dynamic(light: 0x1B2230, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)

    // Text
    static let text = dynamic(light: 0x2B2F36, dark: 0xDCE1E8)
    static let secondaryText = dynamic(light: 0x5F656F, dark: 0x9AA2AF)
    static let tertiaryText = dynamic(light: 0x8C919A, dark: 0x6B7482)

    // Accents
    static let gold = dynamic(light: 0xB8862B, dark: 0xE8C77A)
    static let sky = dynamic(light: 0x2F6FCF, dark: 0x8DB8F5)
    static let modified = dynamic(light: 0xC27A12, dark: 0xF2B872)
    static let added = dynamic(light: 0x3E8A4F, dark: 0x8FD19E)
    /// Fill for prominent buttons — white text stays ≥ 4.5:1 in both moods.
    static let action = dynamic(light: 0x2F6FCF, dark: 0x2F6AC4)

    // Editor
    static let currentLine = dynamic(light: 0x2F6FCF, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.035)
    static let selection = dynamic(light: 0xCFE2F8, dark: 0x27384F)
    static let gutterText = dynamic(light: 0xA3A8B0, dark: 0x465061)
    static let gutterCurrent = dynamic(light: 0xB8862B, dark: 0xE8C77A)
    static let caret = dynamic(light: 0x2F6FCF, dark: 0x7DADF2)
    static let ghost = dynamic(light: 0x9AA0A8, dark: 0x5C6573)
    static let error = dynamic(light: 0xC8364A, dark: 0xF07A8A)
    static let warning = dynamic(light: 0xB86E0C, dark: 0xF2B872)
    static let breakpoint = dynamic(light: 0xD93B4E, dark: 0xE5566A)
    static let executionLine = dynamic(light: 0xE8B931, dark: 0xE8C77A, lightAlpha: 0.16, darkAlpha: 0.12)
    static let executionMarker = dynamic(light: 0xD39E12, dark: 0xE8C77A)
    static let bracketMatch = dynamic(light: 0x2F6FCF, dark: 0x8DB8F5, lightAlpha: 0.16, darkAlpha: 0.2)
}

/// Syntax colors, tuned per appearance for ≥ 4.5:1 on the editor
/// background (comments are intentionally quieter, ≈ 3.5:1).
enum SyntaxPalette {
    static let keyword = Palette.dynamic(light: 0xB03E68, dark: 0xF28FB0)
    static let type = Palette.dynamic(light: 0x24707F, dark: 0x7FD4D9)
    static let function = Palette.dynamic(light: 0x2F62B0, dark: 0x8DB8F5)
    static let string = Palette.dynamic(light: 0x4A7F2C, dark: 0xA9D98B)
    static let number = Palette.dynamic(light: 0xA65F14, dark: 0xF2B872)
    static let comment = Palette.dynamic(light: 0x80868F, dark: 0x5F6979)
    static let attribute = Palette.dynamic(light: 0x7253A8, dark: 0xC3A6F2)
    static let property = Palette.dynamic(light: 0x36506E, dark: 0xB7C6DA)
    static let punctuation = Palette.dynamic(light: 0x6B717A, dark: 0x8B93A0)
    static let heading = Palette.dynamic(light: 0x2F62B0, dark: 0x8DB8F5)
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]).map { [.darkAqua, .vibrantDark].contains($0) } ?? false
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    static let haloEditor = Color(nsColor: Palette.editorBackground)
    static let haloChrome = Color(nsColor: Palette.chromeBackground)
    static let haloRaised = Color(nsColor: Palette.raised)
    static let haloHairline = Color(nsColor: Palette.hairline)
    static let haloText = Color(nsColor: Palette.text)
    static let haloSecondary = Color(nsColor: Palette.secondaryText)
    static let haloTertiary = Color(nsColor: Palette.tertiaryText)
    static let haloGold = Color(nsColor: Palette.gold)
    static let haloSky = Color(nsColor: Palette.sky)
    static let haloModified = Color(nsColor: Palette.modified)
    static let haloAdded = Color(nsColor: Palette.added)
    static let haloAction = Color(nsColor: Palette.action)
}

/// Shared motion tokens — one rhythm for the whole app. Springs are
/// interruptible; with Reduce Motion on, changes become quick fades.
enum Motion {
    private static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var snappy: Animation { reduced ? .easeOut(duration: 0.12) : .snappy(duration: 0.24, extraBounce: 0.02) }
    static var gentle: Animation { reduced ? .easeOut(duration: 0.15) : .smooth(duration: 0.34) }
    static var exit: Animation { .easeOut(duration: 0.12) }
}

enum EditorFont {
    static func regular(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    static func medium(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .medium) }
    static func semibold(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .semibold) }
    static func italic(_ size: CGFloat) -> NSFont {
        let base = regular(size)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }
}
