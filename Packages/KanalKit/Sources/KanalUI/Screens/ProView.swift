import KanalCore
import SwiftUI

/// The offer.
///
/// One screen, whether it arrives from Settings or from closing a stream. It
/// is deliberately short: a name, a sentence, four things, three prices, one
/// button. The last line matters as much as the first — it says the free app
/// keeps working, because someone who feels cornered does not buy, they leave.
public struct ProView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selection: KanalProduct = .preferred
    /// Stops `onDisappear` from counting a successful purchase as a refusal.
    @State private var didPurchase = false
    @State private var legalDocument: LegalDocumentView.Document?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.lg) {
                headline
                features
                plans
                actions
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.vertical, KanalMetrics.xl)
            .frame(maxWidth: paywallWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(KanalColor.background)
        .overlay(alignment: .topTrailing) {
            #if !os(tvOS)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KanalColor.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(KanalColor.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(UIStrings.proActionNotNow))
            .padding(KanalMetrics.md)
            #endif
        }
        .accessibilityIdentifier("pro.screen")
        .task { await store.loadProducts() }
        .onChange(of: store.offers, initial: true) { _, offers in
            guard let first = offers.first else { return }
            if !offers.contains(where: { $0.product == selection }) {
                selection = first.product
            }
        }
        .onChange(of: store.isPro) { _, isPro in
            // Covers the purchase that lands from somewhere else entirely —
            // Ask to Buy being approved, or a family member buying on another
            // device while this screen is open.
            if isPro {
                didPurchase = true
                dismiss()
            }
        }
        .onDisappear {
            guard !didPurchase, !store.isPro else { return }
            store.recordPaywallDismissal()
        }
        #if !os(tvOS)
        .presentationBackground(KanalColor.background)
        #endif
    }

    // MARK: Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            VStack(alignment: .leading, spacing: -6) {
                Text(UIStrings.proHeadlineTop)
                    .kanalDisplay(headlineSize)
                    .foregroundStyle(KanalColor.primaryText)
                Text(UIStrings.proHeadlineBottom)
                    .kanalDisplay(headlineSize)
                    .foregroundStyle(KanalColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(UIStrings.proBody)
                .font(KanalFont.body(16))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12 * KanalMetrics.scale) {
            feature("rectangle.slash", UIStrings.proFeatureNoWatermark)
            feature("person.2.fill", UIStrings.proFeatureProfiles)
            feature("sparkles", UIStrings.proFeatureMetadata)
            feature("appletv.fill", UIStrings.proFeatureHandoff)
        }
    }

    private func feature(_ symbol: String, _ label: LocalizedStringResource) -> some View {
        HStack(spacing: KanalMetrics.md) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KanalColor.accentSolid)
                .frame(width: 24)
            Text(label)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if !store.offers.isEmpty {
            VStack(spacing: KanalMetrics.sm) {
                ForEach(store.offers) { offer in
                    PlanRow(
                        offer: offer,
                        isSelected: effectiveSelection == offer.product,
                        onSelect: { selection = offer.product }
                    )
                }
            }
        } else if store.productLoadFailed {
            HStack(spacing: KanalMetrics.md) {
                Text(UIStrings.proUnavailable)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
                Spacer(minLength: KanalMetrics.sm)
                Button(String(UIStrings.proActionRetry)) {
                    Task { await store.loadProducts() }
                }
                .font(KanalFont.caption(13))
            }
            .padding(KanalMetrics.md)
            .background(KanalColor.surface, in: RoundedRectangle(
                cornerRadius: KanalMetrics.cardRadius, style: .continuous
            ))
        } else {
            HStack(spacing: KanalMetrics.sm) {
                ProgressView()
                Text(UIStrings.proLoading)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            Button {
                Task {
                    if await store.purchase(effectiveSelection) {
                        didPurchase = true
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: KanalMetrics.sm) {
                    if store.purchasing != nil {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(primaryActionTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))
            .disabled(store.purchasing != nil || store.isRestoring || store.offers.isEmpty)

            Text(smallPrint)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let failure = store.failure {
                Text(failure)
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: KanalMetrics.md) {
                #if os(tvOS)
                Button(String(UIStrings.proActionNotNow)) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(KanalColor.secondaryText)
                #endif
                Button(String(UIStrings.proActionRestore)) {
                    Task { await store.restore() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(KanalColor.secondaryText)
                .disabled(store.isRestoring || store.purchasing != nil)
            }
            .font(KanalFont.label(13))
            .frame(maxWidth: .infinity)

            Text(UIStrings.proReassurance)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: KanalMetrics.lg) {
                Button(String(UIStrings.proTerms)) { legalDocument = .terms }
                    .buttonStyle(.plain)
                Button(String(UIStrings.proPrivacy)) { legalDocument = .privacy }
                    .buttonStyle(.plain)
            }
            .font(KanalFont.body(11))
            .foregroundStyle(KanalColor.tertiaryText)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(document: document)
            }
        }
    }

    // MARK: Copy

    private var primaryActionTitle: LocalizedStringResource {
        let hasTrial = store.offers.first { $0.product == effectiveSelection }?.trial != nil
        return hasTrial ? UIStrings.proActionTryFree : UIStrings.proActionBuy
    }

    private var effectiveSelection: KanalProduct {
        if store.offers.contains(where: { $0.product == selection }) { return selection }
        return store.offers.first?.product ?? selection
    }

    private var smallPrint: LocalizedStringResource {
        effectiveSelection.isSubscription
            ? UIStrings.proSmallPrintSubscription
            : UIStrings.proSmallPrintLifetime
    }

    private var headlineSize: CGFloat {
        #if os(tvOS)
        76
        #else
        50
        #endif
    }

    private var paywallWidth: CGFloat {
        #if os(tvOS)
        920
        #else
        560
        #endif
    }

}

/// One price.
///
/// A row rather than a card grid: three cards side by side stop being readable
/// the moment a currency needs four digits, and a TV remote walks a column
/// better than it walks a row.
private struct PlanRow: View {
    let offer: PlanOffer
    let isSelected: Bool
    let onSelect: () -> Void

    private var product: KanalProduct { offer.product }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: KanalMetrics.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? KanalColor.accentSolid : KanalColor.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: KanalMetrics.sm) {
                        Text(name)
                            .font(KanalFont.body(16))
                            .foregroundStyle(KanalColor.primaryText)
                        if product == .preferred {
                            Text(badge)
                                .kanalLabel(10)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(KanalColor.accentSolid, in: Capsule())
                        }
                    }
                    if let trial = offer.trial {
                        Text(UIStrings.proTrial(trial))
                            .font(KanalFont.body(12))
                            .foregroundStyle(KanalColor.secondaryText)
                    }
                }

                Spacer(minLength: KanalMetrics.sm)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(offer.displayPrice)
                        .font(KanalFont.section(16))
                        .foregroundStyle(KanalColor.primaryText)
                    Text(period)
                        .font(KanalFont.body(11))
                        .foregroundStyle(KanalColor.secondaryText)
                }
            }
            .padding(.horizontal, KanalMetrics.md)
            .padding(.vertical, 12 * KanalMetrics.scale)
            .frame(minHeight: KanalMetrics.minTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: KanalMetrics.cardRadius, style: .continuous)
                .fill(isSelected ? KanalColor.surfaceElevated : KanalColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: KanalMetrics.cardRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? KanalColor.accentSolid : KanalColor.separator,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }

    private var name: LocalizedStringResource {
        switch product {
        case .monthly: UIStrings.proPlanMonthly
        case .yearly: UIStrings.proPlanYearly
        case .lifetime: UIStrings.proPlanLifetime
        }
    }

    private var badge: LocalizedStringResource {
        offer.savingsPercent.map(UIStrings.proPlanSave) ?? UIStrings.proPlanBest
    }

    private var period: LocalizedStringResource {
        switch product {
        case .monthly: UIStrings.proPeriodMonth
        case .yearly: UIStrings.proPeriodYear
        case .lifetime: UIStrings.proPeriodOnce
        }
    }
}
