import KanalCore
import SwiftUI

/// The first thing anyone sees.
///
/// Landing straight on an empty field asks a question the person has not been
/// told the answer to. Two short pages first — what this is, and what to go
/// find — then the field. Nothing here is a feature tour; it exists only so
/// that by the time someone reaches the paste box they know what to paste.
public struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    public init() {}

    /// Marked complete only on reaching the field — recording it any earlier
    /// would flip the root view over mid-intro and skip the rest of it.
    private func advance(to next: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            page = next
        }
        if next >= pages.count {
            Task { await model.completeIntro() }
        }
    }

    private var pages: [IntroPage] {
        [
            IntroPage(
                symbol: "sparkles.tv",
                headlineTop: UIStrings.introOneHeadlineTop,
                headlineBottom: UIStrings.introOneHeadlineBottom,
                body: UIStrings.introOneBody
            ),
            IntroPage(
                symbol: "link",
                headlineTop: UIStrings.introTwoHeadlineTop,
                headlineBottom: UIStrings.introTwoHeadlineBottom,
                body: UIStrings.introTwoBody
            ),
        ]
    }

    public var body: some View {
        #if os(tvOS)
        // Apple TV has no good reason to make someone page through an intro
        // before showing the one setup action that matters: scan the TV from
        // the phone. WelcomeView owns that complete setup surface.
        WelcomeView()
            .task { await model.completeIntro() }
        #else
        if page >= pages.count {
            WelcomeView()
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: KanalMetrics.xl) {
                    IntroPageView(page: pages[page])

                    VStack(spacing: KanalMetrics.md) {
                        Button(String(UIStrings.introContinue)) {
                            advance(to: page + 1)
                        }
                        .accessibilityIdentifier("onboarding.continue")
                        .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))

                        Button(String(UIStrings.introSkip)) {
                            advance(to: pages.count)
                        }
                        .accessibilityIdentifier("onboarding.skip")
                        .kanalLabel(12)
                        .foregroundStyle(KanalColor.secondaryText)
                        .buttonStyle(.plain)
                    }

                    PageDots(count: pages.count + 1, current: page)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.vertical, KanalMetrics.xxl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KanalColor.background)
            .transition(.opacity)
        }
        #endif
    }
}

struct IntroPage {
    let symbol: String
    let headlineTop: LocalizedStringResource
    let headlineBottom: LocalizedStringResource
    let body: LocalizedStringResource
}

struct IntroPageView: View {
    let page: IntroPage

    var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.lg) {
            Image(systemName: page.symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(KanalColor.accent)

            VStack(alignment: .leading, spacing: 0) {
                Text(page.headlineTop)
                    .kanalDisplay(headlineSize)
                    .foregroundStyle(KanalColor.primaryText)
                Text(page.headlineBottom)
                    .kanalDisplay(headlineSize)
                    .foregroundStyle(KanalColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(page.body)
                .font(KanalFont.body(bodySize))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(tvOS)
    private var symbolSize: CGFloat { 64 }
    private var headlineSize: CGFloat { 70 }
    private var bodySize: CGFloat { 22 }
    #else
    private var symbolSize: CGFloat { 40 }
    private var headlineSize: CGFloat { 42 }
    private var bodySize: CGFloat { 16 }
    #endif
}

/// Position, so the intro reads as short rather than open-ended.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: KanalMetrics.sm) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? KanalColor.accentSolid : KanalColor.separator)
                    .frame(width: index == current ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
            }
        }
        .accessibilityLabel(Text(UIStrings.introStep(current + 1, count)))
    }
}
