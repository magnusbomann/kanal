import KanalCore
import SwiftUI

/// A shared offer with layouts made for touch and the television remote.
/// Prices and trial eligibility come exclusively from PurchaseStore.
public struct ProView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var planFocus
    @State private var selection: KanalProduct = .preferred
    @State private var didPurchase = false
    @State private var legalDocument: LegalDocumentView.Document?

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900 && !typeSize.isAccessibilitySize
            ScrollView {
                if wide {
                    HStack(alignment: .center, spacing: KanalMetrics.xxl) {
                        introduction(illustrated: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: KanalMetrics.md) {
                            plans
                            checkout
                            footer
                        }
                        .frame(maxWidth: .infinity)
                        #if os(tvOS)
                        .focusSection()
                        #endif
                    }
                    .frame(maxWidth: 1500, minHeight: geometry.size.height - 96)
                    .padding(48)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        introduction(illustrated: false)
                        plans
                        if typeSize.isAccessibilitySize { checkout }
                        footer
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            #if !os(tvOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !wide && !typeSize.isAccessibilitySize {
                    checkout
                        .frame(maxWidth: 512)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity)
                        .background(KanalColor.surface)
                        .overlay(alignment: .top) { Rectangle().fill(KanalColor.separator).frame(height: 1) }
                }
            }
            #endif
        }
        #if os(tvOS)
        .frame(width: 1640, height: 900)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro.screen")
        .background {
            KanalColor.background
                .overlay(alignment: .topLeading) {
                    RadialGradient(colors: [KanalColor.accentSolid.opacity(0.12), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 560)
                }
                .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            #if !os(tvOS)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KanalColor.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(KanalColor.surface.opacity(0.9), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(UIStrings.proActionNotNow))
            .accessibilityIdentifier("pro.close")
            .padding(8)
            #endif
        }
        .task { await store.loadProducts() }
        .onChange(of: store.offers, initial: true) { _, offers in
            guard let first = offers.first else { return }
            if !offers.contains(where: { $0.product == selection }) { selection = first.product }
        }
        .onChange(of: store.isPro, initial: true) { _, isPro in
            if isPro {
                didPurchase = true
                dismiss()
            }
        }
        .onDisappear {
            store.forgetPendingPurchase()
            guard !didPurchase, !store.isPro else { return }
            store.recordPaywallDismissal()
        }
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(document: document) }
        }
        #if !os(tvOS)
        .presentationBackground(KanalColor.background)
        .presentationDetents([.large])
        #endif
    }

    private func introduction(illustrated: Bool) -> some View {
        VStack(alignment: .leading, spacing: illustrated ? 28 : 16) {
            HStack(spacing: 8) {
                Text(UIStrings.proHeadlineTop)
                    .font(.headline.weight(.black))
                    .tracking(2)
                Text(UIStrings.proHeadlineBottom)
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(KanalColor.accent, in: Capsule())
                    .foregroundStyle(KanalColor.onAccent)
            }
            .accessibilityElement(children: .combine)

            if illustrated { cinemaIllustration }

            Text(UIStrings.proValueTitle)
                .font(heroFont)
                .tracking(-1.2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: illustrated ? 20 : 12) {
                benefit("rectangle.slash", UIStrings.proFeatureNoWatermark)
                benefit("moon.stars", UIStrings.proNoReminders)
                benefit("tv.and.mediabox", UIStrings.proAllDevices)
            }
            Text(UIStrings.proContentNotice)
                .font(supportFont)
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(KanalColor.primaryText)
    }

    /// An abstract screen, without suggesting that a content catalogue is sold.
    private var cinemaIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.08, green: 0.07, blue: 0.10))
            Ellipse()
                .fill(KanalColor.accent)
                .frame(width: 280, height: 110)
                .blur(radius: 65)
                .offset(x: 60, y: 70)
            Image(systemName: "play.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .background(.white.opacity(0.10), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private func benefit(_ symbol: String, _ label: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(KanalColor.primaryText)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(label)
                .font(bodyFont)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var plans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.proChoosePlan)
                .font(KanalFont.section())
                .foregroundStyle(KanalColor.primaryText)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if !store.offers.isEmpty {
                ForEach(store.offers) { offer in
                    PlanRow(offer: offer, isSelected: effectiveSelection == offer.product, focusNamespace: planFocus) {
                        selection = offer.product
                    }
                    .disabled(isBusy || store.isPending)
                }
                if store.offers.contains(where: { $0.savingsPercent != nil }) {
                    Text(UIStrings.proSavingsDetail)
                        .font(supportFont)
                        .foregroundStyle(KanalColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if store.productLoadFailed {
                VStack(alignment: .leading, spacing: 16) {
                    Label { Text(UIStrings.proUnavailable) } icon: { Image(systemName: "wifi.exclamationmark") }
                        .font(bodyFont)
                        .foregroundStyle(KanalColor.secondaryText)
                    Button(String(UIStrings.proActionRetry)) { Task { await store.loadProducts() } }
                        .buttonStyle(KanalSecondaryButtonStyle())
                        .accessibilityIdentifier("pro.retry")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KanalColor.surface, in: RoundedRectangle(cornerRadius: 20))
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(UIStrings.proLoading).font(bodyFont)
                }
                .foregroundStyle(KanalColor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        #if os(tvOS)
        .focusScope(planFocus)
        #endif
    }

    private var checkout: some View {
        VStack(spacing: 10) {
            if let offer = selectedOffer {
                Text(billingSummary(offer))
                    .font(supportFont.weight(.medium))
                    .foregroundStyle(KanalColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pro.billing")
            }
            if store.isPending {
                Label { Text(UIStrings.proPending) } icon: { Image(systemName: "clock") }
                    .font(supportFont)
                    .foregroundStyle(KanalColor.primaryText)
                    .accessibilityIdentifier("pro.pending")
            }
            if let failure = store.failure {
                Label { Text(failure) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(supportFont)
                    .foregroundStyle(KanalColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pro.error")
            }
            Button {
                Task {
                    if await store.purchase(effectiveSelection) {
                        didPurchase = true
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isBusy { ProgressView().tint(KanalColor.onAccent) }
                    Text(selectedOffer?.trial != nil ? UIStrings.proActionTryFree : UIStrings.proSettingsUpgrade)
                    if !isBusy { Image(systemName: "arrow.right").accessibilityHidden(true) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))
            .disabled(isBusy || store.isPending || selectedOffer == nil)
            .accessibilityIdentifier("pro.purchase")

            if selectedOffer != nil {
                Text(effectiveSelection.isSubscription ? UIStrings.proSmallPrintSubscription : UIStrings.proSmallPrintLifetime)
                    .font(supportFont)
                    .foregroundStyle(KanalColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            Label { Text(UIStrings.proAppStorePayment) } icon: { Image(systemName: "lock.shield") }
                .font(supportFont)
                .foregroundStyle(KanalColor.secondaryText)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { secondaryActions }.buttonStyle(ProTextButtonStyle())
                VStack(spacing: 4) { secondaryActions }.buttonStyle(ProTextButtonStyle())
            }
            Text(UIStrings.proReassurance)
                .font(supportFont)
                .foregroundStyle(KanalColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { legalActions }
                VStack(spacing: 4) { legalActions }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        Button(String(UIStrings.proContinueFree)) { dismiss() }
            .accessibilityIdentifier("pro.continueFree")
        Button {
            Task { await store.restore() }
        } label: {
            HStack(spacing: 8) {
                if store.isRestoring { ProgressView() }
                Text(UIStrings.proActionRestore)
            }
        }
        .disabled(isBusy)
        .accessibilityIdentifier("pro.restore")
    }

    private var legalActions: some View {
        Group {
            Button(String(UIStrings.proTerms)) { legalDocument = .terms }
                .accessibilityIdentifier("pro.terms")
            Button(String(UIStrings.proPrivacy)) { legalDocument = .privacy }
                .accessibilityIdentifier("pro.privacy")
        }
        .buttonStyle(ProTextButtonStyle())
    }

    private var isBusy: Bool { store.purchasing != nil || store.isRestoring }
    private var selectedOffer: PlanOffer? { store.offers.first { $0.product == effectiveSelection } }
    private var effectiveSelection: KanalProduct {
        store.offers.contains(where: { $0.product == selection }) ? selection : store.offers.first?.product ?? selection
    }
    private func billingSummary(_ offer: PlanOffer) -> LocalizedStringResource {
        let period = String(offer.product.paywallPeriod)
        if let trial = offer.trial {
            return UIStrings.proTrialBilling(trial, offer.displayPrice, period)
        }
        return UIStrings.proBilling(offer.displayPrice, period)
    }
    private var heroFont: Font {
        #if os(tvOS)
        .system(size: 58, weight: .bold)
        #else
        .system(.largeTitle, weight: .bold)
        #endif
    }
    private var bodyFont: Font {
        #if os(tvOS)
        .system(size: 25)
        #else
        .subheadline
        #endif
    }
    private var supportFont: Font {
        #if os(tvOS)
        .system(size: 20)
        #else
        .footnote
        #endif
    }
}

private struct PlanRow: View {
    let offer: PlanOffer
    let isSelected: Bool
    let focusNamespace: Namespace.ID
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(isSelected ? KanalColor.accentSolid : KanalColor.secondaryText)
                    .accessibilityHidden(true)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { name; price }
                } else {
                    VStack(alignment: .leading, spacing: 5) { name }
                    Spacer(minLength: 0)
                    price
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: KanalMetrics.minTarget, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(ProPlanButtonStyle())
        .focused($focused)
        #if os(tvOS)
        .prefersDefaultFocus(isSelected, in: focusNamespace)
        #endif
        .background(isSelected ? KanalColor.accentSolid.opacity(0.08) : KanalColor.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(focused ? KanalColor.primaryText : isSelected ? KanalColor.accentSolid : KanalColor.separator,
                              lineWidth: focused ? 4 : isSelected ? 2 : 1)
        }
        .scaleEffect(focused ? 1.025 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focused)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("pro.plan.\(offer.product)")
    }

    @ViewBuilder
    private var name: some View {
        Text(offer.product.paywallName)
            .font(KanalFont.section())
            .foregroundStyle(KanalColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        if let saving = offer.savingsPercent {
            Text(UIStrings.proPlanSave(saving))
                .font(KanalFont.caption())
                .foregroundStyle(KanalColor.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(KanalColor.accentSolid.opacity(0.18), in: Capsule())
        } else if let trial = offer.trial {
            Text(UIStrings.proTrial(trial))
                .font(KanalFont.caption())
                .foregroundStyle(KanalColor.secondaryText)
        }
    }

    private var price: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text(offer.displayPrice)
                .font(KanalFont.section())
                .foregroundStyle(KanalColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Text(offer.product.paywallPeriod)
                .font(KanalFont.caption())
                .foregroundStyle(KanalColor.secondaryText)
        }
    }
}

private struct ProPlanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct ProTextButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KanalFont.caption())
            .foregroundStyle(KanalColor.secondaryText)
            .padding(.horizontal, 8)
            .frame(minHeight: KanalMetrics.minTarget)
            .background(focused || configuration.isPressed ? KanalColor.surfaceElevated : .clear, in: Capsule())
            .overlay { Capsule().stroke(focused ? KanalColor.primaryText : .clear, lineWidth: 2) }
            .contentShape(Capsule())
    }
}

private extension KanalProduct {
    var paywallName: LocalizedStringResource {
        switch self {
        case .monthly: UIStrings.proPlanMonthly
        case .yearly: UIStrings.proPlanYearly
        case .lifetime: UIStrings.proPlanLifetime
        }
    }
    var paywallPeriod: LocalizedStringResource {
        switch self {
        case .monthly: UIStrings.proPeriodMonth
        case .yearly: UIStrings.proPeriodYear
        case .lifetime: UIStrings.proPeriodOnce
        }
    }
}
