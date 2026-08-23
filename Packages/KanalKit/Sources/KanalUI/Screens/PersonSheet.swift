import KanalCore
import SwiftUI

/// Who that was.
///
/// Reached by tapping a face in the cast row. It answers one question — "where
/// do I know them from?" — so it is a photo, a paragraph, and the work they
/// are best known for, and nothing else.
public struct PersonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public let member: CastMember
    @State private var profile: PersonProfile?
    @State private var isLoading = true

    public init(member: CastMember) {
        self.member = member
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
                    knownFor(known)
                }
            }
            .padding(KanalMetrics.lg)
        }
        .background(KanalColor.background)
        .scrollIndicators(.hidden)
        .task(id: member.id) {
            profile = await model.metadata.person(id: member.id)
            isLoading = false
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
                        VStack(alignment: .leading, spacing: KanalMetrics.xs) {
                            Artwork(
                                url: role.posterURL, title: role.title,
                                symbol: role.isSeries ? "rectangle.stack" : "film"
                            )
                            .aspectRatio(KanalMetrics.posterAspect, contentMode: .fill)
                            .frame(width: posterWidth)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))

                            Text(role.title)
                                .font(KanalFont.body(12))
                                .foregroundStyle(KanalColor.primaryText)
                                .lineLimit(2)
                                .frame(width: posterWidth, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    #if os(tvOS)
    private var portrait: CGFloat { 200 }
    private var posterWidth: CGFloat { 180 }
    #else
    private var portrait: CGFloat { 110 }
    private var posterWidth: CGFloat { 96 }
    #endif
}
