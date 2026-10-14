import DistrictL10n
import DistrictModel
import Foundation

/// A billing amount as the billing screen shows it, with its currency.
///
/// ⛔ CURRENCY-AWARE IN FRENCH ONLY. `GET /api/billing` sends Stripe's `currency` on each
/// subscription and invoice, and French then names it, as the website does: « 249,00 $ CA »
/// for `cad`, « 249,00 $ US » for `usd`, through ``L10nFormat``'s money table, which is
/// held to `contracts/i18n/format-vectors.json`. A body without one reads « 249,00 $ ».
///
/// ⛔ ENGLISH IS EXACTLY WHAT THE APPS SHOW TODAY, WITH OR WITHOUT A CURRENCY: `$249.00`,
/// no thousands separator, and the sign after the dollar (`$-15.00`) for a credit. A
/// currency-aware English price (`CA$249.00`) is a product decision, not part of v3.
public enum BillingMoneyFormat {
    /// `cents` (Stripe minor units) of `currency`, nil when the service did not say.
    public static func price(cents: Int, currency: String?, locale: L10nLocale = L10nRuntime.locale) -> String {
        switch locale {
        case .en:
            return "$" + englishAmount(cents)
        case .frCA:
            // ⚠️ `narrow` IS THE BARE DOLLAR GLYPH, « 249,00 $ », which claims no country:
            // the French a billing line shows when the currency is not known.
            guard let currency else {
                return L10nFormat.money(minorUnits: cents, currency: "cad", display: .narrow, locale: locale)
            }
            return L10nFormat.money(minorUnits: cents, currency: currency, locale: locale)
        }
    }

    /// `249.00`, `1204.25`, `-15.00`: the apps' English billing amount.
    ///
    /// ⚠️ DIVIDED AND REMAINDERED BEFORE `magnitude`, so `Int.min` cannot trap.
    private static func englishAmount(_ cents: Int) -> String {
        let units = (cents / 100).magnitude
        let fraction = (cents % 100).magnitude
        let padded = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return (cents < 0 ? "-" : "") + "\(units).\(padded)"
    }
}

public extension BillingSubscription {
    /// `cents` of this subscription's currency (its ``amount`` or a discount's
    /// `amountOff`) as the billing screen shows it. See ``BillingMoneyFormat``.
    func price(cents: Int, locale: L10nLocale = L10nRuntime.locale) -> String {
        BillingMoneyFormat.price(cents: cents, currency: currency, locale: locale)
    }
}

public extension BillingInvoice {
    /// `cents` of this invoice's currency (its total, tax or amount paid) as the billing
    /// screen shows it. See ``BillingMoneyFormat``.
    func price(cents: Int, locale: L10nLocale = L10nRuntime.locale) -> String {
        BillingMoneyFormat.price(cents: cents, currency: currency, locale: locale)
    }
}
