import SwiftUI

/// Liquid Glass surfaces, expressed as Kanal's own vocabulary so call sites
/// never repeat the shape/tint/interactivity combination by hand.
public extension View {

    /// A floating panel: nav bars, overlays, anything that sits above content.
    func kanalGlassPanel(
        cornerRadius: CGFloat? = nil,
        tinted: Bool = false,
        interactive: Bool = false
    ) -> some View {
        let radius = cornerRadius ?? KanalMetrics.sheetRadius
        var glass = Glass.regular
        if tinted { glass = glass.tint(KanalColor.accentSolid.opacity(0.5)) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// A capsule of glass — pills, chips, small controls.
    func kanalGlassPill(tinted: Bool = false, interactive: Bool = true) -> some View {
        var glass = Glass.regular
        if tinted { glass = glass.tint(KanalColor.accentSolid.opacity(0.55)) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: .capsule)
    }

    /// Glass over video, where the content below must stay readable.
    func kanalGlassOverVideo(cornerRadius: CGFloat? = nil) -> some View {
        glassEffect(
            .clear.interactive(),
            in: .rect(cornerRadius: cornerRadius ?? KanalMetrics.cardRadius, style: .continuous)
        )
    }
}

/// The primary action: coral gradient with a glass highlight on top.
///
/// The gradient is the brand's single saturated element, so it is reserved for
/// the one action a screen most wants you to take.
public struct KanalPrimaryButtonStyle: ButtonStyle {
    public var fullWidth: Bool
    public var size: CGFloat

    public init(fullWidth: Bool = false, size: CGFloat = 16) {
        self.fullWidth = fullWidth
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, fullWidth: fullWidth, size: size)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        let fullWidth: Bool
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .kanalLabel(size)
                .foregroundStyle(isEnabled ? .white : KanalColor.tertiaryText)
                .padding(.vertical, KanalMetrics.md * 0.9)
                .padding(.horizontal, KanalMetrics.xl)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: KanalMetrics.minTarget)
                .background {
                    if isEnabled {
                        Capsule().fill(KanalColor.accent)
                    } else {
                        // Flat and neutral: a dimmed gradient on a dark screen
                        // reads as broken rather than as "not yet".
                        Capsule().fill(KanalColor.surfaceElevated)
                    }
                }
                .overlay {
                    Capsule().strokeBorder(
                        .white.opacity(isEnabled ? 0.28 : 0.06),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: KanalColor.accentEnd.opacity(shadowOpacity),
                    radius: configuration.isPressed ? 6 : 16,
                    y: configuration.isPressed ? 2 : 8
                )
                .scaleEffect(scale)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
        }

        private var shadowOpacity: Double {
            guard isEnabled else { return 0 }
            return configuration.isPressed ? 0.15 : 0.35
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.97 }
            #if os(tvOS)
            return isFocused ? 1.05 : 1
            #else
            return 1
            #endif
        }
    }
}

/// The quiet action beside a primary one — glass, no fill.
public struct KanalSecondaryButtonStyle: ButtonStyle {
    public var fullWidth: Bool
    public var size: CGFloat

    public init(fullWidth: Bool = false, size: CGFloat = 16) {
        self.fullWidth = fullWidth
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kanalLabel(size)
            .foregroundStyle(KanalColor.primaryText)
            .padding(.vertical, KanalMetrics.md * 0.9)
            .padding(.horizontal, KanalMetrics.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: KanalMetrics.minTarget)
            .kanalGlassPill(interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == KanalPrimaryButtonStyle {
    static var kanalPrimary: KanalPrimaryButtonStyle { .init() }
    static func kanalPrimary(fullWidth: Bool) -> KanalPrimaryButtonStyle {
        .init(fullWidth: fullWidth)
    }
}

public extension ButtonStyle where Self == KanalSecondaryButtonStyle {
    static var kanalSecondary: KanalSecondaryButtonStyle { .init() }
    static func kanalSecondary(fullWidth: Bool) -> KanalSecondaryButtonStyle {
        .init(fullWidth: fullWidth)
    }
}

/// Filter chips. Selected chips carry the accent; on tvOS the focused chip
/// also lifts, because `.plain` buttons give no focus feedback at all.
public struct KanalChipButtonStyle: ButtonStyle {
    public var isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }

    private struct ChipBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .kanalLabel(12)
                .foregroundStyle(foreground)
                .padding(.horizontal, KanalMetrics.md)
                .padding(.vertical, KanalMetrics.sm)
                .frame(minHeight: KanalMetrics.minTarget * 0.75)
                .background {
                    if isSelected {
                        Capsule().fill(KanalColor.accent)
                    } else if isFocused {
                        Capsule().fill(KanalColor.primaryText)
                    } else {
                        Capsule().fill(KanalColor.surface)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? 1.06 : 1))
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isFocused)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
        }

        private var foreground: Color {
            if isSelected { return .white }
            if isFocused { return KanalColor.background }
            return KanalColor.secondaryText
        }
    }
}

/// List chrome that tvOS does not implement.
///
/// tvOS draws its own list background and separators and offers no way to
/// override them, so these no-op there rather than forcing every call site to
/// carry a platform check.
public extension View {
    @ViewBuilder
    func kanalPlainListBackground() -> some View {
        #if os(tvOS)
        self
        #else
        scrollContentBackground(.hidden)
        #endif
    }

    @ViewBuilder
    func kanalHiddenRowSeparator() -> some View {
        #if os(tvOS)
        self
        #else
        listRowSeparator(.hidden)
        #endif
    }

    @ViewBuilder
    func kanalListRowBackground(_ color: Color) -> some View {
        #if os(tvOS)
        self
        #else
        listRowBackground(color)
        #endif
    }
}
