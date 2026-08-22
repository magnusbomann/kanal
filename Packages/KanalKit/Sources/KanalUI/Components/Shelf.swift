import SwiftUI

/// A titled horizontal row of cards.
///
/// The whole home screen is shelves; keeping the header, spacing and edge
/// insets in one place is what makes the rows line up down the page.
public struct Shelf<Content: View>: View {
    public let title: String
    public var subtitle: String?
    public var itemWidth: CGFloat
    public var onSeeAll: (() -> Void)?
    @ViewBuilder public var content: () -> Content

    public init(
        title: String,
        subtitle: String? = nil,
        itemWidth: CGFloat = 180,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.itemWidth = itemWidth
        self.onSeeAll = onSeeAll
        self.content = content
    }

    /// Vertical slack so the focus scale is not clipped by the scroll view.
    private var focusHeadroom: CGFloat {
        #if os(tvOS)
        30
        #else
        0
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KanalFont.section(KanalMetrics.scale * 20))
                        .foregroundStyle(KanalColor.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(KanalFont.body(13))
                            .foregroundStyle(KanalColor.secondaryText)
                    }
                }
                Spacer()
                if let onSeeAll {
                    Button(String(UIStrings.seeAll), action: onSeeAll)
                        .kanalLabel(12)
                        .foregroundStyle(KanalColor.accentSolid)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KanalMetrics.lg)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: KanalMetrics.md) {
                    content()
                        .frame(width: itemWidth)
                }
                .padding(.horizontal, KanalMetrics.lg)
                // A focused card grows past its frame; give it somewhere to go.
                .padding(.vertical, focusHeadroom)
                .scrollTargetLayout()
            }
            .padding(.vertical, -focusHeadroom)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}
