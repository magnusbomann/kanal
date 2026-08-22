import SwiftUI

/// Kanal's palette.
///
/// Two rules hold the look together: surfaces are neutral and nearly flat, and
/// the coral accent is the only saturated colour on screen. Anything competing
/// with the accent gets desaturated instead of recoloured.
public enum KanalColor {

    // MARK: Accent

    public static let accentStart = Color(hex: 0xFFA183)
    public static let accentEnd = Color(hex: 0xFF6A3C)

    /// The single accent gradient used on primary actions and live badges.
    public static let accent = LinearGradient(
        colors: [accentStart, accentEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let accentSolid = Color(hex: 0xFF7A4D)

    // MARK: Surfaces

    public static let background = Color(
        light: Color(hex: 0xEFEFEF),
        dark: Color(hex: 0x0B0B0C)
    )

    /// Cards, sheets, list rows.
    public static let surface = Color(
        light: .white,
        dark: Color(hex: 0x17171A)
    )

    /// Raised surface on top of `surface` — nested cards, selected rows.
    public static let surfaceElevated = Color(
        light: Color(hex: 0xF7F7F8),
        dark: Color(hex: 0x212126)
    )

    /// The near-black used by the floating navigation bar.
    public static let inkSurface = Color(
        light: Color(hex: 0x121214),
        dark: Color(hex: 0x1C1C1F)
    )

    // MARK: Content

    public static let primaryText = Color(
        light: Color(hex: 0x0A0A0B),
        dark: Color(hex: 0xF5F5F7)
    )

    public static let secondaryText = Color(
        light: Color(hex: 0x76767C),
        dark: Color(hex: 0x9A9AA2)
    )

    public static let tertiaryText = Color(
        light: Color(hex: 0xAEAEB4),
        dark: Color(hex: 0x6C6C74)
    )

    public static let separator = Color(
        light: Color(hex: 0xDEDEE1),
        dark: Color(hex: 0x2C2C31)
    )

    // MARK: Status

    public static let live = Color(hex: 0xFF3B30)
    public static let success = Color(hex: 0x30C158)
    public static let warning = Color(hex: 0xFFB020)
}

extension Color {
    /// Resolves per colour scheme so the palette works without an asset catalog.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #endif
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
