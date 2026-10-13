import Foundation

/// How a currency is spelled beside an amount. The website's `MoneyDisplay`.
public enum MoneyDisplay: Sendable, Equatable {
    /// The locale's own symbol, which marks a foreign currency and leaves the home one
    /// bare: `$39`, `CA$59` in English, `39 $ US`, `59 $ CA` in French. The default,
    /// for an amount that has to be self-describing.
    case symbol
    /// The bare glyph, never disambiguated (`$39` for both dollars). Only beside a
    /// printed ISO code.
    case narrow
    /// `USD 2.00` / `2,00 USD`.
    case code
}

public extension L10nFormat {
    /// An amount in MINOR units (cents) of `currency`, the website's `formatMoney`.
    ///
    /// ⛔ THE GLOSSARY WINS OVER CLDR FOR CANADIAN DOLLARS IN FRENCH: `59,00 $ CA`, never
    /// a bare `$` that a Canadian cannot tell from a US one. Only the `symbol` display
    /// says it; `narrow` is the bare glyph by definition.
    ///
    /// ⚠️ `disambiguateDollar` WRITES US DOLLARS AS `US$39` IN ENGLISH, for a line that
    /// quotes several dollars at once. French already says `39 $ US`.
    ///
    /// ⚠️ USD, CAD AND EUR HAVE SYMBOLS; ANY OTHER THREE-LETTER CODE IS WRITTEN AS THE
    /// CODE (`XYZ 2.00` / `2,00 XYZ`), and anything else falls back to the code and
    /// the bare number (`BOGUS 2.00`), as the website does when `Intl` refuses the code.
    /// A carrier's GBP or AUD therefore reads `GBP 2.00` here where the website reads
    /// `£2.00`; no vector pins those and the core bills in the three it names.
    static func money(
        minorUnits: Int,
        currency: String,
        display: MoneyDisplay = .symbol,
        disambiguateDollar: Bool = false,
        locale: L10nLocale = L10nRuntime.locale
    ) -> String {
        format(
            MoneyDigits(minorUnits: minorUnits),
            currency: currency,
            display: display,
            disambiguateDollar: disambiguateDollar,
            locale: locale
        )
    }

    /// An amount in MAJOR units of any ISO 4217 code, the website's `formatIsoAmount`,
    /// for a price a carrier quoted in whatever currency it uses.
    static func isoAmount(_ major: Double, isoCode: String, locale: L10nLocale = L10nRuntime.locale) -> String {
        let cents = (abs(major) * 100).rounded(.toNearestOrAwayFromZero)
        let whole = (cents / 100).rounded(.down)
        let digits = MoneyDigits(whole: String(Int(whole)), cents: UInt(cents - whole * 100), negative: major < 0)
        return format(
            digits,
            currency: isoCode,
            display: .symbol,
            disambiguateDollar: false,
            locale: locale
        )
    }

    /// ``money(minorUnits:currency:display:disambiguateDollar:locale:)`` when the
    /// currency is known, and the bare number (`249.00` / `249,00`) when it is nil.
    ///
    /// ⛔ THE HONEST FALLBACK, NOT A STYLE: a guessed symbol states a price the customer
    /// is not paying, and a bare number claims nothing it cannot back.
    static func moneyOrBare(
        minorUnits: Int,
        currency: String?,
        locale: L10nLocale = L10nRuntime.locale
    ) -> String {
        guard let currency else { return MoneyDigits(minorUnits: minorUnits).signed(locale) }
        return money(minorUnits: minorUnits, currency: currency, locale: locale)
    }

    private static func format(
        _ digits: MoneyDigits,
        currency: String,
        display: MoneyDisplay,
        disambiguateDollar: Bool,
        locale: L10nLocale
    ) -> String {
        let code = currency.uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            // `Intl` refuses the code, and the website writes the trimmed code and the
            // number with `toFixed`: no grouping and a dot in every language.
            let trimmed = currency.trimmingCharacters(in: .whitespaces).uppercased()
            let number = digits.sign + digits.plain
            return trimmed.isEmpty ? number : trimmed + nbsp + number
        }
        let sign = digits.sign
        let amount = digits.localized(locale)
        switch locale {
        case .en:
            let mark = englishMark(code, display: display, disambiguateDollar: disambiguateDollar)
            return mark.isPrefixGlyph ? sign + mark.text + amount : sign + mark.text + nbsp + amount
        case .frCA:
            return sign + amount + nbsp + frenchMark(code, display: display)
        }
    }

    private static func englishMark(
        _ code: String,
        display: MoneyDisplay,
        disambiguateDollar: Bool
    ) -> (text: String, isPrefixGlyph: Bool) {
        switch (code, display) {
        case ("USD", .symbol): (disambiguateDollar ? "US$" : "$", true)
        case ("USD", .narrow), ("CAD", .narrow): ("$", true)
        case ("CAD", .symbol): ("CA$", true)
        case ("EUR", .symbol), ("EUR", .narrow): ("\u{20AC}", true)
        default: (code, false)
        }
    }

    private static func frenchMark(_ code: String, display: MoneyDisplay) -> String {
        switch (code, display) {
        case ("USD", .symbol): "$" + nbsp + "US"
        case ("CAD", .symbol): "$" + nbsp + "CA"
        case ("USD", .narrow), ("CAD", .narrow): "$"
        case ("EUR", .symbol), ("EUR", .narrow): "\u{20AC}"
        default: code
        }
    }
}

/// An amount split into its sign, its whole units and its two-digit cents.
private struct MoneyDigits {
    let whole: String
    let cents: UInt
    let negative: Bool

    init(whole: String, cents: UInt, negative: Bool) {
        self.whole = whole
        self.cents = cents
        self.negative = negative
    }

    init(minorUnits: Int) {
        let magnitude = minorUnits.magnitude
        self.init(whole: String(magnitude / 100), cents: magnitude % 100, negative: minorUnits < 0)
    }

    var sign: String {
        negative ? "-" : ""
    }

    /// `1204.25`, with no grouping: `toFixed(2)`.
    var plain: String {
        whole + "." + paddedCents
    }

    /// `-1 204,25`: the sign and the localized number, with no currency.
    func signed(_ locale: L10nLocale) -> String {
        sign + localized(locale)
    }

    func localized(_ locale: L10nLocale) -> String {
        L10nFormat.grouped(whole, locale: locale) + (locale == .en ? "." : ",") + paddedCents
    }

    private var paddedCents: String {
        cents < 10 ? "0\(cents)" : String(cents)
    }
}
