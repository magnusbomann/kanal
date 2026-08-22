import SwiftUI

/// Spacing, corner radii and artwork ratios.
///
/// Values scale per platform: tvOS is viewed from three metres away, so the
/// same semantic step is physically larger there.
public enum KanalMetrics {

    #if os(tvOS)
    public static let scale: CGFloat = 1.6
    #else
    public static let scale: CGFloat = 1.0
    #endif

    public static var xs: CGFloat { 4 * scale }
    public static var sm: CGFloat { 8 * scale }
    public static var md: CGFloat { 16 * scale }
    public static var lg: CGFloat { 24 * scale }
    public static var xl: CGFloat { 32 * scale }
    public static var xxl: CGFloat { 48 * scale }

    /// Radius for cards and artwork tiles.
    public static var cardRadius: CGFloat { 16 * scale }
    /// Radius for sheets and large containers.
    public static var sheetRadius: CGFloat { 28 * scale }

    /// Poster artwork, matching the 2:3 ratio TMDB returns.
    public static let posterAspect: CGFloat = 2.0 / 3.0
    /// Backdrops and live-channel thumbnails.
    public static let backdropAspect: CGFloat = 16.0 / 9.0
    /// Channel logo tiles.
    public static let logoAspect: CGFloat = 1.0

    /// Minimum hit target. 44pt on touch, larger on TV where focus needs room.
    #if os(tvOS)
    public static let minTarget: CGFloat = 64
    #else
    public static let minTarget: CGFloat = 44
    #endif
}
