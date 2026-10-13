import Foundation

/// Numbers, durations, lists and the calendar's words, written the way the website
/// writes them, in English or Canadian French.
///
/// ⛔ HAND-WRITTEN TABLES, NOT A PLATFORM FORMATTER. `NumberFormatter` and
/// `Date.formatted` read CLDR from the OS, CLDR has moved under the same calls (French
/// grouping went from U+00A0 to U+202F in ICU 72), and corelibs-foundation on Linux
/// ships a different copy from the one on an iPhone. The bytes a customer reads must be
/// a property of this code, so every function here is held byte for byte to
/// `contracts/i18n/format-vectors.json`, which the website generates from its own
/// `money.ts`, `format.ts` and duration formatters (`L10nFormatVectorTests`).
///
/// ⚠️ EVERY FUNCTION TAKES A `locale` THAT DEFAULTS TO ``L10nRuntime/locale``. A
/// screen passes nothing; a test passes the language it is checking.
///
/// ⚠️ THE ONLY SPACE FRENCH USES INSIDE A NUMBER IS U+00A0, the one the glossary
/// names and the website normalizes every Unicode space to.
public enum L10nFormat {
    /// U+00A0, the no-break space.
    static let nbsp = "\u{00A0}"

    // MARK: - Numbers

    /// A whole number inside a catalog sentence (`{count} event types`): plain digits
    /// in English, grouped by no-break spaces in French.
    ///
    /// ⛔ NOT ``integer(_:locale:)``, AND ENGLISH IS UNGROUPED ON PURPOSE. Every count
    /// the core printed before the catalogs existed was `\(n)`, and grouping English
    /// here would change `1204 event types` to `1,204 event types` on a screen that
    /// has always shown the first.
    public static func count(_ value: Int, locale: L10nLocale = L10nRuntime.locale) -> String {
        switch locale {
        case .en: String(value)
        case .frCA: integer(value, locale: .frCA)
        }
    }

    /// `1,204` / `1 204`.
    public static func integer(_ value: Int, locale: L10nLocale = L10nRuntime.locale) -> String {
        let digits = String(value.magnitude)
        return (value < 0 ? "-" : "") + grouped(digits, locale: locale)
    }

    /// `1,204.25` / `1 204,25`: at most three decimals, trailing zeros dropped, as
    /// `Intl.NumberFormat` does with no options. A value that is not finite is the
    /// empty string, as on the web.
    public static func number(_ value: Double, locale: L10nLocale = L10nRuntime.locale) -> String {
        decimal(value, maximumFractionDigits: 3, locale: locale)
    }

    /// `38%` / `38 %`, from a RATIO: `percent(0.38)` is thirty-eight percent. One decimal
    /// at most, as on the web.
    public static func percent(ratio: Double, locale: L10nLocale = L10nRuntime.locale) -> String {
        guard ratio.isFinite else { return "" }
        let number = decimal(ratio * 100, maximumFractionDigits: 1, locale: locale)
        switch locale {
        case .en: return number + "%"
        case .frCA: return number + nbsp + "%"
        }
    }

