import KanalCore
import SwiftUI

/// Who that was.
///
/// Reached by tapping a face in the cast row. It answers one question — "where
/// do I know them from?" — so it is a photo, a paragraph, and the work they
/// are best known for, and nothing else.
///
/// Their films come from TMDB, which knows every one ever made; the viewer's
/// provider carries a fraction of it. Each poster is therefore resolved against
/// the library before it is drawn: the ones that can be watched come first and
/// open, and the rest say plainly that they are not on offer.
public struct PersonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public let member: CastMember
    /// Called with a title the library carries. The presenting screen decides
    /// what to do with it, because a sheet cannot replace the sheet it is on.
    public let onSelect: (MediaItem) -> Void

    @State private var profile: PersonProfile?
    @State private var isLoading = true
    /// Library entries for the credits, keyed by TMDB id. Empty until resolved.
    @State private var available: [Int: MediaItem] = [:]

    public init(member: CastMember, onSelect: @escaping (MediaItem) -> Void = { _ in }) {
        self.member = member
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: KanalMetrics.lg) {
                Artwork(
                    url: profile?.profileURL ?? member.profileURL,
                    title: member.name,
                    symbol: "person.fill"
                )
                .frame(width: portrait, height: portrait)
                .clipShape(.circle)

                VStack(spacing: KanalMetrics.sm) {
                    Text(profile?.name ?? member.name)
                        .kanalDisplay(KanalMetrics.scale * 26)
                        .foregroundStyle(KanalColor.primaryText)
                        .multilineTextAlignment(.center)

                    if let role = member.role {
                        Text(role)
                            .font(KanalFont.body(14))
                            .foregroundStyle(KanalColor.secondaryText)
                    }
                }

                if let biography = profile?.biography, !biography.isEmpty {
                    Text(biography)
                        .font(KanalFont.body(14))
                        .foregroundStyle(KanalColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isLoading {
                    ProgressView().tint(KanalColor.tertiaryText)
                }

                if let known = profile?.knownFor, !known.isEmpty {
                    knownFor(ordered(known))
                }
            }
            .padding(KanalMetrics.lg)
        }
        .background(KanalColor.background)
        .scrollIndicators(.hidden)
        .task(id: member.id) {
            available = [:]
            profile = await model.metadata.person(id: member.id)
            isLoading = false
            guard let roles = profile?.knownFor else { return }
            available = await model.availableCredits(among: roles)
        }
        #if !os(tvOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(KanalColor.background)
        #endif
    }

    private func knownFor(_ roles: [KnownRole]) -> some View {
        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            Text(UIStrings.personKnownFor)
                .kanalLabel(12)
                .foregroundStyle(KanalColor.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: KanalMetrics.md) {
                    ForEach(roles) { role in
                        if let item = available[role.id] {
                            Button {
                                open(item)
                            } label: {
                                poster(role, isAvailable: true)
                            }
                            .buttonStyle(KanalCardButtonStyle())
                        } else {
                            poster(role, isAvailable: false)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func poster(_ role: KnownRole, isAvailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: KanalMetrics.xs) {
            Artwork(
                url: role.posterURL, title: role.title,
                symbol: role.isSeries ? "rectangle.stack" : "film"
            )
            .aspectRatio(KanalMetrics.posterAspect, contentMode: .fill)
            .frame(width: posterWidth)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            // Nothing here pretends to be tappable: what the provider does not
            // carry is dimmed and says so.
            .opacity(isAvailable ? 1 : 0.35)

            Text(role.title)
                .font(KanalFont.body(12))
                .foregroundStyle(isAvailable ? KanalColor.primaryText : KanalColor.tertiaryText)
                .lineLimit(2)
                .frame(width: posterWidth, alignment: .leading)

            if !isAvailable {
                Text(UIStrings.personNotInLibrary)
                    .font(KanalFont.body(10))
                    .foregroundStyle(KanalColor.tertiaryText)
                    .lineLimit(2)
                    .frame(width: posterWidth, alignment: .leading)
            }
        }
    }

    /// What can be watched, first. The point of the row is to lead somewhere,
    /// and a viewer should not have to scroll past six films they cannot play
    /// to reach the one they can.
    private func ordered(_ roles: [KnownRole]) -> [KnownRole] {
        guard !available.isEmpty else { return Array(roles.prefix(displayLimit)) }
        let playable = roles.filter { available[$0.id] != nil }
        let rest = roles.filter { available[$0.id] == nil }
        return Array((playable + rest).prefix(displayLimit))
    }

    private func open(_ item: MediaItem) {
        dismiss()
        onSelect(item)
    }

    #if os(tvOS)
    private var portrait: CGFloat { 200 }
    private var posterWidth: CGFloat { 180 }
    #else
    private var portrait: CGFloat { 110 }
    private var posterWidth: CGFloat { 96 }
    #endif

    /// A dozen is what "known for" means. Twice that many are fetched so the
    /// ones the provider carries can rise to the top of them.
    private var displayLimit: Int { 12 }
}
