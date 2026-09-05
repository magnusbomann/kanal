import Foundation
import StoreKit

/// One price, as the paywall needs it.
///
/// Everything StoreKit-shaped — verification, eligibility, locale-aware
/// formatting — has already happened by the time one of these exists. The view
/// gets three plain strings, which is also why the screen can be opened in a
/// simulator with no store behind it.
public struct PlanOffer: Identifiable, Sendable, Equatable {
    public let product: KanalProduct
    /// Already in the viewer's currency, from the App Store.
    public let displayPrice: String
    /// How much the annual plan saves against twelve monthly payments.
    /// Nil for plans that cannot be compared, and when the saving rounds to 0.
    public let savingsPercent: Int?
    /// The free trial, if this Apple ID is still eligible for one.
    public let trial: String?

    public var id: String { product.rawValue }

    public init(
        product: KanalProduct,
        displayPrice: String,
        trial: String? = nil,
        savingsPercent: Int? = nil
    ) {
        self.product = product
        self.displayPrice = displayPrice
        self.trial = trial
        self.savingsPercent = savingsPercent
    }
}

/// "7 days", in whatever language the device is in.
///
/// StoreKit hands over a unit and a count, not a phrase. Formatting it by hand
/// would produce "7 dager" for a Norwegian only by luck, and "1 måneder" the
/// rest of the time.
enum SubscriptionPeriodText {
    static func describe(_ period: Product.SubscriptionPeriod) -> String {
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = period.value
        case .week: components.weekOfMonth = period.value
        case .month: components.month = period.value
        case .year: components.year = period.value
        @unknown default: components.day = period.value
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? "\(period.value)"
    }
}
