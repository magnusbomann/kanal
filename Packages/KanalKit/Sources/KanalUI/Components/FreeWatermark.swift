import KanalCore
import SwiftUI

/// The mark drawn over video in the free tier.
///
/// The quieter of the two nudges, and the one that runs all the time — so it
/// is built to be noticed and not to be resented: the wordmark at caption size
/// in a corner, half opacity, and gone the moment the controls come up so it
/// never sits on top of a button.
///
/// It is a button. Someone who has looked at it for an hour and finally wants
/// it gone should not have to go and find Settings.
struct FreeWatermark: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(UIStrings.proWatermark)
                .kanalLabel(11)
                .foregroundStyle(.white.opacity(0.5))
                // Video is arbitrary: a white mark vanishes into a snowy
                // outside broadcast without something dark behind it.
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .padding(.horizontal, KanalMetrics.sm)
                .padding(.vertical, KanalMetrics.xs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
