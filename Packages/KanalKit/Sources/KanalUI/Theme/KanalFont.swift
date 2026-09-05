import SwiftUI

/// Typography.
///
/// The display face is heavy and condensed — the poster-headline look UHF uses —
/// while everything below title size stays plain system text so it reads well at
/// a glance on a TV across the room.
public enum KanalFont {

    /// Hero headline. Condensed black, tight tracking.
    public static func display(_ size: CGFloat) -> Font {
        // Semantic styles follow Dynamic Type; TV retains its distance-sized type.
        #if os(tvOS)
        .system(size: size, weight: .black).width(.condensed)
        #else
        .system(.largeTitle, design: .default, weight: .black).width(.condensed)
        #endif
    }

    // TV minima apply only to supporting text. Explicit display/section sizes
    // above the minimum retain their hierarchy; spacing is scaled separately.

    /// Section headers: "Continue watching", "Favourite channels".
    public static func section(_ size: CGFloat = 20) -> Font {
        #if os(tvOS)
        .system(size: max(size, 28), weight: .bold)
        #else
        .system(.headline, design: .default, weight: .bold)
        #endif
    }

    /// Buttons and nav items — condensed heavy, uppercase at call sites.
    public static func label(_ size: CGFloat = 15) -> Font {
        #if os(tvOS)
        .system(size: max(size, 26), weight: .heavy).width(.condensed)
        #else
        .system(.headline, design: .default, weight: .heavy).width(.condensed)
        #endif
    }

    public static func body(_ size: CGFloat = 15) -> Font {
        #if os(tvOS)
        .system(size: max(size, 22), weight: .regular)
        #else
        .system(.body, design: .default, weight: .regular)
        #endif
    }

    public static func caption(_ size: CGFloat = 12) -> Font {
        #if os(tvOS)
        .system(size: max(size, 22), weight: .semibold)
        #else
        .system(.caption, design: .default, weight: .semibold)
        #endif
    }
}

public extension View {
    /// Display type with the tracking the headline style depends on.
    func kanalDisplay(_ size: CGFloat) -> some View {
        font(KanalFont.display(size))
            .tracking(-size * 0.02)
            .lineSpacing(-size * 0.08)
    }

    /// Uppercase condensed label, as used on pills and buttons.
    func kanalLabel(_ size: CGFloat = 15) -> some View {
        font(KanalFont.label(size))
            .textCase(.uppercase)
            .tracking(size * 0.03)
    }
}
