import KanalCore
import SwiftUI

/// A profile's face: a symbol on a coloured tile.
///
/// Symbols rather than photographs, deliberately. A photo needs a camera
/// permission, a picker, storage and a sync story, and none of that helps the
/// thing an avatar is for — being recognisable from the sofa, three metres from
/// the television, by someone who cannot read yet.
public struct ProfileAvatar: View {
    public let profile: Profile
    public var size: CGFloat
    /// Drawn on the profile currently in use.
    public var isSelected: Bool

    public init(profile: Profile, size: CGFloat = 96, isSelected: Bool = false) {
        self.profile = profile
        self.size = size
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: profile.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: size * 0.02, y: size * 0.01)

            if showsBadge {
                // The age limit is on the avatar, not tucked into a settings
                // screen. A parent handing over a remote should be able to see
                // which profile is loaded without opening anything.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(profile.maturity.badge)
                            .font(.system(size: size * 0.17, weight: .black))
                            .foregroundStyle(KanalColor.primaryText)
                            .padding(.horizontal, size * 0.09)
                            .padding(.vertical, size * 0.03)
                            .background(
                                Capsule().fill(KanalColor.surface)
                            )
                            .padding(size * 0.06)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(
                    isSelected ? KanalColor.accentSolid : .clear,
                    lineWidth: max(size * 0.035, 2)
                )
        }
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var tint: Color { Color(hex: profile.avatarColor) }

    /// The age badge is dropped below the size where it would be a smudge
    /// rather than a number — a 6pt "12" is decoration, not information.
    private var showsBadge: Bool { profile.isRestricted && size >= 56 }

    private var accessibilityDescription: String {
        guard profile.isRestricted else { return profile.displayName }
        return "\(profile.displayName), \(profile.maturity.displayName)"
    }
}
