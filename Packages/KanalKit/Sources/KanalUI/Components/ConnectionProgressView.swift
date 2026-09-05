import KanalCore
import SwiftUI

/// A calm, truthful setup checklist. Only the current step is animated; steps
/// already completed remain visible so a slow first import still feels alive.
struct ConnectionProgressView: View {
    let progress: ConnectionProgress
    var compact = false

    private let steps = ConnectionProgress.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? KanalMetrics.xs : KanalMetrics.sm) {
            ForEach(steps, id: \.self) { step in
                HStack(spacing: KanalMetrics.sm) {
                    Image(systemName: symbol(for: step))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colour(for: step))
                        .frame(width: 18)
                    Text(title(for: step))
                        .font(KanalFont.body(compact ? 13 : 15))
                        .foregroundStyle(step == progress ? KanalColor.primaryText : KanalColor.secondaryText)
                }
                .opacity(isFuture(step) ? 0.45 : 1)
            }
            if !compact {
                Text(UIStrings.connectionProgressDetail)
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.tertiaryText)
                    .padding(.top, KanalMetrics.xs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func isFuture(_ step: ConnectionProgress) -> Bool {
        guard let current = steps.firstIndex(of: progress),
              let candidate = steps.firstIndex(of: step) else { return false }
        return candidate > current
    }

    private func symbol(for step: ConnectionProgress) -> String {
        guard let current = steps.firstIndex(of: progress),
              let candidate = steps.firstIndex(of: step) else { return "circle" }
        if candidate < current || progress == .ready { return "checkmark.circle.fill" }
        if candidate == current { return "circle.dotted" }
        return "circle"
    }

    private func colour(for step: ConnectionProgress) -> Color {
        isFuture(step) ? KanalColor.tertiaryText : KanalColor.accentSolid
    }

    private func title(for step: ConnectionProgress) -> LocalizedStringResource {
        switch step {
        case .contacting: UIStrings.connectionContacting
        case .signingIn: UIStrings.connectionSigningIn
        case .loadingContent: UIStrings.connectionLoadingContent
        case .organising: UIStrings.connectionOrganising
        case .ready: UIStrings.connectionReady
        }
    }
}
