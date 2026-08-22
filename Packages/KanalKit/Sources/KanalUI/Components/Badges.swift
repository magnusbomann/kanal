import KanalCore
import SwiftUI

/// The pulsing "LIVE" marker.
public struct LiveBadge: View {
    @State private var isPulsing = false

    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.35 : 1)
            Text(UIStrings.live)
        }
        .kanalLabel(11)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(KanalColor.live, in: .capsule)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityLabel(Text(UIStrings.liveNowAccessibility))
    }
}

/// A neutral metadata chip: year, quality, category, channel number.
public struct MetaChip: View {
    public let text: String
    public var emphasized: Bool

    public init(_ text: String, emphasized: Bool = false) {
        self.text = text
        self.emphasized = emphasized
    }

    public var body: some View {
        Text(text)
            .kanalLabel(11)
            .foregroundStyle(emphasized ? KanalColor.primaryText : KanalColor.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                KanalColor.surfaceElevated.opacity(emphasized ? 1 : 0.7),
                in: .capsule
            )
    }
}

/// Thin progress line drawn under artwork for partly-watched items.
public struct ProgressLine: View {
    public let fraction: Double

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(KanalColor.accent)
                    .frame(width: max(proxy.size.width * fraction, 3))
            }
        }
        .frame(height: 3)
        .accessibilityLabel(Text(UIStrings.percentWatched(Int(fraction * 100))))
    }
}
