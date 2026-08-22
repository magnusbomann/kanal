import KanalCore
import SwiftUI

/// A nothing-here message. Always says what to do next, never just "no results".
public struct EmptyStateView: View {
    public let symbol: String
    public let title: String
    public let message: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: KanalMetrics.md) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(KanalColor.tertiaryText)
            Text(title)
                .font(KanalFont.section(18))
                .foregroundStyle(KanalColor.primaryText)
            Text(message)
                .font(KanalFont.body(14))
                .foregroundStyle(KanalColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                    .padding(.top, KanalMetrics.sm)
            }
        }
        .padding(KanalMetrics.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KanalColor.background)
    }
}

/// Shown while a playlist loads. Big playlists take a while, so the copy says
/// what is happening rather than spinning silently.
public struct LoadingView: View {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: KanalMetrics.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(KanalColor.accentSolid)
            VStack(spacing: KanalMetrics.xs) {
                Text(message)
                    .font(KanalFont.section(17))
                    .foregroundStyle(KanalColor.primaryText)
                Text(UIStrings.loadingDetail)
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KanalColor.background)
    }
}
