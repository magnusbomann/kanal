import Foundation

/// Which versions of a title can be downloaded.
@MainActor
public extension AppModel {

    /// Every listing that is the same film as `item` — `item` itself for an
    /// episode or a film listed once. A download of any one of them counts as
    /// this film being on the device.
    func downloadVariants(for item: MediaItem) -> [MediaItem] {
        guard item.kind == .movie, let group = library.movieGroup(containing: item),
              group.variants.contains(where: { $0.id == item.id })
        else { return [item] }
        return group.variants
    }

    /// The versions to offer, with quality and size where the provider says.
    ///
    /// Asked one at a time: they are API calls, not streams, but a panel that
    /// limits connections is not one to fire a burst at.
    func downloadOptions(for item: MediaItem) async -> [DownloadOption] {
        var options: [DownloadOption] = []
        var probed = false
        for variant in downloadVariants(for: item) {
            var option = DownloadOption(
                item: variant,
                quality: (variant.qualityTag).flatMap(DownloadOption.quality(fromName:))
                    ?? DownloadOption.quality(fromName: variant.rawTitle)
            )
            if variant.kind == .movie, let panel = XtreamClient.panel(forMovieStream: variant.streamURL) {
                let facts = await panel.client.downloadFacts(streamID: panel.streamID)
                if let height = facts.height, height > 0 { option.quality = DownloadOption.quality(height: height) }
                option.estimatedBytes = facts.bytes
            }
            if option.estimatedBytes == nil {
                // Spaced out: several connections in quick succession is
                // what gets an account refused for minutes.
                if probed { try? await Task.sleep(for: .seconds(1.5)) }
                guard !Task.isCancelled else { break }
                option.estimatedBytes = await DownloadOption.probeSize(of: variant.streamURL)
                probed = true
            }
            options.append(option)
        }
        return options
    }
}
