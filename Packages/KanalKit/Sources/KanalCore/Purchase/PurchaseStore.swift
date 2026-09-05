import Foundation
import Observation
import StoreKit

/// What Kanal knows about being paid for.
///
/// There is no server and no account, so the App Store receipt is the whole
/// truth: `Transaction.currentEntitlements` is asked at launch and listened to
/// afterwards. That is also why Family Sharing and Universal Purchase carry the
/// weight here — one purchase has to cover a household's iPhone, iPad and
/// Apple TV without anything of ours knowing they are the same household.
@MainActor
@Observable
public final class PurchaseStore {

    /// The only question the rest of the app asks.
    public private(set) var isPro = false
    /// Loaded from the App Store, in the order the paywall shows them.
    public private(set) var products: [Product] = []
    /// The same three things with their prices already resolved.
    ///
    /// The paywall reads this and never touches StoreKit, which is what lets
    /// the screen be opened and looked at without a store behind it.
    public private(set) var offers: [PlanOffer] = []
    public private(set) var isLoadingProducts = false
    public private(set) var productLoadFailed = false
    /// Non-nil while a purchase sheet is up, so one tap cannot start two.
    public private(set) var purchasing: KanalProduct?
    public private(set) var isRestoring = false
    /// Set when the store itself failed. A cancelled purchase is not an error
    /// and never lands here.
    public private(set) var failure: String?
    /// Pacing for the interstitial. Persisted, so it survives relaunches.
    public private(set) var nudge = ProNudge()

    private let storage: KanalStorage
    /// Never cancelled: this object lives as long as the app does, and a
    /// `deinit` on a main-actor class cannot touch isolated state anyway.
    @ObservationIgnored private var updates: Task<Void, Never>?
    // A TV viewing session may show at most one unsolicited offer. The
    // persisted day-long interval also prevents relaunches from repeating it.
    private var hasShownTVOffer = false
    private static let nudgeFile = "pro-nudge.json"

    public init(storage: KanalStorage = .shared) {
        self.storage = storage
        // Started before anything is loaded: a purchase completed on another
        // device, or an Ask-to-Buy approval arriving hours later, both come
        // through here rather than through any call we make.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
    }

    /// Restores persisted pacing and asks the App Store what this Apple ID owns.
    public func start() async {
        if let stored = await storage.load(ProNudge.self, from: Self.nudgeFile) {
            nudge = stored
        }
        await refreshEntitlement()
        await loadProducts()
    }

    // MARK: Entitlement