    /// The digits of `magnitude` with the locale's thousands separator.
    static func grouped(_ digits: String, locale: L10nLocale) -> String {
        let separator = locale == .en ? "," : nbsp
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                out += separator
            }
            out.append(digit)
        }
        return out
    }

    /// A rounded decimal with trailing zeros dropped (`0.5`, `99.9`, `38`).
    ///
    /// ⚠️ ROUNDED ON THE SCALED VALUE, HALF AWAY FROM ZERO, which is `Intl`'s default
    /// rounding mode. The integer and fraction parts are then read as integers, so no
    /// binary fraction is ever printed.
    static func decimal(_ value: Double, maximumFractionDigits: Int, locale: L10nLocale) -> String {
        guard value.isFinite else { return "" }
        var scale = 1.0
        for _ in 0 ..< maximumFractionDigits {
            scale *= 10
        }
        let scaled = (abs(value) * scale).rounded(.toNearestOrAwayFromZero)
        let whole = Int(scaled / scale)
        var fraction = String(Int(scaled - Double(whole) * scale))
        fraction = String(repeating: "0", count: maximumFractionDigits - fraction.count) + fraction
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        let sign = value < 0 ? "-" : ""
        let integerPart = grouped(String(whole), locale: locale)
        guard !fraction.isEmpty else { return sign + integerPart }
        return sign + integerPart + (locale == .en ? "." : ",") + fraction
    }

    // MARK: - Durations

    /// A length of time in minutes and seconds, in the reader's language: `1m 5s`,
    /// `1 min 5 s`. Whole minutes drop the seconds, under a minute reads seconds alone,
    /// and a missing, zero or negative length reads `0m` / `0 min`.
    public static func minutesSeconds(_ seconds: Int?, locale: L10nLocale = L10nRuntime.locale) -> String {
        let minutes: (Int) -> String
        let secondsText: (Int) -> String
        switch locale {
        case .en:
            minutes = { integer($0, locale: .en) + "m" }
            secondsText = { integer($0, locale: .en) + "s" }
        case .frCA:
            minutes = { integer($0, locale: .frCA) + nbsp + "min" }
            secondsText = { integer($0, locale: .frCA) + nbsp + "s" }
        }
        guard let seconds, seconds > 0 else { return minutes(0) }
        let whole = seconds / 60
        let rest = seconds % 60
        if whole == 0 {
            return secondsText(rest)
        }
        return rest == 0 ? minutes(whole) : minutes(whole) + " " + secondsText(rest)
    }

    /// The `duration` string the API sends on a call row (`1m 5s`, `0s`).
    ///
    /// ⛔ A WIRE FORMAT, THE SAME IN EVERY LANGUAGE. The server builds it in English and
    /// the 2.x apps show it as sent; a French screen renders ``minutesSeconds(_:locale:)``
    /// from the raw `durationRaw` instead.
    public static func callDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "0s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    // MARK: - Lists

    /// `A, B and C` / `A, B et C`. One item is itself and none is the empty string.
    ///
    /// ⛔ NO SERIAL COMMA IN ENGLISH. Every list the core wrote before the catalogs read
    /// `a, b and c`, matching the website, and that is what English keeps.
    public static func list(_ items: [String], locale: L10nLocale = L10nRuntime.locale) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        let conjunction = locale == .en ? " and " : " et "
        return items.dropLast().joined(separator: ", ") + conjunction + last
    }

    // MARK: - The calendar's words

    /// `Jan`...`Dec` / `janv.`...`déc.`, for `month` 1...12; nil outside that.
    public static func monthAbbreviation(_ month: Int, locale: L10nLocale = L10nRuntime.locale) -> String? {
        pick(month - 1, locale == .en ? Tables.monthAbbreviationsEn : Tables.monthAbbreviationsFr)
    }

    /// `January`...`December` / `janvier`...`décembre`, for `month` 1...12; nil outside.
    public static func monthName(_ month: Int, locale: L10nLocale = L10nRuntime.locale) -> String? {
        pick(month - 1, locale == .en ? Tables.monthNamesEn : Tables.monthNamesFr)
    }

    /// `Sunday`...`Saturday` / `dimanche`...`samedi`, for `weekday` 1 (Sunday) to 7,
    /// `Calendar`'s numbering; nil outside that.
    ///
    /// ⚠️ FRENCH WEEKDAYS ARE LOWER CASE, as French writes them inside a sentence.
    public static func weekdayName(_ weekday: Int, locale: L10nLocale = L10nRuntime.locale) -> String? {
        pick(weekday - 1, locale == .en ? Tables.weekdayNamesEn : Tables.weekdayNamesFr)
    }

    /// `Sun`...`Sat` / `dim.`...`sam.`, numbered as ``weekdayName(_:locale:)``.
    public static func weekdayAbbreviation(_ weekday: Int, locale: L10nLocale = L10nRuntime.locale) -> String? {
        pick(weekday - 1, locale == .en ? Tables.weekdayAbbreviationsEn : Tables.weekdayAbbreviationsFr)
    }

    /// `AM` before noon and `PM` from noon, for an hour 0...23: the 12-hour clock's
    /// marker as the scheduling stamps write it.
    ///
    /// ⚠️ ENGLISH ONLY, AND UPPER CASE WITHOUT DOTS, UNLIKE ``time(_:timezone:locale:)``'s
    /// `a.m.`: the two are different surfaces of the website and each is copied as it is.
    /// French has no 12-hour clock.
    public static func meridiem(hour: Int) -> String {
        hour < 12 ? "AM" : "PM"
    }

    static func pick(_ index: Int, _ table: [String]) -> String? {
        table.indices.contains(index) ? table[index] : nil
    }
}

/// The calendar's words in both languages, CLDR's `en-CA` and `fr-CA` as the website's
/// node build has them.
enum Tables {
    static let monthAbbreviationsEn = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    static let monthAbbreviationsFr = [
        "janv.", "f\u{E9}vr.", "mars", "avr.", "mai", "juin",
        "juill.", "ao\u{FB}t", "sept.", "oct.", "nov.", "d\u{E9}c.",
    ]
    static let monthNamesEn = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    static let monthNamesFr = [
        "janvier", "f\u{E9}vrier", "mars", "avril", "mai", "juin",
        "juillet", "ao\u{FB}t", "septembre", "octobre", "novembre", "d\u{E9}cembre",
    ]
    static let weekdayNamesEn = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let weekdayNamesFr = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    static let weekdayAbbreviationsEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let weekdayAbbreviationsFr = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
}
