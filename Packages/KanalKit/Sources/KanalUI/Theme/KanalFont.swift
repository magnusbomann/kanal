import SwiftUI

/// Typography.
///
/// The display face is heavy and condensed — the poster-headline look UHF uses —
/// while everything below title size stays plain system text so it reads well at
/// a glance on a TV across the room.
public enum KanalFont {

    /// Hero headline. Condensed black, tight tracking.
    public static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Section headers: "Continue watching", "Favourite channels".
    public static func section(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Buttons and nav items — condensed heavy, uppercase at call sites.
    public static func label(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .heavy).width(.condensed)
    }

    public static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }

    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold)
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