    public func refreshEntitlement() async {
        if let forced = Self.debugOverride {
            isPro = forced
            return
        }
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard KanalProduct(rawValue: transaction.productID) != nil else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate,
               expirationDate <= .now {
                continue
            }
            entitled = true
            break
        }
        isPro = entitled
    }

    // MARK: Products

    public func loadProducts() async {
        // `offers` rather than `products`: a paywall opened twice must not
        // refetch, and in a debug run it must not overwrite seeded prices.
        guard offers.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        productLoadFailed = false
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: KanalProduct.allCases.map(\.rawValue))
            let order = KanalProduct.displayOrder.map(\.rawValue)
            products = loaded.sorted {
                (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
            }
            await rebuildOffers()
        } catch {
            // Not surfaced as a failure banner. An offline paywall showing its
            // own copy without prices is better than an error where the
            // prices should be; the buy button reports the real problem.
            products = []
            offers = []
            productLoadFailed = true
        }
    }

    private func rebuildOffers() async {
        var built: [PlanOffer] = []
        let annualSavings = savingsAgainstMonthly()
        for kanalProduct in KanalProduct.displayOrder {
            guard let product = product(for: kanalProduct) else { continue }
            let trial = await introductoryOffer(for: kanalProduct)
                .map { SubscriptionPeriodText.describe($0.period) }
            built.append(PlanOffer(
                product: kanalProduct,
                displayPrice: product.displayPrice,
                trial: trial,
                savingsPercent: kanalProduct == .yearly ? annualSavings : nil
            ))
        }
        offers = built
    }

    public func product(for kanalProduct: KanalProduct) -> Product? {
        products.first { $0.id == kanalProduct.rawValue }
    }

    private func savingsAgainstMonthly() -> Int? {
        guard let monthly = product(for: .monthly)?.price,
              let yearly = product(for: .yearly)?.price else { return nil }
        let monthlyForYear = monthly * 12
        guard monthlyForYear > 0, yearly < monthlyForYear else { return nil }
        let percent = NSDecimalNumber(
            decimal: ((monthlyForYear - yearly) / monthlyForYear) * 100
        ).intValue
        return percent > 0 ? percent : nil
    }

    /// The free trial attached to a product, if this Apple ID is still eligible
    /// for one. Shown as "7 days free" rather than as a price.
    public func introductoryOffer(for kanalProduct: KanalProduct) async -> Product.SubscriptionOffer? {
        guard let product = product(for: kanalProduct),
              let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer
        else { return nil }
        return offer
    }

    // MARK: Buying

    /// Returns `true` when the purchase went through, so the paywall can close
    /// itself rather than watching a flag.
    @discardableResult
    public func purchase(_ kanalProduct: KanalProduct) async -> Bool {
        guard purchasing == nil, !isRestoring else { return false }
        guard let product = product(for: kanalProduct) else {
            failure = CoreStrings.purchaseUnavailable.resolved
            return false
        }
        purchasing = kanalProduct
        failure = nil
        defer { purchasing = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // An unverified transaction is not a purchase we can honour
                    // — the signature is the only proof there is.
                    failure = CoreStrings.purchaseUnverified.resolved
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                nudge.reset()
                await persistNudge()
                return isPro
            case .pending:
                // Ask to Buy. Nothing has failed and nothing has been bought;
                // `Transaction.updates` will bring the answer whenever it comes.
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    /// For someone who already paid — a reinstall, a second device, a family
    /// member. Required on the paywall by App Review, and by decency.
    public func restore() async {
        guard !isRestoring, purchasing == nil else { return }
        isRestoring = true
        failure = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isPro {
                failure = CoreStrings.purchaseNothingToRestore.resolved
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: Nudging

    /// Called when the player closes. See `ProNudge` for why each rule exists.
    public func playbackClosed(didPlay: Bool, isRestricted: Bool) -> Bool {
        #if os(tvOS)
        let shouldPresent = nudge.playbackClosed(
            didPlay: didPlay, isPro: isPro, isRestricted: isRestricted,
            allowsPrompt: !hasShownTVOffer, minimumInterval: 24 * 60 * 60
        )
        if shouldPresent { hasShownTVOffer = true }
        #else
        let shouldPresent = nudge.playbackClosed(
            didPlay: didPlay, isPro: isPro, isRestricted: isRestricted
        )
        #endif
        Task { await persistNudge() }
        return shouldPresent
    }

    public func recordPaywallDismissal() {
        nudge.recordDismissal()
        Task { await persistNudge() }
    }

    private func persistNudge() async {
        await storage.save(nudge, to: Self.nudgeFile)
    }

    // MARK: Development

    /// Pluss without paying, for development only.
    ///
    /// Three ways in, checked in order, all compiled out of a release build:
    ///
    ///   * `-kanal-pro 1` as a launch argument (also `0`, to force free)
    ///   * `KANAL_PRO=1` in the environment
    ///   * the Developer switch at the bottom of Settings
    ///
    /// TestFlight builds need none of this — sandbox purchases there are free
    /// and exercise the real StoreKit path, which is the one worth testing.
    public static var debugOverride: Bool? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-kanal-pro"), index + 1 < arguments.count {
            return arguments[index + 1] != "0"
        }
        if let value = ProcessInfo.processInfo.environment["KANAL_PRO"] {
            return value != "0"
        }
        if UserDefaults.standard.object(forKey: debugDefaultsKey) != nil {
            return UserDefaults.standard.bool(forKey: debugDefaultsKey)
        }
        return nil
        #else
        return nil
        #endif
    }

    public static let debugDefaultsKey = "kanal.debug.pro"

    #if DEBUG
    /// Forgets the pacing, so a test starts where a fresh install does.
    public func resetNudge() async {
        nudge.reset()
        await persistNudge()
    }

    /// Prices with no App Store behind them, so the paywall can be opened and
    /// looked at in a plain simulator run. `-kanal-paywall` turns it on.
    public func seedSampleOffers() {
        guard offers.isEmpty else { return }
        offers = [
            PlanOffer(product: .monthly, displayPrice: "kr 39,00", trial: nil),
            PlanOffer(
                product: .yearly,
                displayPrice: "kr 249,00",
                trial: "7 dager",
                savingsPercent: 47
            ),
            PlanOffer(product: .lifetime, displayPrice: "kr 599,00", trial: nil),
        ]
    }
    #endif

    #if DEBUG
    /// Backs the Developer switch. `nil` hands control back to the real receipt.
    public func setDebugPro(_ value: Bool?) async {
        if let value {
            UserDefaults.standard.set(value, forKey: Self.debugDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.debugDefaultsKey)
        }
        await refreshEntitlement()
    }
    #endif
}
