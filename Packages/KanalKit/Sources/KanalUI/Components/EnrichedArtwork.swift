import KanalCore
import SwiftUI

/// Artwork for a film or show, upgraded to a real poster when we can identify it.
///
/// Provider artwork for VOD is usually a scaled-down channel logo or nothing at
/// all, which is what makes most IPTV apps look like a spreadsheet. This shows
/// the provider's image immediately and swaps in the proper poster once the
/// title is identified, so the grid never waits on the network to draw.
public struct EnrichedArtwork: View {
    @Environment(AppModel.self) private var model

    public let item: MediaItem
    public var symbol: String
    @State private var resolvedURL: URL?

    public init(item: MediaItem, symbol: String? = nil) {
        self.item = item
        self.symbol = symbol ?? item.kind.symbolName
    }

    public var body: some View {
        Artwork(url: resolvedURL ?? item.logoURL, title: item.title, symbol: symbol)
            .task(id: item.id) {
                guard resolvedURL == nil else { return }
                if let poster = await model.metadata.metadata(for: item)?.posterURL {
                    withAnimation(.easeOut(duration: 0.25)) { resolvedURL = poster }
                }
            }
    }
}
