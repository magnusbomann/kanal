import KanalCore
import SwiftUI

/// The other streams that carry this channel.
///
/// Providers list a channel several times over and some of those streams are
/// dead. Kanal folds them into one card and tries them in turn, but when the
/// automatic choice disappoints, this is where someone picks for themselves —
/// and whatever they pick is remembered for next time.
public struct ChannelSourcesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    public let group: ChannelGroup

    public init(group: ChannelGroup) {
        self.group = group
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            VStack(alignment: .leading, spacing: KanalMetrics.xs) {
                Text(UIStrings.sourcesTitle)
                    .kanalDisplay(26)
                    .foregroundStyle(KanalColor.primaryText)
                Text(group.name)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
            }

            ScrollView {
                LazyVStack(spacing: KanalMetrics.sm) {
                    ForEach(Array(group.variants.enumerated()), id: \.element.id) { index, variant in
                        Button {
                            if model.watchState.lockedVariants[group.id] != nil {
                                model.lockVariant(variant.id, forGroup: group.id)
                            }
                            navigator.play(variant, from: group)
                            dismiss()
                        } label: {
                            SourceRowView(
                                variant: variant,
                                position: index + 1,
                                isRemembered: model.watchState.workingVariants[group.id] == variant.id
                            )
                        }
                        .buttonStyle(KanalCardButtonStyle())
                    }
                }
            }

            Text(UIStrings.sourcesHint)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(KanalMetrics.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KanalColor.background)
        #if !os(tvOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(KanalColor.background)
        #endif
    }
}

struct SourceRowView: View {
    let variant: MediaItem
    let position: Int
    let isRemembered: Bool

    var body: some View {
        HStack(spacing: KanalMetrics.md) {
            // Formatted rather than interpolated: not every locale writes
            // numbers with the same digits.
            Text(position.formatted())
                .kanalLabel(12)
                .foregroundStyle(KanalColor.tertiaryText)
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                // The provider's own wording, because that is what
                // distinguishes one stream from another.
                Text(variant.rawTitle)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.primaryText)
                    .lineLimit(1)
                if let category = variant.category {
                    Text(CategoryLocalizer.display(category))
                        .font(KanalFont.body(12))
                        .foregroundStyle(KanalColor.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if isRemembered {
                Label(String(UIStrings.sourceLastWorked), systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(KanalColor.success)
            }
            if let quality = variant.qualityTag {
                MetaChip(quality)
            }
        }
        .padding(.horizontal, KanalMetrics.md)
        .frame(minHeight: KanalMetrics.minTarget + 10)
        .background(KanalColor.surface, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
