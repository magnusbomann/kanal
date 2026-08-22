import KanalCore
import SwiftUI

/// Remote artwork with a placeholder that never looks broken.
///
/// Provider logos are unreliable — wrong sizes, dead links, transparent PNGs on
/// white. The fallback is a tinted monogram tile so a missing image still reads
/// as a deliberate part of the layout.
public struct Artwork: View {
    public let url: URL?
    public let title: String
    public var symbol: String
    public var contentMode: ContentMode

    public init(
        url: URL?,
        title: String,
        symbol: String = "tv",
        contentMode: ContentMode = .fill
    ) {
        self.url = url
        self.title = title
        self.symbol = symbol
        self.contentMode = contentMode
    }

    public var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure, .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .background(KanalColor.surfaceElevated)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [monogramTint.opacity(0.35), monogramTint.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(monogram)
                .font(KanalFont.display(28))
                .foregroundStyle(monogramTint)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KanalColor.tertiaryText)
                .padding(6)
        }
    }

    private var monogram: String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Deterministic hue per title, so the same channel always looks the same.
    private var monogramTint: Color {
        let hash = title.unicodeScalars.reduce(into: UInt32(7)) { $0 = ($0 &* 31) &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.62)
    }
}
