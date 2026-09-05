import Foundation

/// The three things Kanal sells.
///
/// One entitlement — "Pluss" — reached three ways. Nothing in the app asks
/// *which* one someone bought, only whether they have it, so a fourth offer or
/// a retired price can be added here without any screen learning about it.
public enum KanalProduct: String, CaseIterable, Sendable, Identifiable {
    case monthly = "com.bomann.kanal.pro.monthly"
    case yearly = "com.bomann.kanal.pro.yearly"
    case lifetime = "com.bomann.kanal.pro.lifetime"

    public var id: String { rawValue }

    /// The one offered first. Yearly carries the free trial, and a year is the
    /// unit a television subscription is naturally measured in.
    public static let preferred = KanalProduct.yearly

    /// Ordered as they appear on the paywall: cheapest commitment, best value,
    /// then the one-off.
    public static let displayOrder: [KanalProduct] = [.monthly, .yearly, .lifetime]

    public var isSubscription: Bool { self != .lifetime }
}

/// Features that could be held back from the free tier.
///
/// Nothing here is enforced yet — v1 nudges rather than blocks, which is the
/// whole point of the watermark and the interstitial. The list exists so that
/// deciding to lock one later is an edit in a single file rather than an audit
/// of every screen, and so that the paywall's own copy has somewhere to read
/// its promises from.
public enum ProFeature: String, CaseIterable, Sendable {
    case multiplePlaylists
    case profiles
    case handoff
    case richMetadata
    case fullGuide
    case automaticStreamFailover

    /// The ones a free user is actually stopped from using.
    ///
    /// Deliberately empty. Free must stay a usable television, or the two
    /// nudges have nothing to nudge *from* — someone who cannot watch anything
    /// does not upgrade, they delete the app.
    public static let enforced: Set<ProFeature> = []

    public var isEnforced: Bool { Self.enforced.contains(self) }
}
